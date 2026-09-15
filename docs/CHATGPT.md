# ChatGPT integration

Windows Coding Agent can be used from ChatGPT to inspect and modify **local Git repositories that you authorized on the Windows PC**.

The complete path is:

```text
ChatGPT normal chat
        |
        | custom MCP app / plugin
        v
OpenAI Secure MCP Tunnel
        |
        | outbound authenticated connection
        v
tunnel-client.exe on your Windows PC
        |
        | local stdio child process
        v
Windows Coding Agent MCP (src/index.js)
        |
        v
locally authorized Git repositories
        |
        v
isolated worktrees -> tests -> guarded commit -> optional guarded publish
```

ChatGPT never receives permission to browse arbitrary directories. Repository authorization still happens locally with `Setup.cmd` or `Start-Agent.cmd`.

## Requirements

You need:

- Windows Coding Agent installed and `Setup.cmd` completed
- Node.js 20 or newer
- Git for Windows
- OpenAI Secure MCP Tunnel client
- an OpenAI Platform tunnel scoped to the ChatGPT workspace that will use it
- a restricted Runtime API key with **Tunnels Read + Use**
- ChatGPT workspace access to Developer mode/custom MCP apps and the required write actions

ChatGPT product availability and workspace policies can vary by plan. Current OpenAI documentation supports custom MCP app development for managed Business and Enterprise/Edu workspaces when administrators enable it. If Developer mode, Tunnel connections, or Write actions are absent, ask the workspace administrator to enable the corresponding app/MCP permissions.

## 1. Authorize the local repository

Run:

```text
Setup.cmd
```

Select the local Git repository you want ChatGPT to work with. The human operating the Windows machine performs this step. The MCP client cannot add arbitrary repository paths remotely.

If ChatGPT should eventually be allowed to push an accepted commit to the configured GitHub `origin`, enable publication for that repository locally. Otherwise leave publication disabled. Local commits and GitHub publication are separate permissions.

## 2. Install OpenAI Secure MCP Tunnel client

Download the current Windows tunnel client from the official OpenAI project:

```text
https://github.com/openai/tunnel-client/releases/latest
```

Extract `tunnel-client.exe` and either:

- put it on `PATH`, or
- set `TUNNEL_CLIENT_BIN` to its full path, or
- paste the executable path when `Connect-ChatGPT.cmd` asks for it.

You can verify the binary with:

```text
tunnel-client help quickstart
```

Do not download tunnel binaries from unofficial mirrors.

## 3. Create a Platform tunnel

Open:

```text
https://platform.openai.com/settings/organization/tunnels
```

Create a tunnel for this Windows Coding Agent installation. The tunnel must be scoped to the ChatGPT workspace in which you intend to create the custom app. Copy the resulting ID, which begins with `tunnel_`.

The **local tunnel runtime and the ChatGPT custom app must reference the same tunnel ID**.

## 4. Create the runtime API key

Open:

```text
https://platform.openai.com/settings/organization/api-keys
```

Create a restricted Runtime API key for the tunnel daemon with:

```text
Tunnels Read
Tunnels Use
```

Do not use an organization admin key for the long-running tunnel daemon. An admin key is only needed if you choose to manage tunnel metadata through administrative CLI commands.

`Connect-ChatGPT.cmd` asks for the runtime key with a hidden prompt and places it only in the current process environment as `CONTROL_PLANE_API_KEY`. It does not write the literal key into the Windows Coding Agent repository registry or tunnel profile.

You may instead set `CONTROL_PLANE_API_KEY` yourself before starting the launcher.

## 5. Connect this PC to the tunnel

From the extracted Windows Coding Agent directory, double-click:

```text
Connect-ChatGPT.cmd
```

The launcher performs the equivalent of:

```text
tunnel-client init --force ^
  --sample sample_mcp_stdio_local ^
  --profile windows-coding-agent ^
  --tunnel-id <YOUR_TUNNEL_ID> ^
  --mcp-command "node C:\path\to\Windows-Coding-Agent\src\index.js"

tunnel-client doctor --profile windows-coding-agent --explain

tunnel-client run --profile windows-coding-agent
```

The exact Node.js executable and installation path are detected by the launcher, so normal users do not need to construct the command manually.

Keep the terminal window open while ChatGPT is using the local MCP. With a stdio MCP command, OpenAI documents a limit of **one active `tunnel-client` instance per tunnel ID**. Stop the old instance before starting another one for the same tunnel.

No inbound port is exposed. `tunnel-client` makes the authenticated outbound connection to OpenAI and launches Windows Coding Agent locally over stdio.

## 6. Create the ChatGPT custom MCP app

With `Connect-ChatGPT.cmd` running:

1. Open ChatGPT Settings.
2. Open **Plugins** or **Apps** (the label can vary by workspace rollout), then **Advanced settings**.
3. Enable **Developer mode** if it is not already enabled and your workspace permits it.
4. Choose **Create app**, **Create custom app**, or the equivalent custom MCP option.
5. Name it, for example, `Windows Coding Agent`.
6. Choose **Connection: Tunnel**.
7. Select the same Platform tunnel, or paste the same `tunnel_...` ID used on the Windows PC.
8. For the Secure MCP Tunnel connection, choose **Authentication: None** when that field is shown. The local runtime is already authenticated to OpenAI by the tunnel runtime key; there is no separate public MCP bearer token to enter.
9. Let ChatGPT scan/import the MCP tools.
10. Save/create the custom app.

You do **not** need to publish a public Plugin Directory listing just to use Windows Coding Agent yourself or within an authorized workspace. The custom MCP app is the binding between ChatGPT and the tunnel. A published plugin can be considered later if you want a reusable/discoverable packaged workflow.

## 7. Enable write actions

The app must be allowed to perform write actions if you want ChatGPT to edit files, create worktrees, commit changes, or invoke guarded publication.

In the workspace/app administration controls:

1. Enable the Windows Coding Agent app for the appropriate role/users.
2. Under **Actions**, enable the required **Read actions**.
3. Enable the required **Write actions**.
4. For write approvals, the safest default is **Always ask**.

The ChatGPT permission is an outer policy layer. Windows Coding Agent still independently enforces its local repository registry, worktree-only mutation policy, allowlisted npm scripts, guarded commits, and publication setting.

## 8. Use it in ChatGPT

Start a normal ChatGPT conversation and enable/select the `Windows Coding Agent` custom app from the Plugins/Apps/tools UI available in your workspace.

First test with a read-only request:

```text
Use Windows Coding Agent. List my authorized repositories and show their status. Do not modify anything.
```

Then try an isolated edit:

```text
Use Windows Coding Agent on my-app.
Create an isolated worktree, inspect the repository, make the requested fix,
run the allowlisted tests and validation, show me the resulting diff,
and commit only if the checks pass.
Do not publish to GitHub unless I explicitly ask.
```

When you are ready to publish an accepted local commit:

```text
Publish the accepted commit for my-app using the repository's guarded publication flow.
Do not force-push and do not change the configured remote or default branch.
```

Publication will still fail if the local repository registration has publication disabled or if the fast-forward/remote-head guards do not pass.

## Important ChatGPT mode note

For direct write actions through a custom MCP app, use the normal ChatGPT app/plugin experience supported by your workspace. Other modes can have different app/action restrictions. If an app is visible but writes are unavailable, check the workspace's app action settings rather than loosening Windows Coding Agent's local protections.

## Troubleshooting

### The tunnel does not appear in ChatGPT

Check:

- the Platform tunnel is scoped to the correct ChatGPT workspace
- your user/role has Tunnels Read + Use
- `Connect-ChatGPT.cmd` is still running
- `tunnel-client doctor --profile windows-coding-agent --explain` passes
- your workspace allows Developer mode/custom apps

### ChatGPT can see the app but cannot modify files

Check both permission layers:

- ChatGPT workspace/app **Write actions** are enabled
- the repository was authorized locally
- Windows Coding Agent created an isolated worktree
- the requested npm script is locally allowlisted when applicable

### ChatGPT can commit but cannot push

Enable publication locally for that repository with `Start-Agent.cmd`. Windows Coding Agent does not let the remote ChatGPT session grant itself publication permission.

### The tunnel says another stdio runtime is active

Stop the other `tunnel-client` instance using the same tunnel ID, then start only one `Connect-ChatGPT.cmd` window.

## Security summary

The intended trust chain is:

```text
human local authorization
        +
ChatGPT workspace app permissions
        +
restricted tunnel runtime credential
        +
Windows Coding Agent worktree/git guards
```

Do not replace this with a raw public TCP listener, unauthenticated HTTP wrapper, arbitrary-shell MCP server, or a tunnel profile containing literal API keys.

Official OpenAI Secure MCP Tunnel project:

```text
https://github.com/openai/tunnel-client
```
