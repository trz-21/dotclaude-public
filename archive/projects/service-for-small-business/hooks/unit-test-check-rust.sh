#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -qE 'backend/src/(application|adapters)/'; then exit 0; fi

BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(mod|main|lib|config|error)\.rs$'; then exit 0; fi
if [ ! -f "$FILE_PATH" ]; then exit 0; fi

if ! grep -q '#\[cfg(test)\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $BASENAME — #[cfg(test)] mod tests 블록이 필요합니다" >&2
  exit 2
fi
if ! grep -q '#\[test\]' "$FILE_PATH" && ! grep -q '#\[tokio::test\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $BASENAME — #[test] 함수가 최소 1개 필요합니다" >&2
  exit 2
fi
