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

## 3. Authorize a local repository

Double-click:

```text
Setup.cmd
```

or run:

```text
npm install
npm run setup
```

The ASCII setup screen asks you to type or paste a local Git repository directory, for example:

```text
C:\Users\Alice\Projects\my-project
```

The controller verifies the selected directory, detects the Git root, `origin`, GitHub owner/repository when applicable, default branch, and common npm scripts.

Only paths explicitly authorized by the human operator become available to MCP clients. ChatGPT cannot remotely add arbitrary Windows directories.

Setup also asks whether guarded GitHub publication should be enabled. The recommended first-run answer is `No`. Publication can later be toggled from `Start-Agent.cmd`.

## 4. Connect ChatGPT (optional)

If you want ChatGPT itself to call the local MCP, double-click:

```text
Connect-ChatGPT.cmd
```

You do **not** need to pre-open all the OpenAI setup pages manually. The guided wizard walks through them in order and opens the official pages when requested.

The wizard handles:

1. local Node/Git/repository readiness
2. locating or downloading OpenAI `tunnel-client`
3. opening Platform Tunnels and collecting the `tunnel_...` ID
4. opening Runtime API Keys and collecting a restricted **Tunnels Read + Use** key with a hidden prompt
5. creating the local stdio tunnel profile and running `tunnel-client doctor --explain`
6. opening ChatGPT connection settings and showing the exact custom MCP app values

After entering the runtime API key, choose either **Save securely for this Windows user** (DPAPI-encrypted, recommended for convenience) or **Use only for this session**. The literal key is never written to JSON configuration or the package directory.

After first-time setup, the same launcher becomes the day-to-day control panel. Choose `[1] Start ChatGPT bridge`, keep the terminal open, and stop it with `Ctrl+C` when finished.

The launcher also supports resume, diagnostics, reconfiguration, and two fresh-setup modes. The normal ChatGPT-only reset keeps repository authorization and worktrees intact.

See `docs/CHATGPT.md` for the full walkthrough.

## 5. Manage authorized repositories

Run:

```text
Start-Agent.cmd
```

The ASCII repository manager can:

- add a repository
- remove repository authorization
- toggle fast-forward-only GitHub publication

Removing authorization does not delete the repository from disk.

## 6. Run diagnostics

Standalone local diagnostics:

```text
Doctor.cmd
```

or:

```text
npm run doctor
```

For combined local + tunnel diagnostics, use the `[3] Diagnostics` option inside `Connect-ChatGPT.cmd`.

## 7. Connect other MCP clients

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

For a packaged ZIP install, download a newer release into a new directory. The user-level repository registry and ChatGPT wizard state live outside the extracted package under `%USERPROFILE%\.windows-coding-agent` by default, so replacing the program directory does not itself authorize new repositories or copy secrets into the package.
