#!/bin/bash
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 컴파일 안전망은 유지. 작업 로그/스펙 동기화는 새 흐름에서 PR 본문/Wiki가 담당하므로
# 로컬 docs 강제 블록은 제거하고, 구조적 BE 변경 시 Wiki 갱신을 비차단 리마인드한다.
# (PR/Wiki 절차: .claude/github-workflow.md)
RUST_MARKER="${PROJECT_ROOT}/.claude/.pending-rust-check"
SPEC_MARKER="${PROJECT_ROOT}/.claude/.pending-spec-check"

if [ -f "$RUST_MARKER" ]; then
  BACKEND_DIR="${PROJECT_ROOT}/backend"
  CHECK_OUTPUT=$(cd "$BACKEND_DIR" && cargo check 2>&1)
  if [ $? -ne 0 ]; then
    echo "{\"decision\": \"block\", \"reason\": \"cargo check 실패. 컴파일 오류를 수정한 후 완료하세요.\"}"
    exit 0
  fi
fi

if [ -f "$SPEC_MARKER" ]; then
  echo "⚠️  구조적 BE 변경 감지: 관련 GitHub Wiki 페이지(Backend/API 등) 갱신이 필요한지 확인하세요. (.claude/github-workflow.md)" >&2
fi

exit 0
