import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, readFile, realpath, writeFile } from 'node:fs/promises';
import { validateRelativePath } from '../src/security.js';
import { parseGitHubRemote, runGit } from '../src/git.js';
import { buildGitOperationArgs, buildNpmOperationArgs, validateNpmPackageSpec } from '../src/command-policy.js';
import { buildAgentArgs, validateAgentName } from '../src/agent-cli.js';
import { emptyConfig, loadConfig, saveConfig } from '../src/config.js';
import { registerRepository, resolveRepository } from '../src/repositories.js';
import { createWorktree, resolveWorkspace } from '../src/workspaces.js';
import { readWorkspaceFile, writeWorkspaceFile } from '../src/files.js';
import { runProcess } from '../src/process.js';
import { runAllowedPackageScript } from '../src/operations.js';

async function git(args, cwd) {
  const result = await runGit(args, cwd);
  assert.equal(result.ok, true, result.stderr || result.error);
  return result.stdout.trim();
}

async function makeRepo() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'wca-test-'));
  await git(['init', '-b', 'main'], root);
  await git(['config', 'user.name', 'WCA Test'], root);
  await git(['config', 'user.email', 'wca-test@local.invalid'], root);
  await writeFile(path.join(root, 'hello.txt'), 'hello\n');
  await writeFile(path.join(root, 'package.json'), JSON.stringify({ packageManager: 'npm@11.0.0', scripts: { test: 'node -e "process.exit(0)"', build: 'node -e "process.exit(0)"' } }, null, 2));
  await writeFile(path.join(root, 'package-lock.json'), JSON.stringify({ lockfileVersion: 3 }, null, 2));
  await git(['add', '-A'], root);
  await git(['commit', '-m', 'initial'], root);
  return root;
}

test('GitHub remote parser accepts HTTPS and SSH', () => {
  assert.equal(parseGitHubRemote('https://github.com/example/project.git'), 'example/project');
  assert.equal(parseGitHubRemote('git@github.com:example/project.git'), 'example/project');
  assert.equal(parseGitHubRemote('ssh://git@github.com/example/project.git'), 'example/project');
  assert.equal(parseGitHubRemote('https://gitlab.com/example/project.git'), null);
});

test('relative-path guard rejects escape and Git metadata', () => {
  for (const value of ['../x', 'src/../x', 'C:\\Windows\\x', '\\\\server\\share', '.git/config', 'src/file.txt:stream', 'CON.txt']) {
    assert.throws(() => validateRelativePath(value));
  }
  assert.equal(validateRelativePath('src/file.js').endsWith(path.join('src', 'file.js')), true);
});

test('configuration persists repository registry', async () => {
  const home = await mkdtemp(path.join(os.tmpdir(), 'wca-home-'));
  const env = { ...process.env, WINDOWS_CODING_AGENT_HOME: home };
  const config = emptyConfig();
  config.repositories.demo = {
    name: 'Demo', path: path.resolve(home), github: null, defaultBranch: 'main',
    permissions: { worktrees: true, runScripts: true, commit: true, publish: false }, packageManager: 'npm', allowedPackageScripts: [],
  };
  await saveConfig(config, env);
  assert.deepEqual(await loadConfig(env), config);
});

test('authorized local-only repository can create isolated guarded worktree', async () => {
  const repoPath = await makeRepo();
  const canonicalRepoPath = await realpath(repoPath);
  const home = await mkdtemp(path.join(os.tmpdir(), 'wca-home-'));
  const env = { ...process.env, WINDOWS_CODING_AGENT_HOME: home };
  const config = emptyConfig();
  const repo = await registerRepository(config, 'demo', repoPath, { permissions: { publish: false } });
  assert.equal(repo.defaultBranch, 'main');
  assert.equal(repo.packageManager, 'npm');
  assert.deepEqual(repo.allowedPackageScripts.sort(), ['build', 'test']);
  assert.equal((await resolveRepository(config, 'demo')).path, canonicalRepoPath);
  const workspace = await createWorktree(config, 'demo', 'edit', null, env);
  const ws = await resolveWorkspace(config, workspace.workspaceId, env);
  const before = await readWorkspaceFile(ws.path, 'hello.txt');
  await writeWorkspaceFile(ws.path, 'hello.txt', 'changed\n', { expectedSha256: before.sha256 });
  assert.equal(await readFile(path.join(ws.path, 'hello.txt'), 'utf8'), 'changed\n');
  assert.equal(await readFile(path.join(canonicalRepoPath, 'hello.txt'), 'utf8'), 'hello\n');
});


test('bounded Git operation policy allows useful commands and blocks unsafe refs/paths', () => {
  assert.deepEqual(buildGitOperationArgs('status'), ['status', '--short', '--branch']);
  assert.deepEqual(buildGitOperationArgs('diff', { staged: true, paths: ['src/index.js'] }), ['diff', '--no-ext-diff', '--cached', '--', 'src/index.js']);
  assert.deepEqual(buildGitOperationArgs('cherry_pick_no_commit', { ref: '0123456789abcdef0123456789abcdef01234567' }), ['cherry-pick', '--no-commit', '0123456789abcdef0123456789abcdef01234567']);
  assert.throws(() => buildGitOperationArgs('reset', {}), /Unsupported Git operation/);
  assert.throws(() => buildGitOperationArgs('show', { ref: '--help' }), /Invalid Git ref/);
  assert.throws(() => buildGitOperationArgs('diff', { paths: ['../outside'] }), /Traversal/);
});

test('bounded npm policy disables lifecycle scripts for dependency mutations', () => {
  assert.deepEqual(buildNpmOperationArgs('ci'), ['ci', '--ignore-scripts']);
  assert.deepEqual(
    buildNpmOperationArgs('install_packages', { packages: ['zod@^4.0.0', '@scope/pkg@1.2.3'], dev: true, exact: true }),
    ['install', '--ignore-scripts', '--save-dev', '--save-exact', 'zod@^4.0.0', '@scope/pkg@1.2.3'],
  );
  assert.deepEqual(buildNpmOperationArgs('audit_fix'), ['audit', 'fix', '--ignore-scripts']);
  assert.throws(() => buildNpmOperationArgs('exec', { packages: ['tool'] }), /Unsupported npm operation/);
  assert.throws(() => validateNpmPackageSpec('pkg --foreground-scripts'), /Unsafe npm package spec/);
  assert.throws(() => validateNpmPackageSpec('https://example.com/pkg.tgz'), /Unsafe npm package spec/);
});


test('wildcard package-script policy runs any script declared by the authorized repository', async () => {
  const repoPath = await makeRepo();
  const pkgPath = path.join(repoPath, 'package.json');
  const pkg = JSON.parse(await readFile(pkgPath, 'utf8'));
  pkg.scripts['measure:prompts'] = 'node -e "process.stdout.write(\'measured\')"';
  await writeFile(pkgPath, JSON.stringify(pkg, null, 2));
  await git(['add', 'package.json'], repoPath);
  await git(['commit', '-m', 'add metrics script'], repoPath);

  const home = await mkdtemp(path.join(os.tmpdir(), 'wca-home-'));
  const env = { ...process.env, WINDOWS_CODING_AGENT_HOME: home };
  const config = emptyConfig();
  const repo = await registerRepository(config, 'demo', repoPath, {
    allowedPackageScripts: ['*'],
    permissions: { publish: false },
  });
  assert.deepEqual(repo.allowedPackageScripts, ['*']);
  await saveConfig(config, env);
  const workspace = await createWorktree(config, 'demo', 'wildcard-script', null, env);

  const result = await runAllowedPackageScript(config, workspace.workspaceId, 'measure:prompts', env);
  assert.equal(result.ok, true, result.stderr || result.error);
  assert.match(result.stdout, /measured/);
  await assert.rejects(
    () => runAllowedPackageScript(config, workspace.workspaceId, 'not-defined', env),
    /not defined/,
  );
});

test('exact package-script allowlist still rejects other declared scripts', async () => {
  const repoPath = await makeRepo();
  const home = await mkdtemp(path.join(os.tmpdir(), 'wca-home-'));
  const env = { ...process.env, WINDOWS_CODING_AGENT_HOME: home };
  const config = emptyConfig();
  await registerRepository(config, 'demo', repoPath, {
    allowedPackageScripts: ['test'],
    permissions: { publish: false },
  });
  await saveConfig(config, env);
  const workspace = await createWorktree(config, 'demo', 'exact-script', null, env);
  await assert.rejects(
    () => runAllowedPackageScript(config, workspace.workspaceId, 'build', env),
    /not in the repository allowlist/,
  );
});

test('coding-agent CLI configuration defaults to locally disabled', () => {
  const config = emptyConfig();
  assert.equal(config.agentCli.codex.enabled, false);
  assert.equal(config.agentCli.agy.enabled, false);
  assert.equal(config.agentCli.codex.path, '');
  assert.equal(config.agentCli.agy.path, '');
});

test('coding-agent CLI argument builders stay bounded to safe execution modes', () => {
  const codex = buildAgentArgs('codex', 'Fix the tests', { model: 'gpt-5.6-sol', effort: 'high' }, 'C:\\work');
  assert.deepEqual(codex, [
    'exec', '--sandbox', 'workspace-write',
    '--model', 'gpt-5.6-sol',
    '--config', 'model_reasoning_effort="high"',
    '-',
  ]);
  assert.equal(codex.includes('danger-full-access'), false);

  const agy = buildAgentArgs('agy', 'Audit the code', { model: null, effort: 'medium' }, 'C:\\work');
  assert.deepEqual(agy, [
    '--input-format', 'stream-json',
    '--output-format', 'stream-json',
    '--cwd', 'C:\\work',
    '--sandbox',
    '--effort', 'medium',
  ]);
  assert.equal(agy.includes('--dangerously-skip-permissions'), false);

  assert.throws(() => validateAgentName('powershell'), /Unsupported coding agent/);
  assert.throws(() => buildAgentArgs('codex', 'x', { model: '--bad', effort: null }, 'C:\\work'), /Invalid model/);
});


test('runProcess launches Windows cmd wrappers without execFile EINVAL', { skip: process.platform !== 'win32' }, async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'wca-cmd-test-'));
  const script = path.join(root, 'probe.cmd');
  await writeFile(script, '@echo off\r\necho WRAPPER_OK %~1\r\n', 'utf8');
  const result = await runProcess(script, ['ARG_OK'], { timeout: 20_000 });
  assert.equal(result.ok, true, result.stderr || result.error);
  assert.match(result.stdout, /WRAPPER_OK ARG_OK/);
});


test('single human-facing launcher owns ChatGPT and repository management entry points', async () => {
  const launcher = await readFile(new URL('../Windows-Coding-Agent.cmd', import.meta.url), 'utf8');
  const control = await readFile(new URL('../Windows-Coding-Agent.ps1', import.meta.url), 'utf8');
  const bootstrap = await readFile(new URL('../bootstrap/launch.ps1', import.meta.url), 'utf8');
  const toolchain = await readFile(new URL('../Toolchain.ps1', import.meta.url), 'utf8');
  const packager = await readFile(new URL('../scripts/package-release.ps1', import.meta.url), 'utf8');
  const legacyShim = await readFile(new URL('../Connect-ChatGPT.ps1', import.meta.url), 'utf8');
  const updater = await readFile(new URL('../Update.ps1', import.meta.url), 'utf8');

  assert.match(launcher, /Windows-Coding-Agent\.ps1/);
  assert.match(control, /function Invoke-RepositoryManager/);
  assert.match(control, /\[4\] Manage repositories/);
  assert.match(bootstrap, /'Control'.*Windows-Coding-Agent\.ps1/);
  assert.match(bootstrap, /'Manage'.*-Open Repositories/);
  assert.match(toolchain, /Get-WcaStableLauncherPath[\s\S]*Windows-Coding-Agent\.cmd/);
  assert.match(toolchain, /Windows-Coding-Agent\.cmd'\) -Mode 'Control'/);
  assert.doesNotMatch(packager, /Start-Agent\.cmd/);
  assert.match(packager, /Connect-ChatGPT\.ps1/);
  assert.match(legacyShim, /Windows-Coding-Agent\.ps1/);
  assert.doesNotMatch(legacyShim, /function Invoke-/);
  assert.match(updater, /candidateToolchain[\s\S]*\. \$candidateToolchain[\s\S]*Install-WcaManagedVersion/);
});


test('unified PowerShell control panel self-test passes on Windows', { skip: process.platform !== 'win32' }, async () => {
  const script = path.resolve('Windows-Coding-Agent.ps1');
  const result = await runProcess('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', script,
    '-SelfTest',
  ], { timeout: 60_000 });
  assert.equal(result.ok, true, result.stderr || result.error);
  assert.match(result.stdout, /SELFTEST OK/);
});
