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

Required tools are Node.js 20+, npm, npx, and Git. ChatGPT setup additionally requires the OpenAI tunnel client. Node.js LTS and Git can be installed through WinGet with explicit confirmation. The tunnel client can be installed from the verified official OpenAI GitHub release. pnpm and yarn are optional.

The dependency flow records non-secret executable paths and versions in `toolchain.json`.

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

## Rollback

Use:

```text
Update.cmd -Rollback
```

or the Maintenance menu.

Rollback requires a valid recorded last-known-good managed version. Repository data and worktrees are not rolled back.

## Windows Application Control

If Windows blocks an executable, Windows Coding Agent reports the path and the policy category rather than attempting to bypass the control. On managed systems, allowlisting may require an administrator.
