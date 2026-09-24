#!/bin/bash
# PostToolUse hook: 소스 코드 변경 시 문서화 대기 마커 생성

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"
RUST_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-rust-check"
SPEC_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-spec-check"

PLAN_MARKER="$CLAUDE_PROJECT_DIR/.claude/.plan-exists"

# docs/plans/ 가 작성되면 플랜 마커 생성
if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
  touch "$PLAN_MARKER"
  exit 0
fi

# docs/works/ 또는 specification/ 또는 .claude/code-rules.md 가 작성되면 마커 제거
if echo "$FILE_PATH" | grep -qE '(docs/works/|specification/)'; then
  rm -f "$MARKER"
  rm -f "$RUST_MARKER"
  rm -f "$SPEC_MARKER"
  exit 0
fi

if echo "$FILE_PATH" | grep -qE '\.claude/code-rules\.md$'; then
  rm -f "$SPEC_MARKER"
  exit 0
fi

# 소스 코드 파일이 변경되면 마커 생성
if echo "$FILE_PATH" | grep -qE '(boardgame-simulator-backend/src/|boardgame-simulator-frontend/src/|boardgame-simulator-backend/tests/|boardgame-simulator-backend/migrations/)'; then
  touch "$MARKER"
fi

# .rs 파일이 변경되면 rust-check 마커 생성
if echo "$FILE_PATH" | grep -qE 'boardgame-simulator-backend/.*\.rs$'; then
  touch "$RUST_MARKER"
fi

# 구조적 BE 파일 변경 시 spec-check 마커 생성
# (http 레이어 구조, ports, state, macros, background 모듈)
if echo "$FILE_PATH" | grep -qE 'boardgame-simulator-backend/src/(http/(mod|macros|router|state)\.rs|http/background/|domain/ports/)'; then
  touch "$SPEC_MARKER"
fi

exit 0
