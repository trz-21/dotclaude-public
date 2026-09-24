#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 로컬 docs 누적을 중단했으므로 doc/plan 마커는 더 이상 사용하지 않는다.
# 컴파일/커버리지 안전망 마커(rust/spec/fe)만 유지한다. (.claude/github-workflow.md)
RUST_MARKER="${PROJECT_ROOT}/.claude/.pending-rust-check"
SPEC_MARKER="${PROJECT_ROOT}/.claude/.pending-spec-check"
FE_MARKER="${PROJECT_ROOT}/.claude/.pending-fe-check"

# 프론트 소스 변경 시 fe-check 마커 생성 (Stop 훅의 커버리지 게이트용)
if echo "$FILE_PATH" | grep -qE '(frontend/src/|frontend/app/)'; then
  touch "$FE_MARKER"
fi

# .rs 변경 시 rust-check 마커 생성 (Stop 훅의 cargo check 게이트용)
if echo "$FILE_PATH" | grep -qE 'backend/.*\.rs$'; then
  touch "$RUST_MARKER"
fi

# 구조적 BE 파일 변경 시 spec-check 마커 생성 (Wiki 갱신 리마인드용)
if echo "$FILE_PATH" | grep -qE 'backend/src/(http/(mod|macros|router|state)\.rs|domain/ports/)'; then
  touch "$SPEC_MARKER"
fi
