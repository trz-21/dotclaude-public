#!/bin/bash
# PostToolUse: .ts/.tsx 파일 수정 시 타입 체크 자동 실행

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# .ts/.tsx 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then
  exit 0
fi

# boardgame-simulator-frontend 내 파일인지 확인
if ! echo "$FILE_PATH" | grep -q 'boardgame-simulator-frontend'; then
  exit 0
fi

FRONTEND_DIR="$CLAUDE_PROJECT_DIR/boardgame-simulator-frontend"
cd "$FRONTEND_DIR" || exit 0

TSC_OUTPUT=$(npm run type-check 2>&1)
TSC_EXIT=$?

if [ $TSC_EXIT -ne 0 ]; then
  echo "$TSC_OUTPUT" >&2
  exit 2
fi

exit 0
