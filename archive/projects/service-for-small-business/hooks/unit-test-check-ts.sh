#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q 'frontend/src/features/'; then exit 0; fi

BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(index|types)\.(ts|tsx)$'; then exit 0; fi
if echo "$FILE_PATH" | grep -q '\.test\.'; then exit 0; fi

DIRNAME=$(dirname "$FILE_PATH")
NAMEBASE="${BASENAME%.*}"
EXT="${BASENAME##*.}"
TEST_FILE="$DIRNAME/${NAMEBASE}.test.${EXT}"

if [ ! -f "$TEST_FILE" ]; then
  echo "테스트 파일 없음: $TEST_FILE" >&2
  exit 2
fi
