# Architecture

## Runtime layers

Windows Coding Agent v0.1.5 separates the stable user-facing control plane from versioned agent code.

```text
ChatGPT
  |
  v
OpenAI Secure MCP Tunnel
  |
  v
tunnel-client.exe
  |
  v
%USERPROFILE%\.windows-coding-agent\bootstrap\mcp-loader.mjs
  |
  +--> active-version.json
  |
  v
%USERPROFILE%\.windows-coding-agent\versions\vX.Y.Z\src\index.js
  |
  v
authorized repositories
  |
  v
isolated worktrees
```

The tunnel profile targets the stable bootstrap, not a release ZIP extraction path. The bootstrap only accepts managed version paths contained beneath the configured Windows Coding Agent versions root.

## User-scoped control directory

```text
.windows-coding-agent\
  active-version.json
  chatgpt-connection.json
  config.json
  toolchain.json
  bootstrap\
    mcp-loader.mjs
    launch.ps1
  bin\
    Windows-Coding-Agent.cmd   # canonical human-facing control panel
    Setup.cmd
    Doctor.cmd
    Update.cmd
    Install-Dependencies.cmd
  versions\
    vX.Y.Z\
  tools\
    tunnel-client\
  secrets\
    tunnel-runtime-key.dpapi
  worktrees\
```

`config.json` remains the local authorization policy for repositories. `chatgpt-connection.json` stores non-secret tunnel/setup metadata. `toolchain.json` caches discovered executable paths and versions. The runtime tunnel key, when persisted, remains in a separate DPAPI-protected ciphertext file.

## Toolchain discovery

The local maintenance layer discovers and verifies:

- Node.js
- npm
- npx
- Git
- Windows PowerShell
- cmd.exe
- WinGet
- OpenAI tunnel-client
- optional pnpm
- optional yarn

Cached paths are advisory. If a path disappears, the next scan can search known Windows locations and PATH again.

## Managed version activation

A managed version is prepared in staging and is considered runnable only after locked dependencies are installed and the repository tests, source validation, and launcher self-test pass.

Activation changes only `active-version.json`. A prior healthy managed version is retained as last-known-good when possible. The stable bootstrap reads that state at process start.

## Update boundary

The updater is a local maintenance function, not an MCP tool.

```text
GitHub release
  -> exact versioned ZIP
  -> SHA-256 verification
  -> staging directory
  -> npm ci --ignore-scripts
  -> npm test
  -> npm run validate
  -> launcher self-test
  -> activate version
```

Failure before activation leaves the current active version unchanged.

## Repository package managers

During local repository authorization, Windows Coding Agent records a package manager using the declared `packageManager` field when possible, then lockfiles as fallback. Supported values are npm, pnpm, and yarn.

The MCP exposes `run_package_script` for locally allowlisted package scripts. The legacy `run_npm_script` name remains a compatibility alias and uses the detected package manager rather than forcing npm.

## Security boundary

The managed runtime does not broaden MCP authority. Remote clients still cannot add repository roots, enable publication, install dependencies, update the controller, choose arbitrary executables, or run an unrestricted shell. Those operations remain local human control-plane actions.
