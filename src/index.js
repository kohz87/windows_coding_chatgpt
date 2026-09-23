import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { readdir } from 'node:fs/promises';
import { loadConfig } from './config.js';
import { resolveRepository } from './repositories.js';
import { createWorktree, resolveWorkspace } from './workspaces.js';
import { readWorkspaceFile, writeWorkspaceFile, deleteWorkspaceFile } from './files.js';
import { securePath } from './security.js';
import { runGit } from './git.js';
import { repositoryStatus, repositoryRemoteStatus, runAllowedPackageScript, runAllowedNpmScript, runGitOperation, runNpmOperation, commitWorkspace, publishWorkspace } from './operations.js';
import { agentCliStatus, runAgentCli } from './agent-cli.js';

const VERSION = '0.1.8';
const text = (value) => ({ content: [{ type: 'text', text: JSON.stringify(value, null, 2) }], structuredContent: value });
const fail = (error) => ({ isError: true, content: [{ type: 'text', text: error?.message ?? String(error) }] });
const guarded = (fn) => async (args) => { try { return text(await fn(args)); } catch (error) { return fail(error); } };

function createServer() {
  const server = new McpServer(
    { name: 'windows-coding-agent', version: VERSION },
    { instructions: 'Operate only on repositories locally authorized by the user. Mutate files only in isolated worktrees. Never assume a path or remote that is not present in the local registry.' },
  );

  server.registerTool('ping', { description: 'Check whether Windows Coding Agent is online.', inputSchema: z.object({}) }, async () => text({ ok: true, version: VERSION }));

  server.registerTool('repositories_list', {
    description: 'List locally authorized repositories and their effective permissions.',
    inputSchema: z.object({}),
  }, guarded(async () => {
    const config = await loadConfig();
    return { repositories: Object.entries(config.repositories).map(([id, repo]) => ({ id, name: repo.name, path: repo.path, github: repo.github, defaultBranch: repo.defaultBranch, packageManager: repo.packageManager ?? 'npm', permissions: repo.permissions, allowedPackageScripts: repo.allowedPackageScripts ?? repo.allowedNpmScripts ?? [] })) };
  }));

  server.registerTool('repository_status', {
    description: 'Inspect branch, HEAD, and working-tree state of one authorized canonical repository. Canonical repositories are read-only to mutation tools.',
    inputSchema: z.object({ repositoryId: z.string() }),
  }, guarded(async ({ repositoryId }) => {
    const config = await loadConfig();
    return repositoryStatus(await resolveRepository(config, repositoryId));
  }));

  server.registerTool('repository_remote_status', {
    description: 'Inspect the exact configured GitHub default-branch SHA without mutating the repository. Use the returned remoteHead as the expectedRemoteHead for guarded publication.',
    inputSchema: z.object({ repositoryId: z.string() }),
  }, guarded(async ({ repositoryId }) => {
    const config = await loadConfig();
    return repositoryRemoteStatus(await resolveRepository(config, repositoryId));
  }));

  server.registerTool('repository_file_read', {
    description: 'Read a UTF-8 file from an authorized canonical repository. This tool never writes canonical repositories.',
    inputSchema: z.object({ repositoryId: z.string(), path: z.string() }),
  }, guarded(async ({ repositoryId, path }) => {
    const config = await loadConfig();
    const repo = await resolveRepository(config, repositoryId);
    return { repositoryId, path, ...await readWorkspaceFile(repo.path, path) };
  }));

  server.registerTool('worktree_create', {
    description: 'Create an isolated writable work/* Git worktree from the configured repository.',
    inputSchema: z.object({ repositoryId: z.string(), label: z.string().max(40).default('task'), base: z.string().nullable().default(null) }),
  }, guarded(async ({ repositoryId, label, base }) => createWorktree(await loadConfig(), repositoryId, label, base)));

  server.registerTool('worktree_status', {
    description: 'Inspect one isolated worktree, including exact HEAD, branch, dirty state, and changes.',
    inputSchema: z.object({ workspaceId: z.string() }),
  }, guarded(async ({ workspaceId }) => {
    const config = await loadConfig();
    const ws = await resolveWorkspace(config, workspaceId);
    const [head, status] = await Promise.all([runGit(['rev-parse', 'HEAD'], ws.path), runGit(['status', '--porcelain=v1'], ws.path)]);
    return { workspaceId, repositoryId: ws.repositoryId, branch: ws.branch, head: head.stdout.trim(), dirty: Boolean(status.stdout.trim()), changes: status.stdout.split(/\r?\n/).filter(Boolean) };
  }));

  server.registerTool('file_read', {
    description: 'Read a UTF-8 file inside one isolated writable worktree and return its SHA-256 concurrency token.',
    inputSchema: z.object({ workspaceId: z.string(), path: z.string() }),
  }, guarded(async ({ workspaceId, path }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    return { workspaceId, path, ...await readWorkspaceFile(ws.path, path) };
  }));

  server.registerTool('file_list', {
    description: 'List a directory inside an isolated worktree. Path traversal, .git, junction escape, and absolute paths are blocked.',
    inputSchema: z.object({ workspaceId: z.string(), path: z.string().default('.') }),
  }, guarded(async ({ workspaceId, path }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    const target = await securePath(ws.path, path, { allowDot: true });
    const entries = await readdir(target, { withFileTypes: true });
    return { workspaceId, path, entries: entries.map((e) => ({ name: e.name, type: e.isDirectory() ? 'directory' : e.isFile() ? 'file' : 'other' })) };
  }));

  server.registerTool('file_replace', {
    description: 'Replace an existing UTF-8 file inside an isolated worktree using a required SHA-256 concurrency guard.',
    inputSchema: z.object({ workspaceId: z.string(), path: z.string(), expectedSha256: z.string().regex(/^[a-f0-9]{64}$/), content: z.string() }),
  }, guarded(async ({ workspaceId, path, expectedSha256, content }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    return { workspaceId, path, ...await writeWorkspaceFile(ws.path, path, content, { expectedSha256 }) };
  }));

  server.registerTool('file_create', {
    description: 'Create a new UTF-8 file inside an isolated worktree. Parent directory must already exist.',
    inputSchema: z.object({ workspaceId: z.string(), path: z.string(), content: z.string() }),
  }, guarded(async ({ workspaceId, path, content }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    return { workspaceId, path, ...await writeWorkspaceFile(ws.path, path, content, { create: true }) };
  }));

  server.registerTool('file_delete', {
    description: 'Delete one SHA-guarded regular file inside an isolated worktree.',
    inputSchema: z.object({ workspaceId: z.string(), path: z.string(), expectedSha256: z.string().regex(/^[a-f0-9]{64}$/) }),
  }, guarded(async ({ workspaceId, path, expectedSha256 }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    return { workspaceId, path, deleted: true, deletedSha256: await deleteWorkspaceFile(ws.path, path, expectedSha256) };
  }));

  server.registerTool('git_diff_check', {
    description: 'Run exactly git diff --check inside an isolated worktree.',
    inputSchema: z.object({ workspaceId: z.string() }),
  }, guarded(async ({ workspaceId }) => {
    const ws = await resolveWorkspace(await loadConfig(), workspaceId);
    const result = await runGit(['diff', '--check'], ws.path);
    return { ok: result.ok, exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr };
  }));

  server.registerTool('run_package_script', {
    description: 'Run one locally allowlisted package script using the repository package manager detected during local authorization (npm, pnpm, or yarn).',
    inputSchema: z.object({ workspaceId: z.string(), script: z.string() }),
  }, guarded(async ({ workspaceId, script }) => runAllowedPackageScript(await loadConfig(), workspaceId, script)));

  server.registerTool('run_npm_script', {
    description: 'Backward-compatible alias for run_package_script. The detected repository package manager is used even when it is not npm.',
    inputSchema: z.object({ workspaceId: z.string(), script: z.string() }),
  }, guarded(async ({ workspaceId, script }) => runAllowedNpmScript(await loadConfig(), workspaceId, script)));

  server.registerTool('git_operation', {
    description: 'Run a bounded Git operation inside an isolated worktree. Supports status/diff/log/show/listing, configured-origin fetch/ff-only pull, restore, no-commit cherry-pick/revert, and abort operations. Arbitrary remotes, refspecs, force operations, reset, rebase, and direct canonical mutations are not exposed.',
    inputSchema: z.object({
      workspaceId: z.string(),
      operation: z.enum(['status', 'diff', 'log', 'show', 'ls_files', 'branch_list', 'tag_list', 'fetch', 'pull_ff', 'restore', 'restore_staged', 'cherry_pick_no_commit', 'cherry_pick_abort', 'revert_no_commit', 'revert_abort']),
      ref: z.string().nullable().default(null),
      paths: z.array(z.string()).max(100).default([]),
      staged: z.boolean().default(false),
      maxCount: z.number().int().min(1).max(200).default(30),
    }),
  }, guarded(async ({ workspaceId, operation, ref, paths, staged, maxCount }) =>
    runGitOperation(await loadConfig(), workspaceId, operation, { ref, paths, staged, maxCount })));

  server.registerTool('npm_operation', {
    description: 'Run a bounded npm dependency/query operation inside an isolated worktree. Dependency mutations use --ignore-scripts; repository-defined executable scripts remain restricted to run_package_script/run_npm_script allowlists.',
    inputSchema: z.object({
      workspaceId: z.string(),
      operation: z.enum(['ci', 'install', 'install_packages', 'uninstall_packages', 'update', 'dedupe', 'prune', 'audit', 'audit_fix', 'outdated', 'list', 'view']),
      packages: z.array(z.string()).max(50).default([]),
      dev: z.boolean().default(false),
      exact: z.boolean().default(false),
      depth: z.number().int().min(0).max(10).default(0),
      field: z.string().nullable().default(null),
    }),
  }, guarded(async ({ workspaceId, operation, packages, dev, exact, depth, field }) =>
    runNpmOperation(await loadConfig(), workspaceId, operation, { packages, dev, exact, depth, field })));

  server.registerTool('agent_cli_status', {
    description: 'Inspect locally configured Codex CLI and Antigravity CLI launch permissions and availability. Enable/disable remains a local human-only Start-Agent action.',
    inputSchema: z.object({}),
  }, guarded(async () => agentCliStatus(await loadConfig())));

  server.registerTool('agent_run', {
    description: 'Run a locally enabled coding-agent CLI inside one isolated controller-created worktree. Supported agents are codex and agy. The tool cannot enable an agent, change its executable path, escape the worktree, or request unrestricted permission bypasses.',
    inputSchema: z.object({
      workspaceId: z.string(),
      agent: z.enum(['codex', 'agy']),
      prompt: z.string().min(1).max(100000),
      model: z.string().max(120).nullable().default(null),
      effort: z.enum(['low', 'medium', 'high']).nullable().default(null),
      timeoutSeconds: z.number().int().min(30).max(3600).default(1200),
    }),
  }, guarded(async ({ workspaceId, agent, prompt, model, effort, timeoutSeconds }) =>
    runAgentCli(await loadConfig(), workspaceId, agent, prompt, { model, effort, timeoutSeconds })));

  server.registerTool('repo_commit', {
    description: 'Create one local non-amend commit from an isolated worktree after exact HEAD verification. No push is performed.',
    inputSchema: z.object({ workspaceId: z.string(), expectedHead: z.string().regex(/^[a-f0-9]{40,64}$/), message: z.string().min(1).max(200) }),
  }, guarded(async ({ workspaceId, expectedHead, message }) => commitWorkspace(await loadConfig(), workspaceId, expectedHead, message)));

  server.registerTool('repo_publish', {
    description: 'Publish one accepted clean worktree HEAD to the locally configured GitHub default branch using a normal non-force fast-forward push. Publication must first be enabled locally. Obtain expectedRemoteHead from repository_remote_status immediately before publication.',
    inputSchema: z.object({ workspaceId: z.string(), expectedHead: z.string().regex(/^[a-f0-9]{40}$/), expectedRemoteHead: z.string().regex(/^[a-f0-9]{40}$/), confirmation: z.literal('PUBLISH_CONFIGURED_REMOTE_FAST_FORWARD') }),
  }, guarded(async ({ workspaceId, expectedHead, expectedRemoteHead, confirmation }) => publishWorkspace(await loadConfig(), workspaceId, expectedHead, expectedRemoteHead, confirmation)));

  return server;
}

void serveStdio(createServer);
console.error(`Windows Coding Agent v${VERSION} running.`);
