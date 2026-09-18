# Security model

Windows Coding Agent is designed around explicit local authorization and narrow capabilities rather than unrestricted shell/filesystem access.

## Trust boundary

The human operator controls which local Git repository directories are authorized.

An MCP client can refer to a repository by its configured ID, but cannot provide a new absolute repository path to coding tools.

For ChatGPT, OpenAI Secure MCP Tunnel adds a remote transport layer, but it does **not** widen this local authorization boundary. A remotely connected ChatGPT custom app can call only the MCP tools exposed by Windows Coding Agent against repositories already registered locally.

## ChatGPT / Secure MCP Tunnel boundary

The supported remote path is:

```text
ChatGPT custom MCP app
  -> OpenAI Secure MCP Tunnel
  -> tunnel-client on the user's PC
  -> local Windows Coding Agent stdio child
```

Windows Coding Agent does not expose its own unauthenticated public TCP/HTTP listener for ChatGPT.

The tunnel runtime uses a restricted `CONTROL_PLANE_API_KEY` with Tunnels Read + Use. `Connect-ChatGPT.cmd` prompts for that key without echo. The user can keep it session-only or persist it as Windows DPAPI-encrypted ciphertext bound to the current Windows user. The repository registry and wizard-state JSON never contain the literal key.

Do not use an organization admin key as the long-lived runtime credential. Do not write literal runtime keys into the Windows Coding Agent repository, config example, tunnel profile, or wizard-state file.

ChatGPT workspace app permissions form an outer permission layer. Enabling a Write action in ChatGPT permits ChatGPT to request that MCP operation; it does not disable Windows Coding Agent's local repository, worktree, Git, script, or publication guards.

For write-capable apps, keep ChatGPT approval settings at the workspace's cautious/default level unless you have deliberately reviewed a different policy.

## ChatGPT wizard state

The guided launcher may persist non-secret connection metadata at:

```text
%USERPROFILE%\.windows-coding-agent\chatgpt-connection.json
```

or beneath `WINDOWS_CODING_AGENT_HOME` when that override is used.

Allowed persisted fields are limited to connection metadata such as:

- tunnel ID
- tunnel-client executable path
- local profile name
- setup/diagnostic completion markers
- timestamps

The wizard state must not contain API keys, bearer tokens, GitHub credentials, or other secrets. CI includes a self-test that rejects secret-like state fields and performs a DPAPI encrypt/decrypt round-trip using a temporary test credential.

Resetting only the ChatGPT connection removes this wizard state and the DPAPI-protected tunnel credential, but leaves the repository registry and worktrees intact. The full-reset path requires an explicit `RESET` confirmation and backs up `config.json` before clearing active repository authorization.

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
- staging current worktree changes for one guarded local commit
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

A remote ChatGPT session cannot enable publication for itself. That setting remains a local human action in `Setup.cmd`/`Start-Agent.cmd`.

## Script execution

There is no arbitrary shell MCP tool.

`run_npm_script` accepts only script names stored in the local repository allowlist. It then verifies that the script still exists in `package.json` before invoking `npm run <script>`.

The script itself is repository-controlled code, so users should authorize repositories they trust.

## Credentials

The repository registry stores repository paths, GitHub slugs, branches, permissions, and allowed script names. It does not store GitHub tokens or OpenAI Secure MCP Tunnel runtime API keys. Optional tunnel credential persistence uses a separate DPAPI ciphertext file under the user-scoped Windows Coding Agent data directory.

GitHub authentication is handled by the user's existing Git credential mechanism.

The tunnel profile generated by OpenAI's tunnel client references `env:CONTROL_PLANE_API_KEY`; the secret value itself should remain outside the profile.

## Local authorization matters

Do not make the local setup/manager functions remotely callable MCP tools. Adding/removing repository roots and enabling publication are intentionally human-local control-plane actions.

Do not replace the Secure MCP Tunnel path with a raw public listener merely for convenience. The goal is remote ChatGPT reachability without turning the development PC into a general network-accessible coding daemon.

### DPAPI credential storage

When the user chooses **Save securely for this Windows user**, the launcher encrypts the restricted tunnel runtime key with Windows Data Protection API (DPAPI), `CurrentUser` scope, plus application-specific entropy. The encrypted blob is written to:

```text
%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi
```

or the equivalent path beneath `WINDOWS_CODING_AGENT_HOME`.

DPAPI protects the credential at rest against simple file disclosure, but it is not a boundary against malware, an administrator, or another process already able to operate as the same Windows user. The launcher decrypts the key only when needed, exports it to `CONTROL_PLANE_API_KEY` for the current process tree, and never writes the plaintext value to JSON configuration or tunnel profiles.

## Managed runtime and updater boundary

v0.1.5 separates the stable local control plane from any extracted release directory. The Secure MCP Tunnel targets the user-scoped `bootstrap\mcp-loader.mjs`, which will only load an active installation path contained under `%USERPROFILE%\.windows-coding-agent\versions\` (or the configured `WINDOWS_CODING_AGENT_HOME`). If the active version is unavailable, the bootstrap may fall back only to a recorded last-known-good path inside that same managed versions root.

`toolchain.json` contains discovered executable paths, versions, status information, and timestamps. It is not a credential store. Runtime API keys remain separately DPAPI-protected when secure persistence is enabled.

Dependency installation is an explicit local operation. Node.js LTS and Git may be installed through WinGet after user confirmation. Automatic tunnel-client installation is restricted to the official OpenAI GitHub release and requires SHA-256 verification before extraction. The code may remove the ordinary Internet-zone marker only from that verified official download; it does not disable or bypass Windows Application Control, WDAC, AppLocker, or Smart App Control.

Agent updates are also local human-approved maintenance operations. The updater downloads a versioned GitHub release asset, verifies SHA-256, stages the candidate, installs locked dependencies with `npm ci --ignore-scripts`, runs tests and validation, and only then changes the active-version pointer. Failed candidates do not replace the current active version. The MCP surface deliberately does not expose an unrestricted self-update or dependency-install command to a remote ChatGPT session.

## Package managers

Repository setup records a detected package manager (`npm`, `pnpm`, or `yarn`) and an allowlist of package scripts. The MCP can invoke only those allowlisted scripts. Package-manager detection does not create an arbitrary shell capability, and optional package managers are installed only through local maintenance flows.
