#!/bin/bash
# Stop hook: FE 커버리지 측정
# vitest.config.ts의 thresholds가 설정되면 미달 시 차단됨

FE_DIR="$CLAUDE_PROJECT_DIR/boardgame-simulator-frontend"

# FE 디렉토리가 없으면 통과
if [ ! -d "$FE_DIR" ]; then
  exit 0
fi

# node_modules 없으면 통과 (초기 세팅 전)
if [ ! -d "$FE_DIR/node_modules" ]; then
  exit 0
fi

cd "$FE_DIR" || exit 0

echo "📊 FE 커버리지 측정 중..." >&2
npm test -- --run --coverage --silent 2>&1 | grep -E "^(All files|src/|Coverage|Threshold)" >&2

# vitest 종료 코드 전달 (thresholds 설정 시 미달이면 자동으로 non-zero)
exit ${PIPESTATUS[0]}
