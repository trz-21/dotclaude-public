#!/usr/bin/env bash
# PostToolUse: 소스 파일 수정 시 .pending-doc-check 마커를 생성한다.
# docs/works/ 또는 specification/ 파일 수정 시에는 마커를 제거한다.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

MARKER="$CLAUDE_PROJECT_DIR/.claude/.pending-doc-check"

# 문서 경로이면 마커 제거 (작업 완료로 간주)
if echo "$FILE_PATH" | grep -qE "(docs/works/|specification/)"; then
  rm -f "$MARKER"
  exit 0
fi

# 소스 경로이면 마커 생성
if echo "$FILE_PATH" | grep -qE "(src/|tests/|migrations/)"; then
  touch "$MARKER"
fi
