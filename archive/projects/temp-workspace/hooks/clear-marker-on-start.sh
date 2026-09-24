#!/usr/bin/env bash
# SessionStart hook: 새 세션 시작 시 마커를 초기화한다.

MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"
rm -f "$MARKER"
