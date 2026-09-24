# Windows Coding Agent

A security-bounded MCP coding controller for Windows that lets ChatGPT, Codex, and other compatible MCP clients work with **Git repositories you explicitly authorize on your PC**.

The important boundary is simple: **the human chooses repository directories locally. The AI cannot authorize new filesystem locations for itself.**

## What it provides

- Friendly ASCII setup and repository-management screens
- Guided `Connect-ChatGPT.cmd` wizard for ChatGPT + OpenAI Secure MCP Tunnel
- Automatic opening of the official tunnel, API-key, tunnel-client, and ChatGPT setup pages when needed
- Resume/reconfigure/fresh-setup flows with optional Windows DPAPI-secured runtime credential storage
- Persistent repository registry under your Windows user profile
- Read-only canonical repositories
- Isolated writable `work/*` Git worktrees
- SHA-256 guarded file replacement/deletion
- Path traversal, absolute-path, `.git`, Windows device-name, ADS, and worktree escape protection
- Per-repository package-manager detection (npm, pnpm, or yarn) with locally allowlisted scripts
- Bounded worktree Git operations for inspection, fetch/ff-only pull, restore, and no-commit cherry-pick/revert
- Bounded npm dependency/query operations with lifecycle scripts disabled for dependency mutation
- Optional locally enabled Codex CLI and Antigravity CLI (`agy`) runners, confined to isolated worktrees
- User-scoped toolchain registry for Node.js, npm, npx, Git, PowerShell, WinGet, tunnel-client, pnpm, and yarn
- Optional guided dependency installation and repair
- Versioned managed installation with stable MCP bootstrap, self-heal, verified updates, and rollback
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
- at least one local Git repository

`Setup.cmd` checks for Node.js 20+, npm, npx, and Git. If a required tool is missing it can offer to install or repair Node.js LTS and Git through WinGet. npm and npx are treated as part of the Node.js runtime family and are verified separately.

For ChatGPT access:

- OpenAI Secure MCP Tunnel client
- an OpenAI Platform tunnel and restricted runtime key
- a ChatGPT workspace/role that permits the custom MCP app/tunnel connection and required actions

For GitHub publication, Git must already be authenticated for the repository by your normal Git credential setup.

Windows Coding Agent does **not** store GitHub tokens or literal OpenAI runtime API keys in its repository registry or ChatGPT wizard state. When you choose secure persistence, the tunnel runtime key is stored only as Windows DPAPI-encrypted ciphertext bound to the current Windows user.

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

The setup first checks required dependencies, creates a versioned managed Windows Coding Agent installation under your user profile, then verifies the Git root, detects the GitHub `origin` when present, detects the repository package manager and common scripts, and asks whether guarded publication should be enabled.

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
  Active agent                            [OK] v0.1.5
  Stable MCP bootstrap                    [OK]
  Tunnel client                           [--] not configured
  OpenAI tunnel                           [--] not configured
  ChatGPT app                             [--] not confirmed

  --------------------------------------------------------

     [1] Start guided setup
     [2] Setup / resume / reconfigure
     [3] Diagnostics
     [4] Manage repositories
     [5] Start fresh setup
     [6] Maintenance / dependencies / updates
     [Q] Quit
```

For first-time setup, choose `[1]`.

The six-step wizard:

1. checks Node.js 20+, npm, npx, Git, and local repository authorization, with an install/repair option for missing required tools
2. finds `tunnel-client.exe`, can install the verified official OpenAI release into the user-scoped tool directory, or opens the official download page
3. opens the OpenAI Tunnels page and asks for the `tunnel_...` ID
4. opens Runtime API Keys and asks for a restricted **Tunnels Read + Use** key using a hidden prompt
5. creates the local stdio tunnel profile against a stable user-scoped MCP bootstrap and runs `tunnel-client doctor --explain`
6. opens ChatGPT connection settings and shows the exact custom MCP app values to select

The authenticated browser pages remain explicit user actions. The script does not attempt to click through your OpenAI account or silently grant permissions.

### 3. Start the bridge

After setup, future launches become:

```text
Connect-ChatGPT.cmd
   -> [1] Start ChatGPT bridge
```

If you chose secure persistence, the wizard loads the DPAPI-protected runtime credential automatically. Otherwise it asks again unless `CONTROL_PLANE_API_KEY` already exists. It then verifies the tunnel, optionally opens ChatGPT, and starts the foreground Secure MCP Tunnel.

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
   -> stable ~/.windows-coding-agent/bootstrap/mcp-loader.mjs
   -> active managed Windows Coding Agent version
   -> authorized repository
   -> isolated worktree
   -> tests / guarded commit
   -> optional guarded GitHub publication
```

The tunnel profile no longer depends on the directory where a release ZIP was extracted. Moving or deleting an old v0.1.x folder therefore does not leave the tunnel pointing at a dead `src/index.js` path.

See [docs/CHATGPT.md](docs/CHATGPT.md) for the detailed walkthrough, resume/reconfigure behavior, safe reset modes, and troubleshooting.

## Managed installation, self-heal, and updates

v0.1.5 introduces a stable user-scoped runtime:

```text
%USERPROFILE%\.windows-coding-agent\
  active-version.json
  toolchain.json
  bootstrap\
    mcp-loader.mjs
    launch.ps1
  bin\
    Connect-ChatGPT.cmd
    Start-Agent.cmd
    Setup.cmd
    Doctor.cmd
    Update.cmd
    Install-Dependencies.cmd
  versions\
    v0.1.5\
  tools\
    tunnel-client\
  secrets\
  worktrees\
```

The release ZIP becomes an installer/source bundle rather than the permanent MCP target. Stable launchers dispatch to the active managed version. On startup the ChatGPT wizard can rediscover stale tool paths and repair a tunnel profile that still references an older extracted release.

Maintenance is local and human-controlled. From menu option `[6]` you can scan/install dependencies, run self-heal, check/install an update, roll back to the last-known-good managed version, or show the stable launcher directory.

Updates are downloaded from this repository's GitHub release assets, SHA-256 verified, staged, installed with `npm ci --ignore-scripts`, tested and validated before activation. A failed candidate does not replace the active version. There is deliberately no remote MCP tool that lets ChatGPT replace its own security controller.

## Resume, reconfigure, or start fresh

`Connect-ChatGPT.cmd` remembers only non-secret setup state such as the tunnel ID, tunnel-client path, and completion markers.

Default location:

```text
%USERPROFILE%\.windows-coding-agent\chatgpt-connection.json
```

The runtime API key is never written there. If secure persistence is enabled, encrypted ciphertext is stored separately at `%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi` (or under `WINDOWS_CODING_AGENT_HOME`).

From the control panel you can:

- resume the guided setup
- change only the tunnel ID or tunnel-client path
- manage, test, replace, or forget the securely saved runtime credential
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
      "packageManager": "npm",
      "permissions": {
        "worktrees": true,
        "runScripts": true,
        "commit": true,
        "publish": false
      },
      "allowedPackageScripts": ["test", "build"]
    }
  }
}
```

Users normally do not edit this manually. `Setup.cmd` and `Start-Agent.cmd` maintain it.

Package scripts are exact-allowlisted by default. For a repository you trust to define its own executable scripts, the local repository manager can opt into:

```json
"allowedPackageScripts": ["*"]
```

The wildcard is local policy, not an MCP bypass: `run_package_script` still requires `runScripts`, an isolated controller worktree, and an exact script name that exists in that repository's current `package.json`. Use **Start-Agent.cmd → S** to toggle this policy for an already authorized repository.

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
5. `run_npm_script` for allowlisted checks, or `npm_operation` for bounded npm dependency/query work
6. `git_operation` for bounded Git inspection/worktree operations as needed
7. `git_diff_check`
8. `repo_commit`
9. optionally `repo_publish`

Publication is disabled unless the user enabled it locally for that repository.

### Optional coding-agent CLIs

`Start-Agent.cmd` exposes a local **Toggle coding-agent CLI** action for `codex` and `agy`. Both are disabled by default. Enabling one discovers the executable from the local PATH, verifies `--version`, and stores the exact absolute executable path in the local controller config.

After local enablement, MCP clients can use `agent_cli_status` and `agent_run`. Runs are accepted only for controller-created isolated worktrees. Codex runs use `codex exec --sandbox workspace-write`; Antigravity runs use headless `agy -p` with its sandbox enabled. The MCP cannot enable a runner, replace its executable path, request Codex `danger-full-access`, or pass Antigravity `--dangerously-skip-permissions`.

Both CLIs may use their own native agent/subagent capabilities according to their locally authenticated configuration and permission policies.

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
