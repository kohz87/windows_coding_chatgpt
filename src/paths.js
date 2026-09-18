import os from 'node:os';
import path from 'node:path';

export function getAgentHome(env = process.env) {
  if (env.WINDOWS_CODING_AGENT_HOME) return path.resolve(env.WINDOWS_CODING_AGENT_HOME);
  return path.join(os.homedir(), '.windows-coding-agent');
}

export function getConfigPath(env = process.env) {
  return path.join(getAgentHome(env), 'config.json');
}

export function getWorktreesRoot(env = process.env) {
  return path.join(getAgentHome(env), 'worktrees');
}

export function getToolchainPath(env = process.env) {
  return path.join(getAgentHome(env), 'toolchain.json');
}

export function getActiveVersionPath(env = process.env) {
  return path.join(getAgentHome(env), 'active-version.json');
}

export function getVersionsRoot(env = process.env) {
  return path.join(getAgentHome(env), 'versions');
}

export function getStableBootstrapPath(env = process.env) {
  return path.join(getAgentHome(env), 'bootstrap', 'mcp-loader.mjs');
}

export function getStableBinRoot(env = process.env) {
  return path.join(getAgentHome(env), 'bin');
}
