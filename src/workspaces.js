import path from 'node:path';
import { mkdir, realpath, stat } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { getWorktreesRoot } from './paths.js';
import { assertPathInside, validateWorkspaceId } from './security.js';
import { requireGit, runGit } from './git.js';
import { resolveRepository } from './repositories.js';

function cleanLabel(value) {
  return String(value || 'task').toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 36) || 'task';
}

export async function createWorktree(config, repositoryId, label = 'task', base = null, env = process.env) {
  const repo = await resolveRepository(config, repositoryId);
  if (!repo.permissions.worktrees) throw new Error('Worktree creation is disabled for this repository.');
  const id = `${repositoryId}-${randomUUID().replace(/-/g, '').slice(0, 8)}-${cleanLabel(label)}`;
  const root = path.join(getWorktreesRoot(env), repositoryId);
  await mkdir(root, { recursive: true });
  const target = path.join(root, id);
  assertPathInside(root, target);
  const requestedBase = base || (repo.github ? `origin/${repo.defaultBranch}` : repo.defaultBranch);
  if (requestedBase.startsWith('origin/')) {
    const fetch = await runGit(['fetch', 'origin', repo.defaultBranch], repo.path);
    if (!fetch.ok) throw new Error(`Could not fetch ${repo.defaultBranch}: ${fetch.stderr || fetch.error}`);
  }
  const commit = await requireGit(['rev-parse', '--verify', `${requestedBase}^{commit}`], repo.path, 'Could not resolve base commit.');
  const branch = `work/${id}`;
  const add = await runGit(['worktree', 'add', '-b', branch, target, commit], repo.path);
  if (!add.ok) throw new Error(`Could not create worktree: ${add.stderr || add.error}`);
  return { workspaceId: id, repositoryId, branch, path: target, baseCommit: commit };
}

export async function resolveWorkspace(config, workspaceId, env = process.env) {
  validateWorkspaceId(workspaceId);
  const split = Object.keys(config.repositories).sort((a, b) => b.length - a.length).find((id) => workspaceId.startsWith(`${id}-`));
  if (!split) throw new Error('Workspace ID is not associated with an authorized repository.');
  const repo = await resolveRepository(config, split);
  const root = path.join(getWorktreesRoot(env), split);
  const candidate = path.join(root, workspaceId);
  assertPathInside(root, candidate);
  const target = await realpath(candidate);
  assertPathInside(await realpath(root), target);
  const info = await stat(target);
  if (!info.isDirectory()) throw new Error('Workspace path is not a directory.');
  const top = await requireGit(['rev-parse', '--show-toplevel'], target);
  if (path.resolve(top).toLowerCase() !== path.resolve(target).toLowerCase()) throw new Error('Workspace is not a standalone Git worktree root.');
  const branch = await requireGit(['branch', '--show-current'], target);
  if (!branch.startsWith('work/')) throw new Error('Writable workspaces must use a work/* branch.');
  return { workspaceId, repositoryId: split, repository: repo, path: target, branch };
}
