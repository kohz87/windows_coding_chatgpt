# Installation

## 1. Install prerequisites

Install:

- Windows 10/11
- Node.js 20+
- Git for Windows

Confirm from Command Prompt:

```text
node --version
git --version
```

## 2. Get Windows Coding Agent

Recommended: download the versioned ZIP from:

```text
https://github.com/kohz87/windows_coding_chatgpt/releases
```

Verify the ZIP against the matching `.sha256` asset when appropriate, then extract it.

Developers can instead clone:

```text
git clone https://github.com/kohz87/windows_coding_chatgpt.git
cd windows_coding_chatgpt
```

## 3. Run local setup

Double-click `Setup.cmd` or run:

```text
npm install
npm run setup
```

The wizard asks you to type or paste the local directory of a Git repository.

Example:

```text
C:\Users\Alice\Projects\my-project
```

The controller verifies the selected directory rather than trusting the text blindly. It detects the Git root, `origin`, GitHub owner/repository when applicable, default branch, and common npm scripts.

The human-selected path becomes an authorized repository ID. Remote MCP clients cannot register arbitrary Windows directories for themselves.

## 4. Choose publication permission

Setup asks whether guarded GitHub publication should be enabled.

The recommended first-run answer is `No`.

When disabled, AI clients may still inspect, create worktrees, edit worktree files, run allowlisted checks, and create local commits, but they cannot push through the controller.

Publication can later be toggled from `Start-Agent.cmd`.

## 5. Connect ChatGPT (optional)

If you want ChatGPT itself to call the local MCP and work on the authorized local Git repository, install OpenAI Secure MCP Tunnel client from:

```text
https://github.com/openai/tunnel-client/releases/latest
```

Then create:

1. a Platform tunnel scoped to the ChatGPT workspace:

   ```text
   https://platform.openai.com/settings/organization/tunnels
   ```

2. a restricted Runtime API key with **Tunnels Read + Use**:

   ```text
   https://platform.openai.com/settings/organization/api-keys
   ```

Then run:

```text
Connect-ChatGPT.cmd
```

The launcher links the Secure MCP Tunnel directly to the local stdio command for `src/index.js`, runs the tunnel diagnostic, and prints the ChatGPT custom MCP app/plugin setup steps.

Keep the tunnel window running while ChatGPT needs access.

The full end-to-end guide, including ChatGPT Developer mode, Connection: Tunnel, action permissions, test prompts, and troubleshooting, is in `docs/CHATGPT.md`.

## 6. Manage authorized repositories

Run:

```text
Start-Agent.cmd
```

Available actions:

- Add repository
- Remove repository authorization
- Toggle publication permission

Removing authorization does not delete the repository from disk.

## 7. Run diagnostics

```text
Doctor.cmd
```

or:

```text
npm run doctor
```

Doctor checks Node.js, Git, configuration validity, registered repository roots, and configured GitHub origins.

For tunnel-specific diagnostics, use:

```text
tunnel-client doctor --profile windows-coding-agent --explain
```

## 8. Connect other MCP clients

The local MCP server entrypoint is:

```text
node C:\path\to\windows_coding_chatgpt\src\index.js
```

For Codex, see `docs/CODEX.md`.

For ChatGPT, see `docs/CHATGPT.md`.

## Updating

If installed from Git, `Update.cmd` performs:

```text
git pull --ff-only
npm install
npm test
npm run validate
```

It deliberately refuses non-fast-forward Git updates.

For a packaged ZIP install, download a newer release into a new directory. The user-level repository registry lives outside the extracted package under `%USERPROFILE%\.windows-coding-agent` by default, so replacing the program directory does not itself authorize new repositories.
