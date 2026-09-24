#!/bin/bash
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
rm -f "${PROJECT_ROOT}/.claude/.pending-rust-check"
rm -f "${PROJECT_ROOT}/.claude/.pending-spec-check"
rm -f "${PROJECT_ROOT}/.claude/.pending-fe-check"
