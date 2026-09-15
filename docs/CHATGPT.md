# ChatGPT integration

Windows Coding Agent v0.1 exposes a local **stdio MCP server**.

Local stdio is directly usable by clients such as Codex that can launch a process on the same Windows machine. A remote ChatGPT session cannot directly spawn a process on your PC, so it requires a supported secure MCP bridge or tunnel between ChatGPT and this local controller.

The public repository intentionally does not bundle private tunnel credentials, API keys, or a machine-specific tunnel binary.

## Controller command

The bridge/tunnel should launch or connect to:

```text
node C:\path\to\windows_coding_chatgpt\src\index.js
```

## Security requirement

The bridge should expose the MCP server only through authenticated transport. Do not expose raw stdio through an unauthenticated public TCP listener.

## Existing private deployments

If you already run Windows Coding Agent behind a secure tunnel, point that transport at the generic `src/index.js` entrypoint after completing local repository setup.

Repository authorization remains local even when MCP calls arrive remotely.

## Planned public transport helper

A future release can add an optional transport/supervisor package once its authentication and installation story can be published without embedding user-specific credentials or paths. The repository/worktree security core does not depend on that transport.
