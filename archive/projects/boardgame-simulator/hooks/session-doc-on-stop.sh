#!/bin/bash
# Stop hook: 세션 종료 시 트랜스크립트 기반 세션 정리 문서 생성

INPUT=$(cat)

# 무한 루프 방지
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

ROOT="$CLAUDE_PROJECT_DIR"
SESSION_DIR="$ROOT/docs/sessions"
TODAY=$(date +%Y%m%d)
NOW=$(date +%H%M%S)
SESSION_FILE="$SESSION_DIR/${TODAY}-${NOW}.md"

mkdir -p "$SESSION_DIR"

# ── 대화 추출 (user/assistant 메시지만, 최근 30000자로 제한) ──────────────────
CONVERSATION=$(
  jq -r '
    select(.type == "user" or .type == "assistant") |
    if .type == "user" then
      "[사용자] " + (
        .message.content |
        if type == "string" then .
        elif type == "array" then map(select(.type == "text") | .text) | join("")
        else "" end
      )
    else
      "[Claude] " + (
        .message.content |
        if type == "array" then map(select(.type == "text") | .text) | join("") | .[0:500]
        elif type == "string" then .[0:500]
        else "" end
      )
    end
  ' "$TRANSCRIPT" 2>/dev/null | \
  grep -v '^$' | \
  tail -c 30000
)

if [ -z "$CONVERSATION" ]; then
  exit 0
fi

# ── claude CLI로 세션 정리 문서 생성 ─────────────────────────────────────────
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << 'PROMPT_EOF'
아래는 Claude Code 세션의 대화 내용이야. 이 세션에서 있었던 일을 다음 형식의 마크다운 문서로 정리해줘. 요약이 아니라 나중에 이 세션을 되돌아봤을 때 무슨 일이 있었는지 파악할 수 있도록 구체적으로 작성해.

형식:
# 세션 정리 - DATE_PLACEHOLDER

## 작업 목표
이 세션에서 무엇을 하려 했는지

## 진행한 작업
구체적으로 무엇을 구현/수정/해결했는지. 파일명과 변경 내용 포함.

## 주요 결정과 이유
중요한 기술적 결정과 그 배경

## 발생한 문제와 해결
버그, 컴파일 오류, 설계 문제 등과 해결 방법

## 다음 세션에서 이어할 것
완료 못한 작업, 개선 필요한 부분

---
대화 내용:
PROMPT_EOF

echo "DATE_PLACEHOLDER = ${TODAY}" >> "$PROMPT_FILE"
echo "" >> "$PROMPT_FILE"
echo "$CONVERSATION" >> "$PROMPT_FILE"

RESULT=$(claude --print "$(cat "$PROMPT_FILE")" 2>/dev/null)
rm -f "$PROMPT_FILE"

if [ -n "$RESULT" ]; then
  # DATE_PLACEHOLDER 치환
  echo "${RESULT/DATE_PLACEHOLDER/$TODAY}" > "$SESSION_FILE"
fi

exit 0
