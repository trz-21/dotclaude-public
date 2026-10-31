#!/bin/bash
# Claude가 사용자 입력을 기다릴 때 macOS 알림을 띄운다. 누르면 iTerm이 앞으로 온다.
# 질문·명령 내용은 민감할 수 있어 알림에 넣지 않고 고정 문구만 쓴다.
input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // empty')
project=$(basename "$(echo "$input" | jq -r '.cwd // empty')")

if [ "$event" = "PreToolUse" ]; then
  title="Claude 질문"
  msg="답변을 기다리고 있어요"
else
  title="Claude 확인 요청"
  msg="승인이나 입력을 기다리고 있어요"
fi

notifier=/opt/homebrew/bin/terminal-notifier
if ! { [ -x "$notifier" ] && "$notifier" -title "$title" -subtitle "$project" -message "$msg" \
    -activate com.googlecode.iterm2 -group "claude-$project" >/dev/null 2>&1; }; then
  osascript -e "display notification \"$msg\" with title \"$title\" subtitle \"$project\""
fi
