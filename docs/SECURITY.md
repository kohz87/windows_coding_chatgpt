# Security model

Windows Coding Agent is designed around explicit local authorization and narrow capabilities rather than unrestricted shell/filesystem access.

## Trust boundary

The human operator controls which local Git repository directories are authorized.

An MCP client can refer to a repository by its configured ID, but cannot provide a new absolute repository path to coding tools.

## Canonical repositories are read-only to mutations

Canonical repository roots may be inspected, but mutation tools operate only on isolated worktrees created beneath:

```text
%USERPROFILE%\.windows-coding-agent\worktrees\
```

or the root selected through `WINDOWS_CODING_AGENT_HOME`.

## Path protections

Repository-relative paths reject:

- absolute paths
- UNC paths
- `..` traversal
- empty path segments
- `.git` metadata access
- Windows alternate data streams
- trailing-dot/space aliases
- Windows device names such as `CON`, `NUL`, `COM1`, and `LPT1`

Resolved paths are checked again using real filesystem paths so symlink/junction escape cannot simply bypass lexical validation.

## Write concurrency guards

Replacing or deleting an existing file requires the SHA-256 returned by the prior read.

If another process changes the file between inspection and mutation, the operation is rejected instead of overwriting the newer content.

## Git restrictions

The exposed Git surface intentionally avoids an arbitrary `git` command tool.

Supported mutation patterns are narrow:

- controller-created `work/*` worktrees
- `git diff --check`
- staging all current worktree changes for one guarded local commit
- normal non-force publication to the configured default branch

There is no MCP option for:

- arbitrary remote selection
- force-push
- reset
- rebase
- pushing an arbitrary refspec
- writing directly to the canonical checkout

## Publication guard

`repo_publish` requires all of the following:

1. publication was enabled locally for the repository
2. a GitHub repository was detected/configured
3. fetch and push `origin` still match that exact GitHub repository
4. worktree HEAD matches the accepted commit SHA
5. worktree and index are clean
6. fetched remote head matches the caller's inspected expected SHA
7. remote head is an ancestor of the accepted local commit
8. push uses a normal non-force ref update
9. post-push `ls-remote` resolves to the accepted commit

If any condition fails, publication stops.

## Script execution

There is no arbitrary shell MCP tool.

`run_npm_script` accepts only script names stored in the local repository allowlist. It then verifies that the script still exists in `package.json` before invoking `npm run <script>`.

The script itself is repository-controlled code, so users should authorize repositories they trust.

## Credentials

The repository registry stores repository paths, GitHub slugs, branches, permissions, and allowed script names. It does not store GitHub tokens.

GitHub authentication is handled by the user's existing Git credential mechanism.

## Local authorization matters

Do not make the local setup/manager functions remotely callable MCP tools. Adding/removing repository roots and enabling publication are intentionally human-local control-plane actions.
