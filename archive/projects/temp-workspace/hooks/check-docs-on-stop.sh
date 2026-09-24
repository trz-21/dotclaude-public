#!/usr/bin/env bash
# Stop hook: 마커 파일이 존재하면 응답을 차단하고 문서 작성을 요구한다.

MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"

if [ "${stop_hook_active}" = "true" ]; then
  exit 0
fi

if [ -f "$MARKER" ]; then
  echo '{
  "decision": "block",
  "reason": "소스 파일이 수정되었으나 docs/works/ 작업 로그가 없습니다. docs/works/YYYYMMDD-slug.md 를 작성한 후 다시 완료하세요."
}'
fi
