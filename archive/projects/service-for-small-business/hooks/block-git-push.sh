#!/bin/bash
COMMAND=$(jq -r '.tool_input.command // ""' 2>/dev/null)
if echo "$COMMAND" | grep -qE '^\s*git push'; then
  echo '{"continue": false, "stopReason": "git push는 사용자가 명시적으로 요청할 때만 실행합니다."}'
  exit 0
fi
