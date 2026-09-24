#!/bin/bash
# PostToolUse hook: cargo test 실행 후 Docker 불필요 리소스 정리

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# cargo test / cargo nextest 명령인 경우에만 실행
if ! echo "$COMMAND" | grep -qE 'cargo (test|nextest)'; then
  exit 0
fi

# Docker가 실행 중인지 확인
if ! docker info > /dev/null 2>&1; then
  exit 0
fi

# testcontainers가 만든 컨테이너 정리 (실행 중 + 중단된 것 모두)
# label=org.testcontainers.managed-by=testcontainers 필터로 안전하게 식별
TC_CONTAINERS=$(docker ps -aq --filter "label=org.testcontainers.managed-by=testcontainers" 2>/dev/null)
if [ -n "$TC_CONTAINERS" ]; then
  docker stop $TC_CONTAINERS > /dev/null 2>&1
  docker rm $TC_CONTAINERS > /dev/null 2>&1
fi

# 중단된 컨테이너 + 댕글링 이미지 + 미사용 네트워크 제거 (볼륨은 유지)
docker system prune -f > /dev/null 2>&1

exit 0
