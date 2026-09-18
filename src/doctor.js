import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { loadConfig } from './config.js';
import { getAgentHome, getConfigPath, getWorktreesRoot, getActiveVersionPath, getStableBootstrapPath, getToolchainPath } from './paths.js';
import { resolveRepository } from './repositories.js';

const execFileAsync = promisify(execFile);

async function commandVersion(command, args) {
  try { return String((await execFileAsync(command, args, { windowsHide: true, timeout: 20_000 })).stdout).trim(); }
  catch { return null; }
}

const checks = [];
const add = (name, ok, detail) => checks.push({ name, ok, detail });
add('Node.js', Number(process.versions.node.split('.')[0]) >= 20, process.version);
const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const npxCommand = process.platform === 'win32' ? 'npx.cmd' : 'npx';
const gitVersion = await commandVersion('git', ['--version']);
const npmVersion = await commandVersion(npmCommand, ['--version']);
const npxVersion = await commandVersion(npxCommand, ['--version']);
add('npm', Boolean(npmVersion), npmVersion ?? 'not found');
add('npx', Boolean(npxVersion), npxVersion ?? 'not found');
add('Git', Boolean(gitVersion), gitVersion ?? 'not found');

let config;
try { config = await loadConfig(); add('Configuration', true, getConfigPath()); }
catch (error) { add('Configuration', false, error.message); config = { repositories: {} }; }

try {
  const { readFile, access } = await import('node:fs/promises');
  const active = JSON.parse(await readFile(getActiveVersionPath(), 'utf8'));
  await access(active.path);
  add('Managed agent', true, `v${active.activeVersion} -> ${active.path}`);
} catch {
  add('Managed agent', false, 'not installed or active-version.json is invalid');
}
try {
  const { access } = await import('node:fs/promises');
  await access(getStableBootstrapPath());
  add('Stable MCP bootstrap', true, getStableBootstrapPath());
} catch {
  add('Stable MCP bootstrap', false, 'missing');
}
add('Toolchain registry', true, getToolchainPath());

for (const id of Object.keys(config.repositories ?? {})) {
  try {
    const repo = await resolveRepository(config, id);
    add(`Repository ${id}`, true, `${repo.path}${repo.github ? ` -> ${repo.github}` : ''} [${repo.packageManager ?? 'npm'}]`);
  } catch (error) {
    add(`Repository ${id}`, false, error.message);
  }
}

console.log('Windows Coding Agent Doctor');
console.log(`Home: ${getAgentHome()}`);
console.log(`Worktrees: ${getWorktreesRoot()}\n`);
for (const check of checks) console.log(`${check.ok ? '[PASS]' : '[FAIL]'} ${check.name}: ${check.detail}`);
const failed = checks.filter((v) => !v.ok).length;
console.log(`\n${failed ? `${failed} check(s) failed.` : 'All checks passed.'}`);
process.exitCode = failed ? 1 : 0;
