import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, readFile, realpath, writeFile } from 'node:fs/promises';
import { validateRelativePath } from '../src/security.js';
import { parseGitHubRemote, runGit } from '../src/git.js';
import { buildGitOperationArgs, buildNpmOperationArgs, validateNpmPackageSpec } from '../src/command-policy.js';
import { emptyConfig, loadConfig, saveConfig } from '../src/config.js';
import { registerRepository, resolveRepository } from '../src/repositories.js';
import { createWorktree, resolveWorkspace } from '../src/workspaces.js';
import { readWorkspaceFile, writeWorkspaceFile } from '../src/files.js';

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
