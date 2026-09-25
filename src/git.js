import { runProcess } from './process.js';

const DEFAULT_TIMEOUT = 120_000;

export async function runGit(args, cwd, timeout = DEFAULT_TIMEOUT, env = process.env) {
  return runProcess(process.platform === 'win32' ? 'git.exe' : 'git', args, {
    cwd,
    windowsHide: true,
    timeout,
    env,
  });
}

export async function requireGit(args, cwd, message = 'Git command failed.') {
  const result = await runGit(args, cwd);
  if (!result.ok) throw new Error(`${message} ${result.stderr || result.error}`.trim());
  return result.stdout.trim();
}

export function parseGitHubRemote(value) {
  if (typeof value !== 'string') return null;
  const remote = value.trim();
  const patterns = [
    /^https:\/\/github\.com\/([^/]+)\/([^/]+?)(?:\.git)?\/?$/i,
    /^ssh:\/\/git@github\.com\/([^/]+)\/([^/]+?)(?:\.git)?\/?$/i,
    /^git@github\.com:([^/]+)\/([^/]+?)(?:\.git)?$/i,
  ];
  for (const pattern of patterns) {
    const match = remote.match(pattern);
    if (match) return `${match[1]}/${match[2]}`;
  }
  return null;
}

export function githubRemoteMatches(value, expected) {
  const parsed = parseGitHubRemote(value);
  return parsed?.toLowerCase() === String(expected ?? '').toLowerCase();
}

export async function inspectGitRepository(repositoryPath) {
  const inside = await runGit(['rev-parse', '--is-inside-work-tree'], repositoryPath);
  if (!inside.ok || inside.stdout.trim() !== 'true') throw new Error('Selected directory is not a Git repository.');

  const top = await requireGit(['rev-parse', '--show-toplevel'], repositoryPath);
  const origin = await runGit(['remote', 'get-url', 'origin'], top);
  const github = origin.ok ? parseGitHubRemote(origin.stdout) : null;
  const current = await runGit(['branch', '--show-current'], top);
  let defaultBranch = null;
  const remoteHead = await runGit(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], top);
  if (remoteHead.ok) defaultBranch = remoteHead.stdout.trim().replace(/^origin\//, '');
  if (!defaultBranch) defaultBranch = current.ok && current.stdout.trim() ? current.stdout.trim() : 'main';

  return {
    path: top,
    origin: origin.ok ? origin.stdout.trim() : null,
    github,
    currentBranch: current.ok ? current.stdout.trim() : null,
    defaultBranch,
  };
}
