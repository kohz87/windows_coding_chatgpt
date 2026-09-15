# Windows Coding Agent

A security-bounded MCP coding controller for Windows that lets ChatGPT, Codex, and other compatible MCP clients work with **Git repositories you explicitly authorize on your PC**.

The important boundary is simple: **the human chooses repository directories locally. The AI cannot authorize new filesystem locations for itself.**

## What it provides

- Friendly ASCII setup and repository-management screens
- Guided `Connect-ChatGPT.cmd` wizard for ChatGPT + OpenAI Secure MCP Tunnel
- Automatic opening of the official tunnel, API-key, tunnel-client, and ChatGPT setup pages when needed
- Resume/reconfigure/fresh-setup flows without storing the runtime API key
- Persistent repository registry under your Windows user profile
- Read-only canonical repositories
- Isolated writable `work/*` Git worktrees
- SHA-256 guarded file replacement/deletion
- Path traversal, absolute-path, `.git`, Windows device-name, ADS, and worktree escape protection
- Per-repository npm script allowlists
- Guarded local commits
- Optional fast-forward-only publication to the configured GitHub repository
- MCP stdio server for Codex and local MCP clients
- Windows-first launchers, diagnostics, packaging, and GitHub Actions CI

NPC State and SillyTavern-specific tooling is intentionally not part of the generic core.

## Download

Use the packaged GitHub release:

- [Latest releases](https://github.com/kohz87/windows_coding_chatgpt/releases)
- Each release includes a versioned ZIP and `.sha256` checksum.

Extract the ZIP and double-click `Setup.cmd`.

## Requirements

Required:

- Windows 10 or Windows 11
- Node.js 20 or newer
- Git for Windows
- at least one local Git repository

For ChatGPT access:

- OpenAI Secure MCP Tunnel client
- an OpenAI Platform tunnel and restricted runtime key
- a ChatGPT workspace/role that permits the custom MCP app/tunnel connection and required actions

For GitHub publication, Git must already be authenticated for the repository by your normal Git credential setup.

Windows Coding Agent does **not** store GitHub tokens or OpenAI runtime API keys in its repository registry or ChatGPT wizard state.

## Quick start: ChatGPT -> local Git

### 1. Authorize a repository

Double-click:

```text
Setup.cmd
```

Enter a Git repository such as:

```text
C:\Users\Alice\Projects\my-app
```

The setup verifies the Git root, detects the GitHub `origin` when present, detects common npm scripts, and asks whether guarded publication should be enabled.

### 2. Run the ChatGPT wizard

Double-click:

```text
Connect-ChatGPT.cmd
```

The launcher becomes the setup control panel:

```text
+----------------------------------------------------------+
|              WINDOWS CODING AGENT                      |
|          ChatGPT <-> Local Git Bridge                  |
+----------------------------------------------------------+

  Connection status

  Local repositories                     [OK] 1 authorized
  Tunnel client                           [--] not configured
  OpenAI tunnel                           [--] not configured
  ChatGPT app                             [--] not confirmed

  --------------------------------------------------------

     [1] Start guided setup
     [2] Setup / resume / reconfigure
     [3] Diagnostics
     [4] Manage repositories
     [5] Start fresh setup
     [Q] Quit
```

For first-time setup, choose `[1]`.

The six-step wizard:

1. checks Node.js, Git, and local repository authorization
2. finds `tunnel-client.exe` or opens the official download page
3. opens the OpenAI Tunnels page and asks for the `tunnel_...` ID
4. opens Runtime API Keys and asks for a restricted **Tunnels Read + Use** key using a hidden prompt
5. creates the local stdio tunnel profile and runs `tunnel-client doctor --explain`
6. opens ChatGPT connection settings and shows the exact custom MCP app values to select

The authenticated browser pages remain explicit user actions. The script does not attempt to click through your OpenAI account or silently grant permissions.

### 3. Start the bridge

After setup, future launches become:

```text
Connect-ChatGPT.cmd
   -> [1] Start ChatGPT bridge
```

The wizard asks for the runtime key again unless `CONTROL_PLANE_API_KEY` already exists, verifies the tunnel, optionally opens ChatGPT, and starts the foreground Secure MCP Tunnel.

Keep the terminal open while ChatGPT is using the local MCP. Stop it with `Ctrl+C`.

No inbound public port is required.

### 4. Test from ChatGPT

Start read-only:

```text
Use Windows Coding Agent.
List my authorized repositories and show their current status.
Do not modify anything.
```

Then test a guarded edit:

```text
Use Windows Coding Agent on my-app.
Create an isolated worktree, make the requested change, run the allowlisted tests,
show me the diff, and commit only if checks pass.
Do not publish unless I explicitly ask.
```

The resulting path is:

```text
ChatGPT
   -> custom MCP app
   -> OpenAI Secure MCP Tunnel
   -> tunnel-client.exe on your PC
   -> Windows Coding Agent MCP over local stdio
   -> authorized repository
   -> isolated worktree
   -> tests / guarded commit
   -> optional guarded GitHub publication
```

See [docs/CHATGPT.md](docs/CHATGPT.md) for the detailed walkthrough, resume/reconfigure behavior, safe reset modes, and troubleshooting.

## Resume, reconfigure, or start fresh

`Connect-ChatGPT.cmd` remembers only non-secret setup state such as the tunnel ID, tunnel-client path, and completion markers.

Default location:

```text
%USERPROFILE%\.windows-coding-agent\chatgpt-connection.json
```

The runtime API key is never written there.

From the control panel you can:

- resume the guided setup
- change only the tunnel ID or tunnel-client path
- validate a new runtime key
- reopen the ChatGPT connection step
- manage authorized repositories
- reset only the ChatGPT connection while keeping repositories/worktrees
- perform a full reset only after explicit `RESET` confirmation; the repository registry is backed up first

## Local repository management

Run:

```text
Start-Agent.cmd
```

It provides an ASCII repository manager for adding/removing authorized repositories and toggling guarded publication without hand-editing JSON.

Run standalone diagnostics with:

```text
Doctor.cmd
```

## MCP server

Local MCP clients can launch:

```text
node C:\path\to\windows_coding_chatgpt\src\index.js
```

or:

```text
npm run server
```

Do not point an MCP client at `Start-Agent.cmd`. The startup manager is the human-facing local authorization screen; `src/index.js` is the machine-facing MCP endpoint.

## Example Codex registration

From the repository directory:

```text
codex mcp add windows-coding-agent -- node C:\path\to\windows_coding_chatgpt\src\index.js
codex mcp get windows-coding-agent
```

See [docs/CODEX.md](docs/CODEX.md).

## Repository authorization

A registration contains local policy such as:

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

Users normally do not edit this manually. `Setup.cmd` and `Start-Agent.cmd` maintain it.

Default location:

```text
%USERPROFILE%\.windows-coding-agent\config.json
```

Override the data root with `WINDOWS_CODING_AGENT_HOME`.

## Security model

Canonical repository checkouts are treated as read-only by mutation tools. Source changes are made only inside controller-created isolated worktrees.

The MCP client cannot choose arbitrary Windows paths, arbitrary Git remotes, or force-push targets. ChatGPT workspace write permission does not override these local guards. Publication is tied to the locally authorized GitHub `origin` and uses a normal non-force push after exact HEAD and remote-head checks.

The ChatGPT path adds another separation of duties:

```text
ChatGPT action permission
        +
restricted tunnel runtime credential
        +
human local repository authorization
        +
Windows Coding Agent worktree/git guards
```

See [docs/SECURITY.md](docs/SECURITY.md).

## Common MCP workflow

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
npm run package
```

CI runs tests, validation, the MCP SDK smoke test, Windows PowerShell parser + wizard self-tests, and a release ZIP extraction/contents/self-test check on `windows-latest`.

## Documentation

- [Installation](docs/INSTALLATION.md)
- [Security](docs/SECURITY.md)
- [Configuration](docs/CONFIGURATION.md)
- [Codex](docs/CODEX.md)
- [ChatGPT / Secure MCP Tunnel](docs/CHATGPT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](docs/ROADMAP.md)

## License

GPL-3.0-only. See [LICENSE](LICENSE).
