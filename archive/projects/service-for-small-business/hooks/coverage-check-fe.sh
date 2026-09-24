#!/bin/bash
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# 프론트 소스가 실제로 변경됐을 때만 실행 (마커 게이트). 대화만 한 턴은 즉시 통과.
[ ! -f "${PROJECT_ROOT}/.claude/.pending-fe-check" ] && exit 0
FE_DIR="${PROJECT_ROOT}/frontend"
[ ! -d "$FE_DIR" ] && exit 0
[ ! -d "$FE_DIR/node_modules" ] && exit 0

cd "$FE_DIR" || exit 0
npm test -- --run --coverage --silent 2>&1 | grep -E "^(All files|src/|Coverage|Threshold)" >&2
exit ${PIPESTATUS[0]}
