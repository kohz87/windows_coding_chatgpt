# Windows Coding Agent

A security-bounded MCP coding controller for Windows that lets ChatGPT, Codex, and other compatible MCP clients work with **Git repositories you explicitly authorize on your PC**.

The important boundary is simple: **the human chooses repository directories locally. The AI cannot authorize new filesystem locations for itself.**

## What v0.1 provides

- Local setup wizard for manually selecting Git repository directories
- ChatGPT connection through OpenAI Secure MCP Tunnel
- Guided `Connect-ChatGPT.cmd` setup for the tunnel/runtime key/custom MCP app flow
- Persistent repository registry under your Windows user profile
- Read-only canonical repositories
- Isolated writable `work/*` Git worktrees
- SHA-256 guarded file replacement/deletion
- Path traversal, absolute-path, `.git`, Windows device-name, ADS, and worktree escape protection
- Per-repository npm script allowlists
- Guarded local commits
- Optional fast-forward-only publication to the configured GitHub repository
- MCP stdio server for Codex and local MCP clients
- Health/diagnostic command
- Windows-first launchers and Windows GitHub Actions CI

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
- a ChatGPT workspace/role that permits Developer mode/custom MCP apps and the required actions

For GitHub publication, Git must already be authenticated for the repository by your normal Git credential setup.

Windows Coding Agent does **not** store GitHub tokens or OpenAI runtime API keys in its repository registry.

## Quick start: ChatGPT -> local Git

### 1. Authorize the local repository

Double-click:

```text
Setup.cmd
```

Enter/select a Git repository such as:

```text
C:\Users\Alice\Projects\my-app
```

The setup verifies the Git root, detects the GitHub `origin` when present, detects common npm scripts, and asks whether guarded publication should be enabled.

### 2. Create an OpenAI Secure MCP Tunnel

Create a tunnel for the ChatGPT workspace that will use the controller:

```text
https://platform.openai.com/settings/organization/tunnels
```

Then create a restricted Runtime API key with **Tunnels Read + Use**:

```text
https://platform.openai.com/settings/organization/api-keys
```

Install the official OpenAI tunnel client from:

```text
https://github.com/openai/tunnel-client/releases/latest
```

### 3. Connect this PC

Double-click:

```text
Connect-ChatGPT.cmd
```

It asks for the tunnel ID and runtime API key, creates the OpenAI `sample_mcp_stdio_local` profile for Windows Coding Agent, runs `tunnel-client doctor`, shows the ChatGPT app steps, and then runs the tunnel.

The runtime API key is entered with a hidden prompt and is kept in the current process environment rather than written to the Windows Coding Agent configuration.

Keep that terminal open while ChatGPT is using the local MCP.

### 4. Create the ChatGPT custom MCP app

In ChatGPT Settings:

1. Open **Plugins** or **Apps**, then **Advanced settings**.
2. Enable **Developer mode** if your workspace permits it.
3. Create a custom MCP app named `Windows Coding Agent`.
4. Choose **Connection: Tunnel**.
5. Select/paste the same `tunnel_...` ID used by `Connect-ChatGPT.cmd`.
6. Use **Authentication: None** when that field is shown for the Secure MCP Tunnel connection.
7. Let ChatGPT scan/import the MCP tools and save the app.
8. In workspace app controls, enable the required Read and Write actions. The recommended default for writes is **Always ask**.

A public Plugin Directory submission is **not required** for personal/internal use. The custom MCP app is the ChatGPT-to-tunnel binding.

See [docs/CHATGPT.md](docs/CHATGPT.md) for the detailed walkthrough and troubleshooting.

### 5. Test from ChatGPT

Start with a read-only prompt:

```text
Use Windows Coding Agent. List my authorized repositories and show their status. Do not modify anything.
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

No inbound public port is required.

## Local repository management

Run:

```text
Start-Agent.cmd
```

The startup manager lets you add/remove authorized repositories and toggle publication without hand-editing JSON.

Run diagnostics with:

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

CI runs tests, validation, the MCP SDK smoke test, the ChatGPT launcher smoke test, and a release ZIP extraction/contents check on `windows-latest`.

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
