#!/bin/bash
# 세션이 닫히거나 압축될 때(SessionEnd: clear/exit/…, PreCompact) 도는 훅.
# 훅 자체는 즉시 끝나고, 분리된 백그라운드 워커가 순서대로 처리한다:
#   1) archive-me      — 사용자 정보 아카이빙
#   2) improve-skills  — 세션에서 쓴 스킬 + 훅으로 돈 스킬 실행 기록을 검토해 스킬 보완
#
#   session-close.sh          훅 진입점 (stdin으로 훅 JSON)
#   session-close.sh --run T  워커: transcript T 처리

HOOKS="$HOME/.claude/hooks"
RUNS="$HOOKS/runs"
STATE="$HOOKS/state"
LOG="$HOOKS/hook.log"
LOCK="$HOOKS/.lock"
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
ME="$HOME/.claude/me"
AM="$HOME/.claude/skills/archive-me/scripts"
IS="$HOME/.claude/skills/improve-skills/scripts"
HISTORY="$HOME/.claude/skills/.history"

ARCHIVE_MODEL=sonnet
IMPROVE_MODEL=opus
CLEAN_RUNS_KEEP=3   # 문제 없는 실행 기록은 스킬별로 최근 N개만 검토 대기로 둔다

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ---------------------------------------------------------------- 훅 진입점
if [ "$1" != "--run" ]; then
  # 워커가 띄운 claude 세션이 끝날 때 다시 훅이 돌지 않게
  [ -n "$CLAUDE_HOOK_CHILD" ] && exit 0
  input=$(cat)
  event=$(jq -r '.hook_event_name // empty' <<<"$input")
  reason=$(jq -r '.reason // .trigger // empty' <<<"$input")
  transcript=$(jq -r '.transcript_path // empty' <<<"$input")
  mkdir -p "$HOOKS"
  [ -f "$transcript" ] || { log "skip $event: transcript 없음 ($transcript)"; exit 0; }
  log "trigger $event($reason) $(basename "$transcript")"
  # 세션 종료 시 Claude가 훅 프로세스 그룹을 정리해도 살아남도록 새 세션으로 분리
  nohup python3 -c 'import os,sys; os.setsid(); os.execv(sys.argv[1], sys.argv[1:])' \
    "$0" --run "$transcript" "$event($reason)" >> "$LOG" 2>&1 < /dev/null &
  exit 0
fi

# ---------------------------------------------------------------- 워커
transcript="$2"
trigger="$3"
sid=$(basename "$transcript" .jsonl)
sid8=${sid:0:8}
mkdir -p "$RUNS" "$STATE" "$HISTORY"
[ -f "$transcript" ] || { log "[$sid8] transcript 없음"; exit 0; }

# 같은 세션이 compact → exit처럼 겹쳐 들어오면 순서대로 (최대 20분 대기)
for _ in $(seq 1200); do mkdir "$LOCK" 2>/dev/null && break; sleep 1; done
[ -d "$LOCK" ] || { log "[$sid8] lock 획득 실패"; exit 1; }
trap 'rmdir "$LOCK"' EXIT

HOOK_SYS='이 세션은 훅이 띄운 무인 실행이다. 사용자에게 질문할 수 없고 Bash도 없다. 스킬의 hook 모드 지시를 따른다.
응답의 마지막 줄은 반드시 `ISSUES: none` 또는 `ISSUES: <스킬 지시를 따르기 어려웠던 점, 막힌 도구, 애매했던 지시>` 한 줄로 끝낸다.'

# run_headless <skill> <skill_dir> <model> <run_dir> <prompt>
# 스킬을 무인 실행하고 전체 스트림과 메타 정보를 run_dir에 남긴다. 반환값은 claude 종료 코드.
run_headless() {
  local skill=$1 skill_dir=$2 model=$3 run=$4 prompt=$5 rc
  (cd "$run" && CLAUDE_HOOK_CHILD=1 "$CLAUDE_BIN" -p "$prompt" \
    --model "$model" \
    --no-session-persistence \
    --strict-mcp-config \
    --permission-mode bypassPermissions \
    --tools Read Write Edit Glob Grep Skill \
    --append-system-prompt "$HOOK_SYS" \
    --output-format stream-json --verbose \
    < /dev/null > stream.jsonl 2> stderr.txt)
  rc=$?
  jq -n --arg skill "$skill" --arg dir "$skill_dir" --arg model "$model" --arg trig "$trigger" \
        --arg src "$sid" --argjson rc "$rc" --arg at "$(date '+%F %T')" \
    '{skill:$skill, skill_dir:$dir, model:$model, trigger:$trig, source_session:$src, rc:$rc, finished_at:$at}' \
    > "$run/meta.json"
  return $rc
}

new_run_dir() { local d="$RUNS/$1/$(date +%Y%m%d-%H%M%S)-$sid8"; mkdir -p "$d"; echo "$d"; }

# ---------------------------------------------------------------- 1) archive-me
archive_me() {
  local tmp run
  tmp=$(mktemp)
  python3 "$AM/extract_transcript.py" "$transcript" > "$tmp"
  if ! grep -q '^\[USER\]' "$tmp"; then
    python3 "$AM/extract_transcript.py" "$transcript" --mark > /dev/null
    rm -f "$tmp"; log "[$sid8] archive-me: 새 사용자 발화 없음"
    return
  fi
  run=$(new_run_dir archive-me)
  mv "$tmp" "$run/input.txt"
  log "[$sid8] archive-me 실행 → $run"
  if run_headless archive-me "$HOME/.claude/skills/archive-me" "$ARCHIVE_MODEL" "$run" "/archive-me --hook $run/input.txt"; then
    python3 "$AM/build_index.py" > /dev/null
    python3 "$AM/extract_transcript.py" "$transcript" --mark > /dev/null
    log "[$sid8] archive-me 완료"
  else
    # mark 안 함 → 다음 트리거 때 재시도
    log "[$sid8] archive-me 실패 (exit $?)"
  fi
}

# ---------------------------------------------------------------- 2) improve-skills
# 수정 가능한 스킬 디렉토리인지 (플러그인·번들·synced는 업데이트 때 덮어써지므로 제외)
editable() { [ -f "$1/SKILL.md" ] && [[ "$1" != *"/.claude/plugins/"* && "$1" != *"/skills/synced/"* ]]; }

# 무인 세션엔 Bash가 없으니 수정 가능 여부를 워커가 미리 판정해 입력에 넣는다
classify() {
  local top
  if ! editable "$1"; then echo "- \`$1\` — 수정 불가 (플러그인·번들·synced)"
  elif top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ ! -f "$top/.dotclaude-role" ]; then echo "- \`$1\` — git 레포 안($top): 직접 수정하지 말고 PENDING.md로"
  else echo "- \`$1\` — 직접 수정 가능"; fi
}

improve_skills() {
  local session review=() issue_runs=() clean_runs=() r run dirs=() d ts snaps=()
  session=$(python3 "$IS/extract_skill_session.py" "$transcript" --state "$STATE/improve-skills.json")

  # 검토 대기 중인 훅 실행 기록: 문제 있는 것 전부 + 문제 없는 것은 스킬별 최근 N개
  for skill_runs in "$RUNS"/*/; do
    local n=0
    for r in $(ls -1d "$skill_runs"*/ 2>/dev/null | sort -r); do
      r=${r%/}
      [ -f "$r/reviewed" ] || [ ! -f "$r/meta.json" ] && continue
      if ! python3 "$IS/digest_run.py" "$r" --check; then issue_runs+=("$r")
      elif [ $((n++)) -lt $CLEAN_RUNS_KEEP ]; then clean_runs+=("$r")
      else touch "$r/reviewed"; fi
    done
  done

  # 세션에서 스킬을 안 썼고 문제 있는 훅 실행도 없으면 claude를 띄우지 않는다
  if grep -q '^- (없음)' <<<"$session" && [ ${#issue_runs[@]} -eq 0 ]; then
    python3 "$IS/extract_skill_session.py" "$transcript" --state "$STATE/improve-skills.json" --mark
    log "[$sid8] improve-skills: 검토할 것 없음 (문제 없는 훅 실행 ${#clean_runs[@]}건은 다음 기회에)"
    return
  fi
  review=("${issue_runs[@]}" "${clean_runs[@]}")

  # 수정 대상이 될 수 있는 스킬 디렉토리 목록
  while read -r d; do [ -n "$d" ] && dirs+=("$d"); done < <( {
    grep -oE '— /[^ ]+$' <<<"$session" | sed 's/^— //'
    for r in "${review[@]}"; do jq -r '.skill_dir // empty' "$r/meta.json"; done
    echo "$HOME/.claude/skills/improve-skills"
  } | sort -u )

  run=$(new_run_dir improve-skills)
  {
    echo "# improve-skills hook 입력 ($(date '+%F %T'), trigger: $trigger)"
    echo
    echo "# A. 원 세션 ($sid)"
    echo "$session"
    echo
    echo "# B. 훅으로 돈 스킬 실행 기록 (문제 있는 것 ${#issue_runs[@]}건, 문제 없는 것 ${#clean_runs[@]}건)"
    for r in "${review[@]}"; do echo; python3 "$IS/digest_run.py" "$r"; done
    echo
    echo "# C. 스킬 위치별 수정 가능 여부 (워커 판정)"
    for d in "${dirs[@]}"; do classify "$d"; done
  } > "$run/input.md"

  # 직접 수정 가능한 스킬을 미리 스냅샷 (모델이 아니라 워커가 백업을 보장)
  ts=$(date +%Y%m%d-%H%M%S)
  for d in "${dirs[@]}"; do
    editable "$d" || continue
    mkdir -p "$HISTORY/$(basename "$d")/$ts" && cp -R "$d/." "$HISTORY/$(basename "$d")/$ts/"
    snaps+=("$d")
  done

  log "[$sid8] improve-skills 실행 → $run (스킬 사용: $(grep -c '^- .* ×' <<<"$session"), 훅 실행 검토: ${#review[@]})"
  if run_headless improve-skills "$HOME/.claude/skills/improve-skills" "$IMPROVE_MODEL" "$run" "/improve-skills --hook $run/input.md"; then
    python3 "$IS/extract_skill_session.py" "$transcript" --state "$STATE/improve-skills.json" --mark
    for r in "${review[@]}"; do touch "$r/reviewed"; done
    log "[$sid8] improve-skills 완료"
  else
    log "[$sid8] improve-skills 실패 (exit $?)"
  fi

  # 바뀐 게 없는 스냅샷은 지운다
  for d in "${snaps[@]}"; do
    local b="$HISTORY/$(basename "$d")/$ts"
    if diff -rq "$b" "$d" > /dev/null; then rm -rf "$b"
    else log "[$sid8] 스킬 수정됨: $(basename "$d") (백업 $b)"; fi
    rmdir "$HISTORY/$(basename "$d")" 2>/dev/null
  done
}

archive_me
improve_skills
exit 0
