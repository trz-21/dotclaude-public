#!/bin/bash
# 새 작업 흐름(.claude/github-workflow.md): 작업 전 GitHub 이슈 등록 →
# 이슈 기반 브랜치(feature/issue-<N>-..., fix/issue-<N>-...)에서 작업.
# docs/plans 로컬 플랜 강제 대신, "main 직접 소스 수정"을 차단해 브랜치 흐름을 강제한다.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 소스 파일이 아니면 통과 (문서/설정 수정은 자유)
if ! echo "$FILE_PATH" | grep -qE '(backend/src/|frontend/src/|frontend/app/|backend/tests/|backend/migrations/)'; then
  exit 0
fi

cd "${PROJECT_ROOT}" || exit 0
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# main/master 가 아닌 브랜치에서 작업 중이면 통과 (이슈 기반 브랜치로 간주)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  exit 0
fi

echo '{"decision": "block", "reason": "main에서 소스 코드를 직접 수정하려고 합니다.\n\n새 작업 흐름(.claude/github-workflow.md): 1) GitHub 이슈 등록 → 2) feature/issue-<N>-<slug> 브랜치 생성 후 작업.\n\ngh issue create 로 이슈를 만들고, git checkout -b feature/issue-<N>-<slug> 로 브랜치를 판 뒤 다시 시도하세요."}'
