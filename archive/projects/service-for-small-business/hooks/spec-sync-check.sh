#!/bin/bash
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

cd "${PROJECT_ROOT}" || exit 0
git rev-parse --git-dir &>/dev/null || exit 0

# 스펙의 최종 현황은 GitHub Wiki(canonical). 구조적 코드 변경 시,
# 갱신이 필요할 수 있는 Wiki 페이지를 비차단으로 리마인드한다. (.claude/github-workflow.md)
#
# 탐지 소스 = 워킹트리/스테이징 diff ∪ 피처 브랜치 커밋 diff.
# diff(uncommitted)만 보면 커밋 직후 리마인드가 사라진다(작업 마무리 시점엔 이미 커밋됨).
# 따라서 현재 브랜치가 main/master가 아니면 merge-base 이후 커밋분도 함께 본다. (refs #32)
WORKING=$(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)

COMMITTED=""
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null)
  [ -n "$BASE" ] && COMMITTED=$(git diff --name-only "$BASE"...HEAD 2>/dev/null)
fi

CHANGED=$(printf '%s\n%s\n' "$WORKING" "$COMMITTED" | sort -u | grep -v '^$')
[ -z "$CHANGED" ] && exit 0

PAGES=()
echo "$CHANGED" | grep -qE "^backend/src/(application|domain|adapters)/" && PAGES+=("Backend")
echo "$CHANGED" | grep -qE "^backend/src/http/(handlers/|router\.rs)" && PAGES+=("API")
echo "$CHANGED" | grep -qE "^frontend/(src/features/|src/shared/|app/)" && PAGES+=("Frontend")
echo "$CHANGED" | grep -qE "^(frontend/tests/|backend/tests/|\.github/workflows/)" && PAGES+=("Harness")

[ ${#PAGES[@]} -eq 0 ] && exit 0

# 중복 페이지 제거
PAGES=($(printf '%s\n' "${PAGES[@]}" | sort -u))

echo "⚠️  코드 변경 감지 — GitHub Wiki 페이지 갱신이 필요한지 확인하세요:" >&2
printf "  - Wiki: %s\n" "${PAGES[@]}" >&2