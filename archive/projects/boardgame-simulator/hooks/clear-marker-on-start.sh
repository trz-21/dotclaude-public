#!/bin/bash
# SessionStart hook: 이전 세션의 마커 초기화
MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"
RUST_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-rust-check"
SPEC_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-spec-check"
PLAN_MARKER="$CLAUDE_PROJECT_DIR/.claude/.plan-exists"
rm -f "$MARKER"
rm -f "$RUST_MARKER"
rm -f "$SPEC_MARKER"
rm -f "$PLAN_MARKER"
exit 0
