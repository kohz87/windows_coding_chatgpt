import path from 'node:path';
import { realpath, readFile, access } from 'node:fs/promises';
import { inspectGitRepository, githubRemoteMatches, runGit } from './git.js';
import { validateRepositoryId } from './security.js';

export async function registerRepository(config, id, selectedPath, options = {}) {
  validateRepositoryId(id);
  const inspected = await inspectGitRepository(path.resolve(selectedPath));
  const canonical = await realpath(inspected.path);
  const packageManager = options.packageManager ?? await detectPackageManager(canonical);
  const allowedPackageScripts = Array.from(new Set(options.allowedPackageScripts ?? options.allowedNpmScripts ?? await detectPackageScripts(canonical)));
  const permissions = {
    worktrees: options.permissions?.worktrees ?? true,
    runScripts: options.permissions?.runScripts ?? true,
    commit: options.permissions?.commit ?? true,
    publish: options.permissions?.publish ?? false,
  };
  config.repositories[id] = {
    name: options.name ?? path.basename(canonical),
    path: canonical,
    github: inspected.github,
    defaultBranch: inspected.defaultBranch,
    permissions,
    packageManager,
    allowedPackageScripts,
  };
  return config.repositories[id];
}

export async function resolveRepository(config, repositoryId) {
  validateRepositoryId(repositoryId);
  const repo = config.repositories[repositoryId];
  if (!repo) throw new Error(`Repository '${repositoryId}' is not authorized.`);
  const canonical = await realpath(repo.path);
  const inspected = await inspectGitRepository(canonical);
  if (path.resolve(inspected.path).toLowerCase() !== path.resolve(canonical).toLowerCase()) {
    throw new Error('Configured repository path no longer resolves to the same Git root.');
  }
  if (repo.github) {
    const fetchUrl = await runGit(['remote', 'get-url', 'origin'], canonical);
    const pushUrl = await runGit(['remote', 'get-url', '--push', 'origin'], canonical);
    if (!fetchUrl.ok || !pushUrl.ok || !githubRemoteMatches(fetchUrl.stdout, repo.github) || !githubRemoteMatches(pushUrl.stdout, repo.github)) {
      throw new Error(`Repository '${repositoryId}' origin no longer matches configured GitHub repository '${repo.github}'.`);
    }
  }
  const allowedPackageScripts = repo.allowedPackageScripts ?? repo.allowedNpmScripts ?? [];
  return { id: repositoryId, ...repo, packageManager: repo.packageManager ?? 'npm', allowedPackageScripts, path: canonical };
}

export async function detectPackageManager(repositoryPath) {
  try {
    const pkg = JSON.parse(await readFile(path.join(repositoryPath, 'package.json'), 'utf8'));
    const declared = typeof pkg.packageManager === 'string' ? pkg.packageManager.split('@')[0].toLowerCase() : '';
    if (['npm', 'pnpm', 'yarn'].includes(declared)) return declared;
  } catch {}
  for (const [file, manager] of [['pnpm-lock.yaml', 'pnpm'], ['yarn.lock', 'yarn'], ['package-lock.json', 'npm'], ['npm-shrinkwrap.json', 'npm']]) {
    try { await access(path.join(repositoryPath, file)); return manager; } catch {}
  }
  return 'npm';
}

export async function detectPackageScripts(repositoryPath) {
  try {
    const pkg = JSON.parse(await readFile(path.join(repositoryPath, 'package.json'), 'utf8'));
    const preferred = ['test', 'validate', 'build', 'lint', 'package', 'typecheck', 'check'];
    return preferred.filter((name) => typeof pkg.scripts?.[name] === 'string');
  } catch {
    return [];
  }
}

export const detectNpmScripts = detectPackageScripts;
