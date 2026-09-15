# Roadmap

The generic v0.1 release focuses on the reusable security and repository control plane.

Planned follow-up work:

1. local repository manager improvements, including editing npm script allowlists
2. guarded worktree removal and richer diff/log/search tools
3. automatic Codex MCP registration from Setup
4. optional provider/agent orchestration module for Antigravity-style background workers
5. optional authenticated ChatGPT transport/supervisor package
6. optional application adapters, including SillyTavern/NPC State test-host integration
7. signed release packaging and safer updater/rollback workflow
8. broader Windows integration tests for junctions, drive-letter casing, and credential-manager Git flows

Project-specific adapters should remain optional so the core continues to work for ordinary GitHub repositories.
