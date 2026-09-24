#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if ! echo "$COMMAND" | grep -qE 'cargo (test|nextest)'; then exit 0; fi
if ! docker info > /dev/null 2>&1; then exit 0; fi

TC_CONTAINERS=$(docker ps -aq --filter "label=org.testcontainers.managed-by=testcontainers" 2>/dev/null)
if [ -n "$TC_CONTAINERS" ]; then
  docker stop $TC_CONTAINERS > /dev/null 2>&1
  docker rm $TC_CONTAINERS > /dev/null 2>&1
fi
docker system prune -f > /dev/null 2>&1
