# Windows Coding Agent

A security-bounded MCP coding controller for Windows that lets ChatGPT, Codex, and other compatible MCP clients work with **repositories you explicitly authorize locally**.

The important boundary is simple: **the user chooses repository directories on the Windows machine. The AI cannot authorize new filesystem locations for itself.**

## What v0.1 provides

- Local setup wizard for manually selecting Git repository directories
- Persistent repository registry under your Windows user profile
- Read-only access to canonical repositories
- Isolated writable `work/*` Git worktrees
- SHA-256 guarded file replacement/deletion
- Path traversal, absolute-path, `.git`, Windows device-name, ADS, and worktree escape protection
- Per-repository npm script allowlists
- Guarded local commits
- Optional fast-forward-only publication to the configured GitHub repository
- MCP stdio server for Codex and other local MCP clients
- Health/diagnostic command
- Windows-first `Setup.cmd`, `Start-Agent.cmd`, `Doctor.cmd`, and `Update.cmd`
- Windows GitHub Actions CI

NPC State and SillyTavern-specific host tooling is intentionally not part of the generic core. It can be added later as an optional adapter rather than making every user inherit project-specific machinery.

## Requirements

Required:

- Windows 10 or Windows 11
- Node.js 20 or newer
- Git for Windows
- At least one local Git repository

For GitHub publication, Git must already be authenticated for the repository by your normal Git credential setup.

Optional:

- OpenAI Codex CLI or another local MCP client
- A supported secure MCP bridge/tunnel if you want a remote ChatGPT session to reach this local stdio controller

Windows Coding Agent does **not** store GitHub tokens in its repository registry.

## Quick start

Clone or download this repository, then double-click:

```text
Setup.cmd
```

The wizard asks for a repository directory such as:

```text
C:\Users\Alice\Projects\my-app
```

It verifies the Git root, detects the GitHub `origin` when present, detects the default branch, detects common npm scripts, and asks whether guarded publication should be enabled.

After setup, use:

```text
Start-Agent.cmd
```

The startup manager lets you add/remove repositories and toggle publication without hand-editing JSON.

Run diagnostics with:

```text
Doctor.cmd
```

## MCP server

Local MCP clients should launch:

```text
node C:\path\to\windows_coding_chatgpt\src\index.js
```

or:

```text
npm run server
```

Do not point the MCP client at `Start-Agent.cmd`. The startup manager is a human-facing local authorization screen; `src/index.js` is the machine-facing MCP endpoint.

## Example Codex registration

From the repository directory:

```text
codex mcp add windows-coding-agent -- node C:\path\to\windows_coding_chatgpt\src\index.js
```

Then verify:

```text
codex mcp get windows-coding-agent
```

See [docs/CODEX.md](docs/CODEX.md).

## How repository authorization works

A repository registration contains only a small amount of local policy, for example:

```json
{
  "schemaVersion": 1,
  "repositories": {
    "my-app": {
      "name": "my-app",
      "path": "C:\\Users\\Alice\\Projects\\my-app",
      "github": "alice/my-app",
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

Users normally do not edit this by hand. `Setup.cmd` and `Start-Agent.cmd` maintain it.

Default location:

```text
%USERPROFILE%\.windows-coding-agent\config.json
```

Override the data root with:

```text
WINDOWS_CODING_AGENT_HOME
```

## Security model

Canonical repository checkouts are treated as read-only by mutation tools. Source changes are made only inside controller-created isolated worktrees.

The MCP client cannot choose arbitrary Windows paths, arbitrary Git remotes, or force-push targets. Publication is tied to the GitHub `origin` the human authorized locally and uses a normal non-force push after exact HEAD and remote-head checks.

See [docs/SECURITY.md](docs/SECURITY.md) for the full model.

## Common workflow

A typical AI-assisted task becomes:

1. `repositories_list`
2. `repository_status`
3. `worktree_create`
4. inspect/edit files in the isolated worktree
5. `run_npm_script` for allowlisted checks
6. `git_diff_check`
7. `repo_commit`
8. optionally `repo_publish`

Publication is disabled unless the user enabled it locally for that repository.

## Development

```text
npm install
npm test
npm run validate
```

CI runs the same test and validation commands on `windows-latest`.

## Documentation

- [Installation](docs/INSTALLATION.md)
- [Security](docs/SECURITY.md)
- [Configuration](docs/CONFIGURATION.md)
- [Codex](docs/CODEX.md)
- [ChatGPT](docs/CHATGPT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](docs/ROADMAP.md)

## License

GPL-3.0-only. See [LICENSE](LICENSE).
