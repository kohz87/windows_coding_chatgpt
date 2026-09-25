# Configuration

## Location

Default:

```text
%USERPROFILE%\.windows-coding-agent\config.json
```

Override the controller data root with environment variable:

```text
WINDOWS_CODING_AGENT_HOME=D:\AgentData
```

Then configuration lives at:

```text
D:\AgentData\config.json
```

## Registry format

Schema version 1:

```json
{
  "schemaVersion": 1,
  "repositories": {
    "project-id": {
      "name": "Project Name",
      "path": "C:\\Projects\\project",
      "github": "owner/project",
      "defaultBranch": "main",
      "permissions": {
        "worktrees": true,
        "runScripts": true,
        "commit": true,
        "publish": false
      },
      "allowedNpmScripts": ["test", "build"]
    }
  }
}
```

## Repository IDs

Repository IDs are local aliases used by MCP tools. They contain letters, numbers, underscores, or hyphens.

The setup wizard derives the first suggestion from the selected folder name.

## GitHub field

When `origin` is one of these forms:

```text
https://github.com/owner/repo.git
git@github.com:owner/repo.git
ssh://git@github.com/owner/repo.git
```

Setup records:

```text
owner/repo
```

If no supported GitHub origin is detected, local worktree operations still work, but controller publication is unavailable.

## npm script allowlist

Setup initially detects common scripts. The allowlist is intentionally names only, not arbitrary command strings supplied by the MCP client.

Advanced users may edit the configuration manually, but `Windows-Coding-Agent.cmd` is the recommended interface for ordinary repository authorization and publication toggles.


## Coding-agent CLI toggles

The global `agentCli` settings are local controller authorization, separate from repository permissions.

Both `codex` and `agy` default to disabled. Use `Windows-Coding-Agent.cmd` -> **Toggle coding-agent CLI** rather than editing paths manually. When enabled, the manager discovers the executable on PATH, probes its version, and persists its exact absolute path. MCP callers can inspect status and run enabled agents, but cannot change these toggle settings.
