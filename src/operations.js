import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { runGit, githubRemoteMatches } from './git.js';
import { buildGitOperationArgs, buildNpmOperationArgs } from './command-policy.js';
import { resolveWorkspace } from './workspaces.js';
import { runProcess } from './process.js';

export async function repositoryStatus(repo) {
  const [branch, head, status] = await Promise.all([
    runGit(['branch', '--show-current'], repo.path),
    runGit(['rev-parse', 'HEAD'], repo.path),
    runGit(['status', '--porcelain=v1'], repo.path),
  ]);
  return {
    repositoryId: repo.id,
    branch: branch.ok ? branch.stdout.trim() : null,
    head: head.ok ? head.stdout.trim() : null,
    dirty: status.ok ? Boolean(status.stdout.trim()) : null,
    changes: status.ok ? status.stdout.split(/\r?\n/).filter(Boolean) : [],
  };
}

export async function repositoryRemoteStatus(repo) {
  if (!repo.github) throw new Error('This repository has no configured GitHub origin.');
  const fetchUrl = await runGit(['remote', 'get-url', 'origin'], repo.path);
  const pushUrl = await runGit(['remote', 'get-url', '--push', 'origin'], repo.path);
  if (!fetchUrl.ok || !pushUrl.ok || !githubRemoteMatches(fetchUrl.stdout, repo.github) || !githubRemoteMatches(pushUrl.stdout, repo.github)) {
    throw new Error('Configured origin does not match the locally authorized GitHub repository.');
  }
  const remote = await runGit(['ls-remote', 'origin', `refs/heads/${repo.defaultBranch}`], repo.path);
  if (!remote.ok) throw new Error(`Could not inspect configured remote branch: ${remote.stderr || remote.error}`);
  const line = remote.stdout.trim();
  if (!line) throw new Error(`Configured remote branch '${repo.defaultBranch}' was not found.`);
  const remoteHead = line.split(/\s+/)[0];
  if (!/^[a-f0-9]{40}$/.test(remoteHead)) throw new Error('Configured remote returned an invalid commit SHA.');
  return { repositoryId: repo.id, github: repo.github, branch: repo.defaultBranch, remoteHead };
}

export async function runAllowedPackageScript(config, workspaceId, script, env = process.env) {
  const ws = await resolveWorkspace(config, workspaceId, env);
  if (!ws.repository.permissions.runScripts) throw new Error('Script execution is disabled for this repository.');
  const allowedScripts = ws.repository.allowedPackageScripts ?? ws.repository.allowedNpmScripts ?? [];
  if (!allowedScripts.includes(script)) throw new Error(`Package script '${script}' is not in the repository allowlist.`);
  const pkg = JSON.parse(await readFile(path.join(ws.path, 'package.json'), 'utf8'));
  if (typeof pkg.scripts?.[script] !== 'string') throw new Error(`Package script '${script}' is not defined.`);

  const manager = ws.repository.packageManager ?? 'npm';
  const command = process.platform === 'win32' ? `${manager}.cmd` : manager;
  const result = await runProcess(command, ['run', script], {
    cwd: ws.path,
    timeout: 10 * 60_000,
    maxBuffer: 20 * 1024 * 1024,
    env,
  });
  return {
    ok: result.ok,
    packageManager: manager,
    exitCode: result.exitCode,
    stdout: result.stdout.slice(-100_000),
    stderr: result.stderr.slice(-50_000),
    error: result.error,
  };
}

export async function runAllowedNpmScript(config, workspaceId, script, env = process.env) {
  return runAllowedPackageScript(config, workspaceId, script, env);
}

export async function runGitOperation(config, workspaceId, operation, options = {}, env = process.env) {
  const ws = await resolveWorkspace(config, workspaceId, env);
  let args;

  if (operation === 'fetch') {
    if (!ws.repository.github) throw new Error('Git fetch requires a configured GitHub origin.');
    const branch = options.ref ? String(options.ref).trim() : ws.repository.defaultBranch;
    if (branch !== ws.repository.defaultBranch) throw new Error('Fetch is restricted to the configured default branch.');
    args = ['fetch', 'origin', ws.repository.defaultBranch];
  } else if (operation === 'pull_ff') {
    if (!ws.repository.github) throw new Error('Git pull requires a configured GitHub origin.');
    const branch = options.ref ? String(options.ref).trim() : ws.repository.defaultBranch;
    if (branch !== ws.repository.defaultBranch) throw new Error('Pull is restricted to the configured default branch.');
    const status = await runGit(['status', '--porcelain=v1'], ws.path);
    if (!status.ok || status.stdout.trim()) throw new Error('Fast-forward pull requires a clean isolated worktree.');
    args = ['pull', '--ff-only', 'origin', ws.repository.defaultBranch];
  } else {
    args = buildGitOperationArgs(operation, options);
  }

  const result = await runGit(args, ws.path, 10 * 60_000);
  return {
    ok: result.ok,
    operation,
    args,
    exitCode: result.exitCode,
    stdout: result.stdout.slice(-100_000),
    stderr: result.stderr.slice(-50_000),
    error: result.error,
  };
}

export async function runNpmOperation(config, workspaceId, operation, options = {}, env = process.env) {
  const ws = await resolveWorkspace(config, workspaceId, env);
  if (!ws.repository.permissions.runScripts) throw new Error('Package operations are disabled for this repository.');
  if ((ws.repository.packageManager ?? 'npm') !== 'npm') {
    throw new Error(`Repository uses '${ws.repository.packageManager}', so npm_operation is disabled to avoid mutating a different package-manager lockfile.`);
  }

  const args = buildNpmOperationArgs(operation, options);
  const command = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const result = await runProcess(command, args, {
    cwd: ws.path,
    timeout: 10 * 60_000,
    maxBuffer: 20 * 1024 * 1024,
    env,
  });
  return {
    ok: result.ok,
    operation,
    args,
    exitCode: result.exitCode,
    stdout: result.stdout.slice(-100_000),
    stderr: result.stderr.slice(-50_000),
    error: result.error,
  };
}

export async function commitWorkspace(config, workspaceId, expectedHead, message, env = process.env) {
  const ws = await resolveWorkspace(config, workspaceId, env);
  if (!ws.repository.permissions.commit) throw new Error('Commits are disabled for this repository.');
  if (!message || /[\r\n\0]/.test(message)) throw new Error('Commit message must be one non-empty line.');
  const head = await runGit(['rev-parse', 'HEAD'], ws.path);
  if (!head.ok || head.stdout.trim() !== expectedHead) throw new Error('Workspace HEAD changed since inspection.');
  const status = await runGit(['status', '--porcelain=v1'], ws.path);
  if (!status.ok || !status.stdout.trim()) throw new Error('Workspace is clean; there is nothing to commit.');
  const staged = await runGit(['diff', '--cached', '--name-only'], ws.path);
  if (!staged.ok || staged.stdout.trim()) throw new Error('Pre-staged changes are not accepted by guarded commit.');
  const add = await runGit(['add', '-A'], ws.path);
  if (!add.ok) throw new Error(`git add failed: ${add.stderr || add.error}`);
  const commit = await runGit(['commit', '-m', message], ws.path);
  if (!commit.ok) {
    await runGit(['restore', '--staged', '--', '.'], ws.path);
    throw new Error(`git commit failed: ${commit.stderr || commit.error}`);
  }
  const next = await runGit(['rev-parse', 'HEAD'], ws.path);
  return { commitSha: next.stdout.trim(), previousHead: expectedHead };
}

export async function publishWorkspace(config, workspaceId, expectedHead, expectedRemoteHead, confirmation, env = process.env) {
  const ws = await resolveWorkspace(config, workspaceId, env);
  const repo = ws.repository;
  if (!repo.permissions.publish) throw new Error('Publishing is disabled for this repository. Enable it locally first.');
  if (!repo.github) throw new Error('Publishing requires a configured GitHub origin.');
  if (confirmation !== 'PUBLISH_CONFIGURED_REMOTE_FAST_FORWARD') throw new Error('Explicit publication confirmation is required.');
  const head = await runGit(['rev-parse', 'HEAD'], ws.path);
  const status = await runGit(['status', '--porcelain=v1'], ws.path);
  if (!head.ok || head.stdout.trim() !== expectedHead) throw new Error('Workspace HEAD changed since inspection.');
  if (!status.ok || status.stdout.trim()) throw new Error('Publishing requires a clean worktree and index.');
  const fetchUrl = await runGit(['remote', 'get-url', 'origin'], ws.path);
  const pushUrl = await runGit(['remote', 'get-url', '--push', 'origin'], ws.path);
  if (!fetchUrl.ok || !pushUrl.ok || !githubRemoteMatches(fetchUrl.stdout, repo.github) || !githubRemoteMatches(pushUrl.stdout, repo.github)) {
    throw new Error('Configured origin does not match the locally authorized GitHub repository.');
  }
  const fetch = await runGit(['fetch', 'origin', repo.defaultBranch], ws.path);
  if (!fetch.ok) throw new Error(`Fetch failed: ${fetch.stderr || fetch.error}`);
  const remote = await runGit(['rev-parse', `refs/remotes/origin/${repo.defaultBranch}`], ws.path);
  if (!remote.ok) throw new Error('Could not resolve fetched remote branch.');
  const remoteHead = remote.stdout.trim();
  if (remoteHead !== expectedRemoteHead) throw new Error(`Remote branch changed since inspection: ${remoteHead}`);
  const ancestor = await runGit(['merge-base', '--is-ancestor', remoteHead, expectedHead], ws.path);
  if (!ancestor.ok) throw new Error('Configured remote branch is not an ancestor of the accepted commit.');
  const push = await runGit(['push', 'origin', `${expectedHead}:refs/heads/${repo.defaultBranch}`], ws.path);
  if (!push.ok) throw new Error(`Non-force push failed: ${push.stderr || push.error}`);
  const verify = await runGit(['ls-remote', 'origin', `refs/heads/${repo.defaultBranch}`], ws.path);
  const final = verify.ok ? verify.stdout.trim().split(/\s+/)[0] : null;
  if (final !== expectedHead) throw new Error('Remote verification did not match the accepted commit.');
  return { repository: repo.github, branch: repo.defaultBranch, previousRemoteHead: remoteHead, finalRemoteHead: final, nonForce: true };
}
