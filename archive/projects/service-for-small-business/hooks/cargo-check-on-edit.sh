#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q 'backend/'; then exit 0; fi

BACKEND_DIR="${PROJECT_ROOT}/backend"
cd "$BACKEND_DIR" || exit 0

CHECK_OUTPUT=$(cargo check 2>&1)
if [ $? -ne 0 ]; then echo "$CHECK_OUTPUT" >&2; exit 2; fi

BASENAME=$(basename "$FILE_PATH")

# mod.rs, lib.rs, main.rs → 전체 단위 테스트
if echo "$BASENAME" | grep -qE '^(mod|lib|main)\.rs$'; then
  cargo nextest run --lib 2>&1; exit $?
fi

# tests/ 하위 → 해당 integration test만
if echo "$FILE_PATH" | grep -qE 'backend/tests/[^/]+\.rs$'; then
  TEST_NAME=$(basename "$FILE_PATH" .rs)
  cargo nextest run --test "$TEST_NAME" 2>&1; exit $?
fi

# src/ 하위 → 모듈 경로로 변환하여 단위 테스트 필터
if echo "$FILE_PATH" | grep -qE 'backend/src/'; then
  MODULE=$(echo "$FILE_PATH" | sed 's|.*/backend/src/||' | sed 's|\.rs$||' | sed 's|/|::|g')
  cargo nextest run --lib --filter-expr "test(~$MODULE)" 2>&1; exit $?
fi
