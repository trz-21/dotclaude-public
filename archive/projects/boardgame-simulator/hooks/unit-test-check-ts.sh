#!/bin/bash
# PostToolUse: src/features/**/  파일 수정 시 대응 .test.ts 파일 존재 여부 확인

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# .ts/.tsx 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then
  exit 0
fi

# src/features/ 내 파일인지 확인
if ! echo "$FILE_PATH" | grep -q 'boardgame-simulator-frontend/src/features/'; then
  exit 0
fi

# 제외: index.ts, types.ts, store/index.ts, *.test.ts 자체
BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(index|types)\.(ts|tsx)$'; then
  exit 0
fi
if echo "$FILE_PATH" | grep -q '\.test\.'; then
  exit 0
fi

# 대응 .test.ts 파일 경로 계산
# e.g. src/features/simulation/api/index.ts → src/features/simulation/api/index.test.ts
DIRNAME=$(dirname "$FILE_PATH")
NAMEBASE="${BASENAME%.*}"
EXT="${BASENAME##*.}"
TEST_FILE="$DIRNAME/${NAMEBASE}.test.${EXT}"

# 같은 디렉토리 내 .test.ts 파일도 허용
# (예: hooks/ 디렉토리에 hooks.test.ts 가 있는 경우)
FEATURE_DIR=$(echo "$FILE_PATH" | sed 's|/src/features/\([^/]*\)/.*|/src/features/\1|')

if [ ! -f "$TEST_FILE" ]; then
  # 피처 루트의 __tests__/ 확인
  ALT_TEST="$FEATURE_DIR/__tests__/${NAMEBASE}.test.${EXT}"
  if [ ! -f "$ALT_TEST" ]; then
    echo "단위 테스트 없음: $(basename "$FILE_PATH")" >&2
    echo "" >&2
    echo "대응 테스트 파일이 없습니다. 다음 중 하나를 생성하세요:" >&2
    echo "  $TEST_FILE" >&2
    echo "  $ALT_TEST" >&2
    exit 2
  fi
fi

exit 0
