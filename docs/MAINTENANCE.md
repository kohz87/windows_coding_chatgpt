# Maintenance

Use the stable maintenance entry points created under:

```text
%USERPROFILE%\.windows-coding-agent\bin\
```

The ChatGPT wizard also exposes the same common actions under **Maintenance / dependencies / updates**.

## Dependency scan and repair

Run:

```text
Install-Dependencies.cmd
```

Required tools are Node.js 20+, npm, npx, and Git. ChatGPT setup additionally requires the OpenAI tunnel client. Node.js LTS and Git can be installed through WinGet with explicit confirmation. The tunnel client can be installed from the verified official OpenAI GitHub release.

Python 3.11+ is optional and first-class in the toolchain. Existing interpreters are discovered automatically; choosing **Install managed Python** installs pinned CPython 3.12.10 under the Windows Coding Agent tools directory without changing PATH. `Install-Dependencies.ps1 -ManagedPython` provides the same non-interactive managed-runtime install. The runtime includes validated `pip` and `venv` support. pnpm and yarn remain optional.

The dependency flow records non-secret executable paths, versions, status, and managed/system source information in `toolchain.json`.

## Process output cap

Local process capture defaults to 20 MiB. From **Maintenance / dependencies / updates** choose **Change process output cap** to select 20, 64, 128, or 256 MiB. The setting is stored in `runtime-settings.json` under the Windows Coding Agent home and is read for new process calls immediately. MCP responses still return bounded output tails, so raising the capture cap prevents long-running tools from being terminated without turning the chat response into an unbounded output stream.

## Self-heal

Self-heal refreshes tool discovery, repairs the managed active installation and stable launchers, and can rewrite a stale tunnel profile to point at the stable MCP bootstrap once a usable tunnel runtime key is available.

It does not change repository authorization or publication policy.

## Update

Run:

```text
Update.cmd
```

or use the Maintenance menu.

The updater:

1. checks the latest GitHub release
2. downloads the exact versioned ZIP
3. verifies SHA-256
4. extracts into staging
5. installs locked dependencies with `npm ci --ignore-scripts`
6. runs tests and validation
7. runs launcher self-tests
8. installs the candidate under the managed versions directory
9. switches the active version only after validation succeeds

The candidate release is also exercised through the same `Install-WcaManagedVersion` path used by the updater before release publication. Managed-install validation writes its full command transcript to `logs\last-managed-install.log` under the Windows Coding Agent home. If `npm ci`, `npm test`, source validation, or the launcher self-test fails, the error includes the last output plus the log path.

## Rollback

Use:

```text
Update.cmd -Rollback
```

or the Maintenance menu.

Rollback requires a valid recorded last-known-good managed version. Repository data and worktrees are not rolled back.

## Windows Application Control

If Windows blocks an executable, Windows Coding Agent reports the path and the policy category rather than attempting to bypass the control. On managed systems, allowlisting may require an administrator.
