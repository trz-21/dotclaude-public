---
name: no-local-doc-accumulation
description: User does not want skills writing work-log/plan/session docs into local project directories
metadata: 
  node_type: memory
  type: feedback
---

User does not want Claude skills creating accumulation docs (`docs/works/`, `docs/plans/`, `docs/sessions/`, `docs/decisions/`) in local project directories. Progress should be reported in conversation, not left as files.

**Why:** These dated log files piled up across many projects and were noise the user never wanted.

**How to apply:**
- `task-with-harness` and `init-project` skills were edited (2026-06-16) to remove all doc-writing/reading steps and the doc-enforcement hooks (`check-plan-on-edit`, `session-doc-on-stop`, `load-context-on-start`, and the doc-log block of the Stop hook). Compile/test/spec-sync hooks were kept.
- `specification/` (living spec) is still fine to write/update — that is not accumulation.
- The 3 existing skill-generated docs dirs (boardgame-simulator, service-for-small-business, temp-workspace) were moved to `~/.Trash/claude-docs-cleanup-20260616/` (recoverable).
- When adding/editing any skill, do not introduce local doc-file generation; report in chat instead.
