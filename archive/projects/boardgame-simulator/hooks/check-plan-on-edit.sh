#!/bin/bash
# PreToolUse hook: 소스 코드 수정 전 플랜 파일 존재 확인

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# docs/plans/ 작성 자체는 허용 (이게 플랜 작성이므로)
if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
  exit 0
fi

# 소스 코드 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE '(boardgame-simulator-backend/src/|boardgame-simulator-frontend/src/|boardgame-simulator-backend/tests/|boardgame-simulator-backend/migrations/)'; then
  exit 0
fi

PLAN_MARKER="$CLAUDE_PROJECT_DIR/.claude/.plan-exists"

if [ -f "$PLAN_MARKER" ]; then
  exit 0
fi

echo "{\"decision\": \"block\", \"reason\": \"소스 코드를 수정하기 전에 작업 플랜을 먼저 작성하세요.\n\ndocs/plans/$(date +%Y%m%d)-[작업명].md 파일을 작성한 뒤 다시 시도하세요.\n\n플랜에 포함할 내용: 목표 / 서브태스크 / 영향 파일 / 테스트 전략\"}"
exit 0
