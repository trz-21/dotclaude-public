#!/bin/bash
# dotclaude 자동 동기화. SessionEnd 훅에서 `sync.sh --detach` 로 불린다 (훅은 바로 끝나고 워커가 백그라운드로 돈다).
#
# 원본 레포(~/.claude/dotclaude/source)
#   1) 원격 변경 가져오기 + 링크 점검 (install.sh --repair)
#   2) ~/.claude 에 새로 생긴 스킬·에이전트·커맨드·메모리를 원본 레포로 흡수
#   3) 프로젝트별 .claude 를 projects/ 로 미러
#   4) 플러그인·MCP 설정을 setup/ 에 기록
#   5) 스킬·프로젝트 사용 기록 누적 (state/usage/<호스트>.json)
#   6) 7일마다 아카이브 검토 (archive-review.py)
#   7) 커밋·푸시
# 공개 레포(~/.claude/dotclaude/export, 등록돼 있을 때만)
#   8) 원격 상태로 맞춘 뒤 export.py 로 다시 만들고, 유출 검사(pre-commit)를 통과하면 커밋·푸시
#
#   sync.sh             지금 바로 실행
#   sync.sh --detach    훅용 (2분 안에 다시 불리면 건너뜀)
#   sync.sh --no-push   커밋까지만
#   sync.sh --no-review Claude 무인 실행(아카이브 판단·공개 검토)을 하지 않는다 (새 기기 첫 확인 등)

REG="$HOME/.claude/dotclaude"
BIN="$(cd "$(dirname "$0")" && pwd -P)"
LOG="$HOME/.claude/dotclaude-sync.log"
LOCK="$HOME/.claude/.dotclaude-sync.lock"
STAMP="$HOME/.claude/.dotclaude-sync.last"

if [ "${1:-}" = --detach ]; then
  [ -n "${CLAUDE_HOOK_CHILD:-}" ] && exit 0   # 워커가 띄운 claude 세션에서는 돌지 않는다
  cat > /dev/null                              # 훅 입력은 쓰지 않는다
  nohup python3 -c 'import os,sys; os.setsid(); os.execv(sys.argv[1], sys.argv[1:])' \
    "$0" --hook >> "$LOG" 2>&1 < /dev/null &
  exit 0
fi
PUSH=1; REVIEW=1
for a in "$@"; do case "$a" in --no-push) PUSH=0 ;; --no-review) REVIEW=0 ;; esac; done
# claude 명령(plugin list 등)이 끝날 때도 SessionEnd 가 불려서, 2분 안에 다시 불리면 건너뛴다
if [ "${1:-}" = --hook ] && [ -n "$(find "$STAMP" -mmin -2 2>/dev/null)" ]; then exit 0; fi

SRC="$(cd "$REG/source" 2>/dev/null && pwd -P)" || { echo "원본 레포가 등록되지 않음 (install.sh 먼저)" >&2; exit 1; }
OUT="$(cd "$REG/export" 2>/dev/null && pwd -P)" || OUT=""
HOST="$(hostname -s)"
HOMEENC="$(python3 -c 'import os,re; print(re.sub(r"[^A-Za-z0-9]", "-", os.environ["HOME"]))')"   # install.sh 와 같은 규칙

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# 동시에 여러 세션이 끝나도 한 번에 하나만. 30분 넘은 잠금은 죽은 것으로 본다
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then rmdir "$LOCK"; mkdir "$LOCK" || exit 0
  else log "다른 동기화가 진행 중이라 건너뜀"; exit 0; fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
log "sync 시작"

online() { [ -n "$(git -C "$1" remote)" ] && [ $PUSH = 1 ]; }

commit_push() {  # repo message
  git -C "$1" add -A
  if ! git -C "$1" diff --cached --quiet; then
    git -C "$1" commit -q -m "$2" 2>>"$LOG" || { log "커밋 실패 (유출 검사 등): $1"; git -C "$1" reset -q; return 1; }
  fi
  online "$1" || return 0
  git -C "$1" pull -q --rebase --autostash 2>>"$LOG" || { git -C "$1" rebase --abort 2>/dev/null; log "pull 충돌: $1 — 수동으로 해결 필요"; return 1; }
  git -C "$1" push -q 2>>"$LOG" || log "push 실패: $1"
}

# ---------------------------------------------------------------- 1) 가져오기 + 링크
if online "$SRC"; then
  git -C "$SRC" pull -q --rebase --autostash 2>>"$LOG" || { git -C "$SRC" rebase --abort 2>/dev/null; log "pull 충돌: $SRC — 수동으로 해결 필요"; }
fi
"$SRC/install.sh" --repair 2>>"$LOG"

# ---------------------------------------------------------------- 2) 흡수
adopt() {  # 원본(실제 파일·디렉토리) 레포_목적지
  [ -e "$2" ] && { log "흡수 건너뜀 (레포에 같은 이름 있음): $1"; return; }
  mkdir -p "$(dirname "$2")"
  mv "$1" "$2" && ln -s "$2" "$1" && log "흡수: $1 → $2"
}
for kind in skills agents commands; do
  for p in "$HOME/.claude/$kind"/*; do
    [ -e "$p" ] && [ ! -L "$p" ] || continue
    case "$(basename "$p")" in synced) continue ;; esac   # claude.ai 스킬 동기화 폴더
    adopt "$p" "$SRC/$kind/$(basename "$p")"
  done
done
for m in "$HOME/.claude/projects"/*/memory; do
  [ -d "$m" ] && [ ! -L "$m" ] && [ -n "$(ls -A "$m")" ] || continue
  enc="$(basename "$(dirname "$m")")"
  [[ "$enc" == "$HOMEENC"* ]] || continue
  adopt "$m" "$SRC/memory/HOME${enc#$HOMEENC}"
done

# ---------------------------------------------------------------- 3) 프로젝트 .claude 미러
"$BIN/mirror-projects.sh" "$SRC" 2>>"$LOG"

# ---------------------------------------------------------------- 4) 플러그인·MCP 기록
mkdir -p "$SRC/setup"
P="$HOME/.claude/plugins"
# jq 가 실패하면 기존 기록을 그대로 둔다 (빈 파일로 덮어쓰지 않게 임시 파일에 쓴 뒤 옮김)
write_json() { local tmp="$1.tmp"; if "${@:2}" > "$tmp" && [ -s "$tmp" ]; then mv "$tmp" "$1"; else rm -f "$tmp"; log "기록 실패: $1"; fi; }
[ -f "$P/known_marketplaces.json" ] && [ -f "$P/installed_plugins.json" ] && write_json "$SRC/setup/plugins.json" jq -S -n \
  --slurpfile km "$P/known_marketplaces.json" --slurpfile ip "$P/installed_plugins.json" \
  '{marketplaces: ($km[0] | with_entries(.value |= .source)),
    plugins: [$ip[0].plugins | to_entries[] | {id: .key, scope: (.value[0].scope // "user")}] | sort_by(.id)}'
# 비밀 값(env, headers, oauth)은 키만 남기고 <SET_ME> 로 가린다. 로컬 스코프 경로는 홈 안이면 ~ 기준으로
[ -f "$HOME/.claude.json" ] && write_json "$SRC/setup/mcp.json" jq -S --arg home "$HOME" '
  def redact: reduce ("env", "headers", "oauth") as $k (.; if (.[$k] | type) == "object" then .[$k] |= map_values("<SET_ME>") else . end);
  def tilde: if startswith($home + "/") then "~" + ltrimstr($home) else . end;
  {user: ((.mcpServers // {}) | map_values(redact)),
   local: ([.projects // {} | to_entries[] | select((.value.mcpServers // {}) | length > 0)
            | {key: (.key | tilde), value: (.value.mcpServers | map_values(redact))}] | from_entries)}' \
  "$HOME/.claude.json"

# ---------------------------------------------------------------- 5) 사용 기록
python3 "$BIN/usage.py" "$SRC/state/usage/$HOST.json" 2>>"$LOG"

# ---------------------------------------------------------------- 6) 주간 아카이브 검토
last="$(cat "$SRC/state/last-archive-review" 2>/dev/null || echo 0)"
if [ $REVIEW = 1 ] && [ $(( $(date +%s) - last )) -gt $((7 * 86400)) ]; then
  log "아카이브 검토 시작"
  if python3 "$BIN/archive-review.py" >> "$LOG" 2>&1; then
    date +%s > "$SRC/state/last-archive-review"
    "$SRC/install.sh" --repair 2>>"$LOG"   # 아카이브된 항목의 링크 정리
    log "아카이브 검토 완료"
  else
    echo $(( $(date +%s) - 6 * 86400 )) > "$SRC/state/last-archive-review"   # 매 세션 재시도하지 않고 하루 뒤에
    log "아카이브 검토 실패 — 하루 뒤 다시 시도"
  fi
fi

# ---------------------------------------------------------------- 7) 원본 커밋·푸시
commit_push "$SRC" "sync: $HOST $(date '+%F %H:%M')"
"$SRC/install.sh" --repair 2>>"$LOG"   # pull 로 들어온 새 항목 링크

# ---------------------------------------------------------------- 8) 공개 사본
if [ -n "$OUT" ]; then
  # 공개 레포는 결과물이라 로컬 변경을 두지 않는다: 원격 상태로 맞춘 뒤 다시 만든다
  if online "$OUT"; then
    git -C "$OUT" fetch -q 2>>"$LOG" && git -C "$OUT" reset -q --hard "@{u}" 2>>"$LOG"
  fi
  # 공개 커밋에 개인 메일이 남지 않게: 공개 레포에는 GitHub noreply 주소로만 커밋한다
  if [[ "$(git -C "$OUT" config user.email)" != *@users.noreply.github.com ]]; then
    log "공개 레포 user.email 이 GitHub noreply 주소가 아니라 export 를 건너뜀 (CLAUDE.md 셋업 3단계 참고)"
  elif python3 "$BIN/export.py" $([ $REVIEW = 0 ] && echo --no-review) >> "$LOG" 2>&1; then
    commit_push "$OUT" "export: $(git -C "$SRC" rev-parse --short HEAD) ($HOST $(date '+%F %H:%M'))" \
      && commit_push "$SRC" "export cache: $HOST $(date '+%F %H:%M')"   # state/export.json 갱신분
  else
    log "export 실패 — 공개 레포는 이전 상태 유지"
    git -C "$OUT" reset -q --hard HEAD 2>/dev/null; git -C "$OUT" clean -fdq 2>/dev/null
  fi
fi

touch "$STAMP"
log "sync 끝"
