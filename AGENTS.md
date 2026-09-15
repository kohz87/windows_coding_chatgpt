# AGENTS.md

## Purpose

This repository is a security-bounded local coding control plane. Preserve the rule that humans authorize repository roots locally and MCP clients operate only within those configured roots and controller-created worktrees.

## Security invariants

- Do not add an arbitrary shell MCP tool.
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
