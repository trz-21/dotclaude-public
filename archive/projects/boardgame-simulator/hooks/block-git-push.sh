#!/bin/bash
# git push를 자동으로 실행하지 못하도록 차단
# 사용자가 명시적으로 요청한 경우에만 허용

COMMAND=$(jq -r '.tool_input.command // ""' 2>/dev/null)

if echo "$COMMAND" | grep -qE '^\s*git push'; then
    echo '{"continue": false, "stopReason": "git push는 사용자가 명시적으로 요청할 때만 실행합니다. 푸시가 필요하면 직접 요청해주세요."}'
    exit 0
fi
