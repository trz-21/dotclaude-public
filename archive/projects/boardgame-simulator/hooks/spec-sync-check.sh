#!/bin/bash
# Stop hook: 소스 변경에 대응하는 specification/ 업데이트 누락 경고
# 차단(block)하지 않고 경고만 출력 (exit 0)

INPUT=$(cat)

STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

ROOT="$CLAUDE_PROJECT_DIR"

cd "$ROOT" || exit 0

# git이 없거나 repo가 아니면 통과
git rev-parse --git-dir &>/dev/null || exit 0

# 변경된 파일 목록 (staged + unstaged, 삭제 제외)
CHANGED=$(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)
CHANGED=$(echo "$CHANGED" | sort -u)

if [ -z "$CHANGED" ]; then
  exit 0
fi

# 소스-스펙 매핑 체크
MISSING_SPECS=()

check_spec() {
  local spec_file="$1"
  # 스펙 파일 자체가 변경됐으면 통과
  if echo "$CHANGED" | grep -q "^${spec_file}$"; then
    return
  fi
  MISSING_SPECS+=("$spec_file")
}

# BE application/domain/adapters → backend.md
if echo "$CHANGED" | grep -qE "^boardgame-simulator-backend/src/(application|domain|adapters)/"; then
  check_spec "specification/dev/backend.md"
fi

# BE http/handlers/ or http/router.rs → api.md
if echo "$CHANGED" | grep -qE "^boardgame-simulator-backend/src/http/(handlers/|router\.rs)"; then
  check_spec "specification/dev/api.md"
fi

# BE application/engine/ → game-engine.md
if echo "$CHANGED" | grep -qE "^boardgame-simulator-backend/src/application/engine/"; then
  check_spec "specification/dev/game-engine.md"
fi

# FE src/features/ → frontend.md
if echo "$CHANGED" | grep -qE "^boardgame-simulator-frontend/src/features/"; then
  check_spec "specification/dev/frontend.md"
fi

# tests/fixtures/ → harness.md
if echo "$CHANGED" | grep -qE "^boardgame-simulator-backend/tests/fixtures/"; then
  check_spec "specification/dev/harness.md"
fi

# 누락 없으면 통과
if [ ${#MISSING_SPECS[@]} -eq 0 ]; then
  exit 0
fi

# 경고 출력 (차단 아님)
SPEC_LIST=$(printf "  - %s\n" "${MISSING_SPECS[@]}")
echo "⚠️  스펙 동기화 확인 필요:" >&2
echo "$SPEC_LIST" >&2
echo "" >&2
echo "변경 내용이 스펙에 반영됐는지 확인하세요. 불필요하면 무시해도 됩니다." >&2

exit 0
