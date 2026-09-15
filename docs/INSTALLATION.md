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

Clone:

```text
git clone https://github.com/kohz87/windows_coding_chatgpt.git
cd windows_coding_chatgpt
```

or download and extract the repository ZIP.

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

The controller verifies the selected directory rather than trusting the text blindly.

It detects:

- Git repository root
- `origin` remote, when present
- GitHub owner/repository, when `origin` points to github.com
- default branch
- common npm scripts such as `test`, `validate`, `build`, `lint`, `package`, `typecheck`, and `check`

The detected npm scripts become that repository's initial execution allowlist.

## 4. Choose publication permission

Setup asks whether guarded GitHub publication should be enabled.

The recommended first-run answer is `No`.

When disabled, AI clients may still inspect, create worktrees, edit worktree files, run allowlisted checks, and create local commits, but they cannot push through the controller.

Publication can later be toggled from `Start-Agent.cmd`.

## 5. Manage authorized repositories

Run:

```text
Start-Agent.cmd
```

Available actions:

- Add repository
- Remove repository authorization
- Toggle publication permission

Removing authorization does not delete the repository from disk.

## 6. Run diagnostics

```text
Doctor.cmd
```

or:

```text
npm run doctor
```

Doctor checks Node.js, Git, configuration validity, registered repository roots, and configured GitHub origins.

## 7. Connect an MCP client

The actual MCP server entrypoint is:

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
