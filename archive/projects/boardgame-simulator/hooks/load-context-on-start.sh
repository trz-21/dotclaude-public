#!/bin/bash
# SessionStart hook: 직전 세션 로그 + 최근 작업 로그를 Claude 컨텍스트에 주입

ROOT="$CLAUDE_PROJECT_DIR"
SESSIONS_DIR="$ROOT/docs/sessions"
WORKS_DIR="$ROOT/docs/works"

OUTPUT=""

# ── 직전 세션 로그 ────────────────────────────────────────────────────────────
LAST_SESSION=$(ls -t "$SESSIONS_DIR"/*.md 2>/dev/null | head -1)
if [ -n "$LAST_SESSION" ]; then
  OUTPUT+="## 직전 세션 요약 ($(basename "$LAST_SESSION" .md))\n"
  OUTPUT+="$(cat "$LAST_SESSION")\n\n"
fi

# ── 최근 작업 로그 (최대 3개) ─────────────────────────────────────────────────
RECENT_WORKS=$(ls -t "$WORKS_DIR"/*.md 2>/dev/null | head -3)
if [ -n "$RECENT_WORKS" ]; then
  OUTPUT+="## 최근 작업 로그\n"
  for f in $RECENT_WORKS; do
    OUTPUT+="### $(basename "$f" .md)\n"
    # 각 작업 로그의 첫 20줄만 (요약 부분)
    OUTPUT+="$(head -20 "$f")\n\n"
  done
fi

if [ -n "$OUTPUT" ]; then
  echo -e "$OUTPUT"
fi

exit 0
