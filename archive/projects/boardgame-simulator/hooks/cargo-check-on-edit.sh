#!/bin/bash
# PostToolUse: .rs 파일 수정 시 cargo check + 영향 범위 테스트 자동 실행

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# .rs 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then
  exit 0
fi

# boardgame-simulator-backend 내 파일인지 확인
if ! echo "$FILE_PATH" | grep -q 'boardgame-simulator-backend'; then
  exit 0
fi

BACKEND_DIR="$CLAUDE_PROJECT_DIR/boardgame-simulator-backend"
cd "$BACKEND_DIR" || exit 0

# ── 1. cargo check ────────────────────────────────────────────────────────────
CHECK_OUTPUT=$(cargo check 2>&1)
CHECK_EXIT=$?

if [ $CHECK_EXIT -ne 0 ]; then
  echo "$CHECK_OUTPUT" >&2
  exit 2
fi

# ── 2. 영향 범위 테스트 ────────────────────────────────────────────────────────
BASENAME=$(basename "$FILE_PATH")

# mod.rs, lib.rs, main.rs → 전체 단위 테스트
if echo "$BASENAME" | grep -qE '^(mod|lib|main)\.rs$'; then
  cargo nextest run --lib 2>&1
  exit $?
fi

# tests/ 하위 파일 → 해당 integration test만
if echo "$FILE_PATH" | grep -qE 'boardgame-simulator-backend/tests/[^/]+\.rs$'; then
  TEST_NAME=$(basename "$FILE_PATH" .rs)
  cargo nextest run --test "$TEST_NAME" 2>&1
  exit $?
fi

# src/ 하위 파일 → 모듈 경로로 변환하여 단위 테스트 필터링
if echo "$FILE_PATH" | grep -qE 'boardgame-simulator-backend/src/'; then
  # src/domain/models/game_state.rs → domain::models::game_state
  MODULE=$(echo "$FILE_PATH" \
    | sed 's|.*/boardgame-simulator-backend/src/||' \
    | sed 's|\.rs$||' \
    | sed 's|/|::|g')

  cargo nextest run --lib --filter-expr "test(~$MODULE)" 2>&1
  exit $?
fi

exit 0
