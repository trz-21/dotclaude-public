#!/bin/bash
# 최근 맥락은 GitHub Issue/PR/Wiki가 canonical이다 (.claude/github-workflow.md).
# 로컬 docs를 더 이상 쌓지 않으므로, 빠른 로컬 신호인 최근 커밋만 주입하고
# 나머지는 GitHub 소스를 가리킨다.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${PROJECT_ROOT}" || exit 0
git rev-parse --git-dir &>/dev/null || exit 0

echo "## 최근 작업 (git log)"
git log --oneline -5 2>/dev/null
echo ""
echo "최근 맥락은 GitHub가 canonical입니다 (.claude/github-workflow.md):"
echo "  - 진행/예정 작업: gh issue list"
echo "  - 최근 작업 로그: gh pr list --state merged"
echo "  - 스펙 최종 현황: GitHub Wiki"
