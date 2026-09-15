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

Advanced users may edit the configuration manually, but `Start-Agent.cmd` is the recommended interface for ordinary repository authorization and publication toggles.
