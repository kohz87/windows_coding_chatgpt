# Codex integration

## Prerequisites

- Windows Coding Agent setup completed
- dependencies installed with `npm install`
- Codex CLI installed

## Register the MCP server

Run:

```text
codex mcp add windows-coding-agent -- node C:\path\to\windows_coding_chatgpt\src\index.js
```

Verify:

```text
codex mcp get windows-coding-agent
```

or:

```text
codex mcp list
```

## Recommended workflow

Ask Codex to use the Windows Coding Agent tools instead of raw writes against your canonical checkout.

A safe sequence is:

```text
repositories_list
repository_status
worktree_create
file_read / file_replace / file_create
run_npm_script
git_diff_check
repo_commit
```

Only request `repo_publish` after reviewing the accepted commit and only when publication is enabled locally.

## Removing the registration

```text
codex mcp remove windows-coding-agent
```
