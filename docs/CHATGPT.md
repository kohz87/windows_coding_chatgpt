# ChatGPT integration

Windows Coding Agent can be used from ChatGPT to inspect and modify **local Git repositories that you authorized on the Windows PC**.

The normal user path is now deliberately simple:

```text
Setup.cmd
   |
   v
Connect-ChatGPT.cmd
   |
   v
Guided ASCII wizard
   |
   +--> OpenAI tunnel page
   +--> Runtime API key page
   +--> tunnel-client doctor
   +--> ChatGPT connection settings
   |
   v
ChatGPT <-> Secure MCP Tunnel <-> Windows Coding Agent <-> authorized Git
```

ChatGPT never receives permission to browse arbitrary directories. Repository authorization still happens locally with `Setup.cmd` or `Start-Agent.cmd`.

## Requirements

You need:

- Windows 10/11
- Node.js 20 or newer
- Git for Windows
- Windows Coding Agent installed and at least one local Git repository authorized
- OpenAI Secure MCP Tunnel client
- an OpenAI Platform tunnel scoped to the ChatGPT workspace that will use it
- a restricted Runtime API key with **Tunnels Read + Use**
- ChatGPT workspace access to a custom MCP app/tunnel connection and the required actions

Product availability and workspace labels can vary. The wizard opens the current OpenAI setup pages but deliberately does not automate authenticated browser clicks or permission grants.

## Managed runtime and stable bridge

Starting with v0.1.5, the tunnel profile no longer points directly at the folder where a release ZIP was extracted. Setup creates a versioned managed installation under `%USERPROFILE%\.windows-coding-agent\versions\` and a stable MCP bootstrap at `%USERPROFILE%\.windows-coding-agent\bootstrap\mcp-loader.mjs`.

The tunnel always launches that stable bootstrap. The bootstrap reads `active-version.json` and loads the active agent version. This means replacing or deleting an old extracted release directory does not strand the tunnel on a dead `src/index.js` path.

The same user-scoped home stores a non-secret `toolchain.json` cache for Node.js, npm, npx, Git, PowerShell, WinGet, tunnel-client, pnpm, and yarn. If a cached path becomes invalid, the local wizard can rediscover it and repair the cache.

The main wizard's **Maintenance** menu can scan/install dependencies, self-heal the managed runtime and tunnel profile, install a verified update, or roll back to the last-known-good managed version. These remain local human actions and are not exposed as remote MCP self-modification tools.

## Quick setup

Run:

```text
Connect-ChatGPT.cmd
```

You will see a control panel similar to:

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

The wizard walks through six steps.

### Step 1 - Local readiness

The wizard checks:

- Node.js
- Git
- the local repository registry
- whether at least one Git repository is authorized

If no repository is authorized, it can launch `Setup.cmd` directly.

### Step 2 - Tunnel client

The wizard searches, in order, for:

1. the `-TunnelClient` command-line parameter
2. `TUNNEL_CLIENT_BIN`
3. the previously saved tunnel-client path
4. `tunnel-client.exe` on `PATH`

If it cannot find the binary, it offers to open the official release page or lets you enter the local executable path.

Official client:

```text
https://github.com/openai/tunnel-client/releases/latest
```

### Step 3 - OpenAI tunnel

The wizard can open:

```text
https://platform.openai.com/settings/organization/tunnels
```

Create or select a tunnel for the same ChatGPT workspace that will use Windows Coding Agent, then paste the resulting `tunnel_...` ID.

The local runtime and the ChatGPT app must use the same tunnel ID.

### Step 4 - Runtime API key

The wizard can open:

```text
https://platform.openai.com/settings/organization/api-keys
```

Create a **Restricted** runtime key with:

```text
Tunnels
  [x] Read
  [x] Use
  [ ] Manage
```

The key is entered with a hidden prompt. You can either save it securely for the current Windows user or keep it session-only. Secure persistence uses Windows DPAPI and stores only encrypted ciphertext; session-only mode places it only in the current process environment as `CONTROL_PLANE_API_KEY`.

The literal key is **never saved** in `chatgpt-connection.json`, `config.json`, the tunnel profile, or the Windows Coding Agent source tree. DPAPI ciphertext is stored separately at `%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi` when secure persistence is selected.

You may instead set `CONTROL_PLANE_API_KEY` yourself before launching the wizard.

### Step 5 - Configure and test the bridge

The wizard creates/refreshes the local tunnel profile using the official local-stdio sample and the detected Node.js path. Conceptually:

```text
tunnel-client init --force ^
  --sample sample_mcp_stdio_local ^
  --profile windows-coding-agent ^
  --tunnel-id <YOUR_TUNNEL_ID> ^
  --mcp-command "node C:\path\to\Windows-Coding-Agent\src\index.js"
```

It immediately runs:

```text
tunnel-client doctor --profile windows-coding-agent --explain
```

The wizard does not mark the bridge configured unless `doctor` succeeds.

### Step 6 - Connect ChatGPT

The wizard can open:

```text
https://chatgpt.com/#settings/Connectors
```

Create/connect the custom MCP app using:

```text
Connection      Tunnel
Tunnel ID       the same tunnel_... used by this PC
Authentication  None
```

`Authentication: None` means there is no second public MCP bearer token. The local Secure MCP Tunnel runtime is already authenticated to OpenAI with the restricted runtime key.

Allow the Read and Write actions you want ChatGPT to use. The recommended write approval policy is **Always ask** unless you deliberately choose a different policy.

You do **not** need to publish a public Plugin Directory listing to use Windows Coding Agent on your own machine. The custom MCP app/tunnel connection is sufficient.

## What the wizard remembers

Non-secret connection progress is saved under the Windows Coding Agent data directory:

```text
%USERPROFILE%\.windows-coding-agent\chatgpt-connection.json
```

or beneath `WINDOWS_CODING_AGENT_HOME` when that override is set.

Saved values include only things such as:

- tunnel ID
- local tunnel-client executable path
- profile name
- whether tunnel `doctor` last succeeded
- whether you confirmed the ChatGPT app step

The runtime API key is intentionally absent. When secure persistence is enabled, the encrypted DPAPI blob lives under secrets\tunnel-runtime-key.dpapi instead. It can be decrypted only in the Windows user context that created it (subject to normal local-machine/user security boundaries).

This lets the wizard resume without turning the setup file into a plaintext credential vault.

## Normal daily startup

After first-time setup, run:

```text
Connect-ChatGPT.cmd
```

and choose:

```text
[1] Start ChatGPT bridge
```

The launcher first uses `CONTROL_PLANE_API_KEY` when already present, otherwise loads the DPAPI-protected saved credential when available, and only prompts when neither exists. It reruns the tunnel diagnostic, optionally opens ChatGPT, then starts:

```text
tunnel-client run --profile windows-coding-agent
```

Keep that terminal window open while ChatGPT uses the local MCP. Stop it with `Ctrl+C`.

No inbound public port is opened. `tunnel-client` maintains the outbound connection to OpenAI and starts Windows Coding Agent locally over stdio.

## Resume and reconfigure

The main menu includes:

```text
[2] Setup / resume / reconfigure
```

You can rerun the guided setup or change only one item:

- tunnel ID
- tunnel-client path
- runtime credential management (replace, test, forget, or switch back to session-only)
- ChatGPT app connection step
- authorized repositories

Changing a tunnel ID invalidates the saved tunnel/App completion state so the wizard does not pretend the old connection is still valid.

## Diagnostics

Choose:

```text
[3] Diagnostics
```

The wizard checks local Node/Git/repository state and can run the built-in Windows Coding Agent doctor.

When a tunnel is configured, you can also choose the full tunnel diagnostic. It asks for the runtime key if needed and invokes `tunnel-client doctor --explain`.

## Start fresh safely

Choose:

```text
[5] Start fresh setup
```

There are two reset levels.

### ChatGPT connection only - recommended

Resets:

- saved tunnel ID
- saved tunnel-client path
- securely saved DPAPI runtime credential, if one exists
- wizard progress

Keeps:

- repository authorization
- repository files
- worktrees
- Git settings

Existing tunnel-client profile files are left alone and are safely overwritten by the next guided `init --force`.

You can also invoke this directly:

```text
Connect-ChatGPT.cmd -ResetSetup
```

### Full Windows Coding Agent setup

This is intentionally harder to trigger. You must type `RESET` explicitly.

The wizard:

1. backs up `config.json` to a timestamped `config.backup.<timestamp>.json`
2. clears the active repository authorization registry
3. clears ChatGPT wizard state
4. leaves existing repositories and worktrees on disk
5. offers to run `Setup.cmd` again

This prevents a tunnel troubleshooting reset from casually destroying local coding state.

## First ChatGPT test

After the bridge is running, try a read-only request first:

```text
Use Windows Coding Agent.
List my authorized repositories and show their current status.
Do not modify anything.
```

Then try an isolated edit:

```text
Use Windows Coding Agent on my-app.
Create an isolated worktree, inspect the repository, make the requested fix,
run the allowlisted tests and validation, show me the resulting diff,
and commit only if the checks pass.
Do not publish to GitHub unless I explicitly ask.
```

When you are ready to publish an accepted commit:

```text
Publish the accepted commit for my-app using the guarded publication flow.
Do not force-push and do not change the configured remote or default branch.
```

Publication still fails if the local repository registration has publication disabled or if the remote/head/fast-forward guards do not pass.

## Permission layers

The intended trust chain is:

```text
ChatGPT action permission
        +
restricted tunnel runtime credential
        +
human local repository authorization
        +
Windows Coding Agent worktree/git guards
```

The tunnel only gives ChatGPT a route to the MCP tools. It does not grant arbitrary Windows filesystem access, arbitrary Git commands, arbitrary remotes, force-push, or the ability to authorize a new local repository.

## Troubleshooting

### Tunnel does not appear in ChatGPT

Check:

- the Platform tunnel is scoped to the correct ChatGPT workspace
- your role has Tunnels Read + Use
- `Connect-ChatGPT.cmd` bridge is still running
- `tunnel-client doctor --profile windows-coding-agent --explain` passes
- your workspace allows the custom app/tunnel connection

### ChatGPT can see the app but cannot modify files

Check both permission layers:

- ChatGPT app **Write actions** are enabled
- the repository was authorized locally
- Windows Coding Agent created an isolated worktree
- the requested npm script is locally allowlisted when applicable

### ChatGPT can commit but cannot push

Enable publication locally for that repository with `Start-Agent.cmd`. A remote ChatGPT session cannot grant itself publication permission.

### Setup became confusing or stale

Use:

```text
Connect-ChatGPT.cmd
  -> [5] Start fresh setup
  -> [1] ChatGPT connection only
```

Then rerun the guided setup. Your authorized repositories remain intact.

## Official OpenAI tunnel documentation

Secure MCP Tunnel project:

```text
https://github.com/openai/tunnel-client
```
