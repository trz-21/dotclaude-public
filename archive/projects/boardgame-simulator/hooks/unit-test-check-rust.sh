#!/bin/bash
# PostToolUse: src/application/, src/adapters/ 파일 수정 시 단위 테스트 존재 여부 확인

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# .rs 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then
  exit 0
fi

# application/ 또는 adapters/ 내 파일인지 확인
if ! echo "$FILE_PATH" | grep -qE 'boardgame-simulator-backend/src/(application|adapters)/'; then
  exit 0
fi

# 제외: mod.rs, main.rs, lib.rs, config.rs, error.rs
BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(mod|main|lib|config|error)\.rs$'; then
  exit 0
fi

# 파일이 존재하는지 확인
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# #[cfg(test)] 블록 확인
if ! grep -q '#\[cfg(test)\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $(basename "$FILE_PATH")" >&2
  echo "" >&2
  echo "이 파일에 #[cfg(test)] mod tests 블록이 필요합니다:" >&2
  echo "  $FILE_PATH" >&2
  echo "" >&2
  echo "#[cfg(test)]" >&2
  echo "mod tests {" >&2
  echo "    use super::*;" >&2
  echo "" >&2
  echo "    #[test]" >&2
  echo "    fn test_example() { ... }" >&2
  echo "}" >&2
  exit 2
fi

# #[test] 함수가 최소 1개 있는지 확인
if ! grep -q '#\[test\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $(basename "$FILE_PATH")" >&2
  echo "" >&2
  echo "#[cfg(test)] 블록은 있지만 #[test] 함수가 없습니다." >&2
  echo "최소 1개 이상의 #[test] 함수를 추가하세요: $FILE_PATH" >&2
  exit 2
fi

exit 0
