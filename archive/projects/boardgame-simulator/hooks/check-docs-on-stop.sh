#!/bin/bash
# Stop hook: 문서화 대기 마커가 있으면 응답 완료 차단

INPUT=$(cat)

# 무한 루프 방지
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

RUST_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-rust-check"

if [ -f "$RUST_MARKER" ]; then
  BACKEND_DIR="$CLAUDE_PROJECT_DIR/boardgame-simulator-backend"
  if [ -d "$BACKEND_DIR" ]; then
    CHECK_OUTPUT=$(cd "$BACKEND_DIR" && cargo check 2>&1)
    CHECK_EXIT=$?
    if [ $CHECK_EXIT -ne 0 ]; then
      echo "{\"decision\": \"block\", \"reason\": \"cargo check 실패:\\n${CHECK_OUTPUT}\\n\\n컴파일 오류를 수정한 후 완료하세요.\"}"
      exit 0
    fi
  fi
fi

SPEC_MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-spec-check"

if [ -f "$SPEC_MARKER" ]; then
  echo "{\"decision\": \"block\", \"reason\": \"구조적 BE 파일(http 레이어/ports/background)이 변경됐는데 스펙 업데이트가 없습니다.\\n\\n아래 중 해당하는 파일을 업데이트하세요:\\n- specification/dev/backend.md\\n- .claude/code-rules.md\\n\\n업데이트 후 다시 완료하세요.\"}"
  exit 0
fi

MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"

if [ -f "$MARKER" ]; then
  TODAY=$(date +%Y%m%d)
  echo "{\"decision\": \"block\", \"reason\": \"소스 코드가 변경됐는데 작업 로그가 없습니다.\\n\\ndocs/works/${TODAY}-[작업명].md 를 작성한 후 완료하세요.\\n(specification/ 변경도 필요하면 함께 업데이트)\"}"
  exit 0
fi

exit 0
