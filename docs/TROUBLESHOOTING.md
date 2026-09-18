# Troubleshooting

## Run Doctor first

```text
Doctor.cmd
```

or:

```text
npm run doctor
```

## Node.js not found

Install Node.js 20 or newer, reopen Command Prompt, and verify:

```text
node --version
```

## Git not found

Install Git for Windows and verify:

```text
git --version
```

## Repository is not a Git repository

The directory selected during setup must be inside an existing Git working tree.

Use:

```text
git status
```

inside that directory to verify it.

## Origin no longer matches

For repositories registered with a GitHub slug, the controller checks both fetch and push `origin` URLs every time it resolves the repository.

If you intentionally changed remotes, remove the old authorization and add the repository again locally.

## Publishing is disabled

Run `Start-Agent.cmd`, choose `P`, and toggle publication for the repository.

Publication remains fast-forward-only.

## Script is not allowlisted

Only locally configured npm script names can run through `run_npm_script`.

If a new repository script should be trusted, update that repository's `allowedNpmScripts` in the local configuration. A future manager screen will provide a UI for editing this list.

## Stale SHA error

Read the file again. A stale SHA means the file changed after the previous inspection. This is a concurrency guard, not corruption.

## MCP server prints nothing

That is normal. MCP protocol traffic uses stdio. Human-facing status output from the server goes to stderr.

Use an MCP client or inspector rather than launching `src/index.js` as an interactive menu.

## ERR_MODULE_NOT_FOUND points at an older Windows-Coding-Agent folder

This was possible in v0.1.4 and earlier because the tunnel profile could contain the absolute path to the extracted release folder. v0.1.5 uses a stable user-scoped MCP bootstrap instead.

Install v0.1.5 with `Setup.cmd`, then use **Maintenance -> Self-heal paths, bootstrap, and tunnel profile** or start the bridge once. With a valid saved/runtime tunnel key, the wizard detects the stale MCP command and rewrites the tunnel profile against the stable bootstrap.

## Windows Application Control blocked tunnel-client.exe

If PowerShell reports that an Application Control policy blocked `tunnel-client.exe`, Windows rejected the process before the OpenAI client ran. This is not an API-key or tunnel-ID error.

v0.1.5 catches this condition and reports the executable path instead of dumping a terminating PowerShell exception. Check Windows Security / App Control, WDAC, AppLocker, or organizational policy. On a managed PC, an administrator may need to allow the verified executable. Windows Coding Agent does not disable those controls.

## Node.js, npm, npx, Git, or tunnel-client moved

Open **Maintenance -> Scan / install dependencies** or **Maintenance -> Self-heal**. The toolchain registry is a cache, not an authority: stale paths are rediscovered from known locations and PATH, then `toolchain.json` is refreshed.

## npm or another package manager is missing

`Setup.cmd` checks Node.js 20+, npm, npx, and Git before creating the managed installation. Node.js LTS and Git can be installed through WinGet with your confirmation. pnpm and yarn remain optional and can be installed from the local dependency wizard when required.

## An update fails validation

A candidate update is staged and tested before `active-version.json` changes. If validation fails, the existing active version remains in use. If a newly activated version later becomes unusable and a previous managed version exists, choose **Maintenance -> Roll back to last-known-good agent version**.
