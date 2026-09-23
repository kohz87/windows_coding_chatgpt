# AGENTS.md

## Purpose

This repository is a security-bounded local coding control plane. Preserve the rule that humans authorize repository roots locally and MCP clients operate only within those configured roots and controller-created worktrees.

## Security invariants

- Do not add an arbitrary shell MCP tool.
- Optional external coding-agent CLIs must remain explicit named integrations, disabled by default, locally enabled only, pinned to a locally discovered executable path, and restricted to controller-created worktrees.
- Never expose external-agent permission-bypass flags through MCP.
- Do not let MCP callers authorize new absolute repository paths.
- Do not make canonical repository mutation a normal tool path.
- Do not expose arbitrary Git remote/refspec/force options.
- Preserve SHA-guarded destructive file mutations.
- Preserve realpath containment checks in addition to lexical path checks.
- Publication must remain tied to the locally configured repository and default branch.
- Publication must remain non-force and remote-head guarded.
- Do not persist credentials in config.json.

## Validation

Before committing:

```text
npm test
npm run validate
```

On Windows, also run `Doctor.cmd` after local setup changes when practical.


## Managed runtime invariants

- The Secure MCP Tunnel must target the stable user-scoped bootstrap, not a release extraction directory.
- Managed agent versions live beneath the configured Windows Coding Agent versions root and activation is represented by `active-version.json`.
- Tool paths in `toolchain.json` are rediscoverable non-secret cache entries, not authorization.
- Dependency installation, agent upgrades, rollback, repository authorization, and publication enablement remain local human control-plane actions. Do not expose unrestricted MCP tools for them.
- Automatic tunnel-client installation must use the official OpenAI release and verify SHA-256 before installation. Do not bypass Windows Application Control, WDAC, AppLocker, or Smart App Control.
- Managed updates must validate a staged candidate before changing the active version.
- Repository scripts remain locally allowlisted and use the detected package manager (npm, pnpm, or yarn). No arbitrary shell surface.
