#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q 'frontend/'; then exit 0; fi

cd "${PROJECT_ROOT}/frontend" || exit 0
TSC_OUTPUT=$(npm run type-check 2>&1)
if [ $? -ne 0 ]; then echo "$TSC_OUTPUT" >&2; exit 2; fi
