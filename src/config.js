import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { getAgentHome, getConfigPath } from './paths.js';
import { validateRepositoryId } from './security.js';

export function emptyConfig() {
  return {
    schemaVersion: 1,
    agentCli: {
      codex: { enabled: false, path: '' },
      agy: { enabled: false, path: '' },
    },
    repositories: {},
  };
}

function normalizeAgentCli(config) {
  config.agentCli ??= {};
  for (const name of ['codex', 'agy']) {
    config.agentCli[name] ??= {};
    config.agentCli[name].enabled ??= false;
    config.agentCli[name].path ??= '';
  }
  return config;
}

export function validateConfig(config) {
  if (!config || config.schemaVersion !== 1 || typeof config.repositories !== 'object' || Array.isArray(config.repositories)) {
    throw new Error('Unsupported or malformed configuration.');
  }

  normalizeAgentCli(config);
  if (!config.agentCli || typeof config.agentCli !== 'object' || Array.isArray(config.agentCli)) {
    throw new Error('Configuration agentCli must be an object.');
  }
  for (const name of ['codex', 'agy']) {
    const entry = config.agentCli[name];
    if (!entry || typeof entry !== 'object' || typeof entry.enabled !== 'boolean' || typeof entry.path !== 'string') {
      throw new Error(`Agent CLI '${name}' has invalid configuration.`);
    }
    if (entry.path && !path.isAbsolute(entry.path)) throw new Error(`Agent CLI '${name}' path must be absolute.`);
  }

  for (const [id, repo] of Object.entries(config.repositories)) {
    validateRepositoryId(id);
    if (!repo || typeof repo !== 'object' || typeof repo.path !== 'string' || !path.isAbsolute(repo.path)) {
      throw new Error(`Repository '${id}' has an invalid absolute path.`);
    }
    if (repo.github != null && !/^[^/\s]+\/[^/\s]+$/.test(repo.github)) throw new Error(`Repository '${id}' has an invalid GitHub slug.`);
    if (typeof repo.defaultBranch !== 'string' || !repo.defaultBranch.trim()) throw new Error(`Repository '${id}' has no default branch.`);
    const permissions = repo.permissions ?? {};
    for (const key of ['worktrees', 'runScripts', 'commit', 'publish']) {
      if (typeof permissions[key] !== 'boolean') throw new Error(`Repository '${id}' permission '${key}' must be boolean.`);
    }
    if (repo.packageManager != null && !['npm', 'pnpm', 'yarn'].includes(repo.packageManager)) {
      throw new Error(`Repository '${id}' has invalid packageManager.`);
    }
    const allowedScripts = repo.allowedPackageScripts ?? repo.allowedNpmScripts;
    if (!Array.isArray(allowedScripts) || allowedScripts.some((v) => typeof v !== 'string' || (v !== '*' && !/^[A-Za-z0-9_.:@/-]+$/.test(v)))) {
      throw new Error(`Repository '${id}' has invalid allowed package scripts.`);
    }
  }
  return config;
}

export async function loadConfig(env = process.env) {
  const configPath = getConfigPath(env);
  try {
    const config = JSON.parse(await readFile(configPath, 'utf8'));
    return validateConfig(config);
  } catch (error) {
    if (error?.code === 'ENOENT') return emptyConfig();
    throw error;
  }
}

export async function saveConfig(config, env = process.env) {
  validateConfig(config);
  const home = getAgentHome(env);
  const configPath = getConfigPath(env);
  await mkdir(home, { recursive: true });
  const temp = `${configPath}.${process.pid}.${randomUUID()}.tmp`;
  await writeFile(temp, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
  await rename(temp, configPath);
  return configPath;
}
