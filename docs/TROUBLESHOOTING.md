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
