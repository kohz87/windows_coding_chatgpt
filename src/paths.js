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
