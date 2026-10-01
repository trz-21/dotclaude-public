#!/bin/bash
# 세션이 닫히거나 압축될 때(SessionEnd: clear/exit/…, PreCompact) 도는 훅.
# 훅은 transcript 를 대기열에 넣기만 하고, 마지막 일괄 실행 후 24시간이 지났을 때만 분리된 워커를 띄운다.
# 워커는 대기열의 세션들을 모아 스킬마다 claude 를 한 번씩만 띄운다 (실행마다 드는 고정비를 줄이려고):
#   1) archive-me      — 사용자 정보 아카이빙
#   2) improve-skills  — 세션에서 쓴 스킬 + 훅으로 돈 스킬 실행 기록을 검토해 스킬 보완
#
#   session-close.sh                 훅 진입점 (stdin으로 훅 JSON)
#   session-close.sh --flush         대기열을 지금 바로 처리
#   session-close.sh --run T [T...]  transcript T 들을 지금 바로 처리 (대기열과 무관, 실패하면 대기열에 넣는다)

HOOKS="$HOME/.claude/hooks"
RUNS="$HOOKS/runs"
STATE="$HOOKS/state"
QUEUE="$STATE/queue.txt"
LAST_BATCH="$STATE/last-batch"   # 마지막 일괄 실행 시각 (epoch 초)
LOG="$HOOKS/hook.log"
LOCK="$HOOKS/.lock"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
ME="$HOME/.claude/me"
AM="$HOME/.claude/skills/archive-me/scripts"
IS="$HOME/.claude/skills/improve-skills/scripts"
HISTORY="$HOME/.claude/skills/.history"

ARCHIVE_MODEL=sonnet
IMPROVE_MODEL=opus
BATCH_INTERVAL=86400  # 일괄 실행 간격 (초)
CLEAN_RUNS_KEEP=3     # 문제 없는 실행 기록은 스킬별로 최근 N개만 검토 대기로 둔다
ARCHIVE_MIN_BYTES=2048  # 추출본이 이보다 작거나 사용자 발화가 1개 이하면 archive-me 에 넣지 않는다 (거의 늘 변경 없음)
RUNS_KEEP=20 RUNS_KEEP_DAYS=14  # 검토 끝난 실행 기록 보존: 스킬별 최신 N개 + N일

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# 실패는 바로 알 수 있게 macOS 알림으로 (스킬 수정 같은 나머지는 세션 시작 때 hook-digest.py 가 알린다)
notify_fail() {
  local reason
  reason=$(jq -r 'select(.type=="result") | .result // .subtype // empty' "$2/stream.jsonl" 2>/dev/null | tail -1 | cut -c1-80)
  # 모델 출력이 AppleScript 코드로 해석되지 않게 문자열은 인자로 넘긴다
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title (item 2 of argv)' -e 'end run' \
    "${reason:-원인은 /hook-review 에서 확인}" "Claude 훅: $1 실패" >/dev/null 2>&1
}

# 대기열에 없을 때만 추가 (한 줄 append 는 원자적이라 워커와 겹쳐도 안전하다)
enqueue() { mkdir -p "$STATE"; grep -qxF "$1" "$QUEUE" 2>/dev/null || echo "$1" >> "$QUEUE"; }

# ---------------------------------------------------------------- 훅 진입점
if [ "$1" != "--run" ] && [ "$1" != "--flush" ]; then
  # 워커가 띄운 claude 세션이 끝날 때 다시 훅이 돌지 않게
  [ -n "$CLAUDE_HOOK_CHILD" ] && exit 0
  input=$(cat)
  event=$(jq -r '.hook_event_name // empty' <<<"$input")
  reason=$(jq -r '.reason // .trigger // empty' <<<"$input")
  transcript=$(jq -r '.transcript_path // empty' <<<"$input")
  mkdir -p "$HOOKS"
  [ -f "$transcript" ] || { log "skip $event: transcript 없음 ($transcript)"; exit 0; }
  enqueue "$transcript"
  last=$(cat "$LAST_BATCH" 2>/dev/null); now=$(date +%s)
  if [ -n "$last" ] && [ $((now - last)) -lt $BATCH_INTERVAL ]; then
    left=$((BATCH_INTERVAL - now + last))
    log "queue $event($reason) $(basename "$transcript") (대기 $(sort -u "$QUEUE" | grep -c .)개, 일괄 실행까지 $((left / 3600))h$((left % 3600 / 60))m)"
    exit 0
  fi
  # 워커가 뜨기 전에 다른 세션이 또 워커를 띄우지 않게 시각부터 기록한다
  echo "$now" > "$LAST_BATCH"
  log "trigger $event($reason) $(basename "$transcript") → 일괄 실행"
  # 세션 종료 시 Claude가 훅 프로세스 그룹을 정리해도 살아남도록 새 세션으로 분리
  nohup python3 -c 'import os,sys; os.setsid(); os.execv(sys.argv[1], sys.argv[1:])' \
    "$0" --flush "batch:$event($reason)" >> "$LOG" 2>&1 < /dev/null &
  exit 0
fi

# ---------------------------------------------------------------- 워커
mode=$1; shift
bid=$(date +%m%d%H%M)   # 일괄 실행 ID: 로그의 [xxxxxxxx] 자리 (hook-digest.py 가 8자로 파싱)
mkdir -p "$RUNS" "$STATE" "$HISTORY"

# 같은 시각에 워커가 겹치면 순서대로 (최대 20분 대기)
# SIGKILL·재부팅이면 trap 이 안 돌아 잠금이 남으므로, 잠금에 PID 를 남기고 그 프로세스가 죽었으면 회수한다
# (PID 없는 옛 잠금은 3시간 지나면 죽은 것으로 본다)
got=
for _ in $(seq 1200); do
  mkdir "$LOCK" 2>/dev/null && { got=1; break; }
  pid=$(cat "$LOCK/pid" 2>/dev/null)
  if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || { [ -z "$pid" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +180 2>/dev/null)" ]; }; then
    log "[$bid] 죽은 잠금 회수 (pid ${pid:-없음})"; rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; continue
  fi
  sleep 1
done
# 잠금 디렉토리는 남이 잡고 있어도 있으므로, 직접 만들었는지로 판단한다
[ -n "$got" ] || { log "[$bid] lock 획득 실패"; notify_fail "session-close 잠금" ""; exit 1; }
echo $$ > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK"' EXIT

# 처리할 transcript 목록. --flush 는 대기열을 rename 해서 가져간다 (그 뒤 진입점이 쓰는 건 새 대기열로 간다).
# 잠금을 쥔 뒤라 남아 있는 queue.txt.<pid> 는 중간에 죽은 워커 몫이니 같이 가져간다.
items=() taken=()
if [ "$mode" = "--flush" ]; then
  trigger=${1:-flush}
  [ -f "$QUEUE" ] && mv "$QUEUE" "$QUEUE.$$"
  for f in "$QUEUE".*; do [ -f "$f" ] && taken+=("$f"); done
  while read -r t; do [ -n "$t" ] && items+=("$t"); done < <(cat "${taken[@]}" /dev/null | awk '!seen[$0]++')
  date +%s > "$LAST_BATCH"
else
  trigger=manual
  for a in "$@"; do
    case $a in *.jsonl) items+=("$a") ;; *) trigger=$a ;; esac  # 옛 안내의 `--run T manual` 도 받는다
  done
fi

ts=() sids=() failed=()
for t in "${items[@]}"; do
  if [ -f "$t" ]; then ts+=("$t"); sids+=("$(basename "$t" .jsonl)")
  else log "[$bid] transcript 없음, 대기열에서 뺌: $t"; fi
done
log "[$bid] 일괄 실행 시작 ($mode, $trigger): 세션 ${#ts[@]}개"

HOOK_SYS='이 세션은 훅이 띄운 무인 실행이다. 사용자에게 질문할 수 없고 Bash도 없다. 스킬의 hook 모드 지시를 따른다.
응답의 마지막 줄은 반드시 `ISSUES: none` 또는 `ISSUES: <스킬 지시를 따르기 어려웠던 점, 막힌 도구, 애매했던 지시>` 한 줄로 끝낸다.'

# 무인 실행 공통 인자 (모델만 스킬마다 다르다)
CLAUDE_FLAGS=(
  --no-session-persistence
  --exclude-dynamic-system-prompt-sections   # cwd 등을 첫 메시지로 옮겨 실행 사이 캐시 재사용을 늘린다
  # (--disable-slash-commands 는 고정비 -19% 지만 스킬 본문을 직접 조립해야 해서 보류, --setting-sources 는 사용자 스킬·CLAUDE.md 가 빠져 못 씀)
  --strict-mcp-config
  --permission-mode bypassPermissions
  --tools Read Write Edit Glob Grep Skill
  --append-system-prompt "$HOOK_SYS"
  --output-format stream-json --verbose
)

# run_headless <skill> <skill_dir> <model> <run_dir> <prompt> <transcript...>
# 스킬을 무인 실행하고 전체 스트림과 메타 정보를 run_dir에 남긴다. 반환값은 claude 종료 코드.
run_headless() {
  local skill=$1 skill_dir=$2 model=$3 run=$4 prompt=$5 rc t ss=(); shift 5
  : > "$run/transcripts.txt"  # hook-digest.py 가 재실행 명령을 만들 때 쓴다
  for t in "$@"; do echo "$t" >> "$run/transcripts.txt"; ss+=("$(basename "$t" .jsonl)"); done
  (cd "$run" && CLAUDE_HOOK_CHILD=1 "$CLAUDE_BIN" -p "$prompt" --model "$model" "${CLAUDE_FLAGS[@]}" \
    < /dev/null > stream.jsonl 2> stderr.txt)
  rc=$?
  jq -n --arg skill "$skill" --arg dir "$skill_dir" --arg model "$model" --arg trig "$trigger" \
        --arg src "$bid" --argjson rc "$rc" --arg at "$(date '+%F %T')" \
        --argjson cost "$(jq -s '[.[] | select(.type=="result") | .total_cost_usd // 0] | last // 0' "$run/stream.jsonl" 2>/dev/null || echo 0)" \
        --argjson sessions "$(printf '%s\n' "${ss[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
    '{skill:$skill, skill_dir:$dir, model:$model, trigger:$trig, source_session:$src, sessions:$sessions, rc:$rc, cost_usd:$cost, finished_at:$at}' \
    > "$run/meta.json"
  return $rc
}

new_run_dir() { local d="$RUNS/$1/$(date +%Y%m%d-%H%M%S)-$bid"; mkdir -p "$d"; echo "$d"; }
fail_add() { [[ " ${failed[*]} " == *" $1 "* ]] || failed+=("$1"); }

# ---------------------------------------------------------------- 1) archive-me
archive_me() {
  local tmp run t i n users bytes inc=() inc_n=()
  run=$(new_run_dir archive-me)
  for i in "${!ts[@]}"; do
    t=${ts[$i]}
    # 추출한 줄까지만 mark 하려고 줄 수를 먼저 고정한다 (그 사이 세션이 재개돼 늘어난 부분은 다음 차례로)
    n=$(wc -l < "$t" | tr -d ' ')
    tmp=$(mktemp)
    python3 "$AM/extract_transcript.py" "$t" --upto "$n" > "$tmp"
    users=$(grep -c '^\[USER\]' "$tmp"); bytes=$(wc -c < "$tmp" | tr -d ' ')
    if [ "$users" -eq 0 ]; then
      python3 "$AM/extract_transcript.py" "$t" --upto "$n" --mark > /dev/null; log "[${sids[$i]:0:8}] archive-me: 새 사용자 발화 없음"
    elif [ "$users" -le 1 ] || [ "$bytes" -lt $ARCHIVE_MIN_BYTES ]; then
      python3 "$AM/extract_transcript.py" "$t" --upto "$n" --mark > /dev/null
      log "[${sids[$i]:0:8}] archive-me: 건너뜀 (사용자 발화 ${users}개, ${bytes}B)"
    else
      { echo "===== 세션 ${sids[$i]} (_log.md 에는 hook:${sids[$i]:0:8}) ====="; echo; cat "$tmp"; } >> "$run/input.txt"
      inc+=("$t"); inc_n+=("$n")
    fi
    rm -f "$tmp"
  done
  if [ ${#inc[@]} -eq 0 ]; then rm -rf "$run"; log "[$bid] archive-me: 넣을 세션 없음"; return; fi

  log "[$bid] archive-me 실행 → $run (세션 ${#inc[@]}개)"
  if run_headless archive-me "$HOME/.claude/skills/archive-me" "$ARCHIVE_MODEL" "$run" "/archive-me --hook $run/input.txt" "${inc[@]}"; then
    python3 "$AM/build_index.py" > /dev/null
    for i in "${!inc[@]}"; do python3 "$AM/extract_transcript.py" "${inc[$i]}" --upto "${inc_n[$i]}" --mark > /dev/null; done
    log "[$bid] archive-me 완료"
  else
    # mark 안 함 → 대기열에 남겨 다음 일괄 실행 때 재시도
    log "[$bid] archive-me 실패 (exit $?)"
    for t in "${inc[@]}"; do fail_add "$t"; done
    notify_fail archive-me "$run"
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
  local review=() issue_runs=() clean_runs=() r run dirs=() d snap snaps=() t i n k sid8 inc=() inc_n=() sessions=""
  local is_state="$STATE/improve-skills.json"

  # 스킬을 쓰고 그 뒤에 사용자 발화가 있는 세션만 A 로 (교정 신호가 없으면 검토할 거리가 없다)
  for i in "${!ts[@]}"; do
    t=${ts[$i]}; sid8=${sids[$i]:0:8}
    n=$(wc -l < "$t" | tr -d ' ')
    if python3 "$IS/extract_skill_session.py" "$t" --state "$is_state" --upto "$n" --check; then
      sessions+=$'\n'"# A-$((${#inc[@]} + 1)). 원 세션 (${sids[$i]})"$'\n'
      sessions+=$(python3 "$IS/extract_skill_session.py" "$t" --state "$is_state" --upto "$n")$'\n'
      inc+=("$t"); inc_n+=("$n")
    else
      python3 "$IS/extract_skill_session.py" "$t" --state "$is_state" --upto "$n" --mark
      log "[$sid8] improve-skills: 건너뜀 (스킬 사용 없음 또는 스킬 사용 뒤 사용자 발화 없음)"
    fi
  done

  # 검토 대기 중인 훅 실행 기록: 문제 있는 것 전부 + 문제 없는 것은 스킬별 최근 N개
  # 로그인·네트워크 같은 환경 실패(exit 2)는 스킬 문제가 아니라 검토하지 않는다 (실패 알림은 hook-digest 가 한다)
  for skill_runs in "$RUNS"/*/; do
    k=0
    for r in $(ls -1d "$skill_runs"*/ 2>/dev/null | sort -r); do
      r=${r%/}
      [ -f "$r/reviewed" ] || [ ! -f "$r/meta.json" ] && continue
      python3 "$IS/digest_run.py" "$r" --check
      case $? in
        1) issue_runs+=("$r") ;;
        2) touch "$r/reviewed" ;;
        *) if [ $((k++)) -lt $CLEAN_RUNS_KEEP ]; then clean_runs+=("$r"); else touch "$r/reviewed"; fi ;;
      esac
    done
  done

  # 검토할 세션도 문제 있는 훅 실행도 없으면 claude를 띄우지 않는다
  if [ ${#inc[@]} -eq 0 ] && [ ${#issue_runs[@]} -eq 0 ]; then
    log "[$bid] improve-skills: 검토할 것 없음 (문제 없는 훅 실행 ${#clean_runs[@]}건은 다음 기회에)"
    return
  fi
  review=("${issue_runs[@]}" "${clean_runs[@]}")

  # 수정 대상이 될 수 있는 스킬 디렉토리 목록
  while read -r d; do [ -n "$d" ] && dirs+=("$d"); done < <( {
    grep -E '^- [^ ]+ ×[0-9]+ — /[^ ]+$' <<<"$sessions" | sed 's/^.* — //'
    for r in "${review[@]}"; do jq -r '.skill_dir // empty' "$r/meta.json"; done
    echo "$HOME/.claude/skills/improve-skills"
  } | sort -u )

  run=$(new_run_dir improve-skills)
  {
    echo "# improve-skills hook 입력 ($(date '+%F %T'), trigger: $trigger)"
    echo
    echo "# A. 원 세션 ${#inc[@]}개 (세션마다 따로 판단한다)"
    [ ${#inc[@]} -eq 0 ] && echo "- (없음)"
    echo "$sessions"
    echo
    echo "# B. 훅으로 돈 스킬 실행 기록 (문제 있는 것 ${#issue_runs[@]}건, 문제 없는 것 ${#clean_runs[@]}건)"
    for r in "${review[@]}"; do echo; python3 "$IS/digest_run.py" "$r"; done
    echo
    echo "# C. 스킬 위치별 수정 가능 여부 (워커 판정)"
    for d in "${dirs[@]}"; do classify "$d"; done
  } > "$run/input.md"

  # 직접 수정 가능한 스킬을 미리 스냅샷 (모델이 아니라 워커가 백업을 보장)
  snap=$(date +%Y%m%d-%H%M%S)
  for d in "${dirs[@]}"; do
    editable "$d" || continue
    mkdir -p "$HISTORY/$(basename "$d")/$snap" && cp -R "$d/." "$HISTORY/$(basename "$d")/$snap/"
    snaps+=("$d")
  done

  log "[$bid] improve-skills 실행 → $run (세션: ${#inc[@]}, 훅 실행 검토: ${#review[@]})"
  if run_headless improve-skills "$HOME/.claude/skills/improve-skills" "$IMPROVE_MODEL" "$run" "/improve-skills --hook $run/input.md" "${inc[@]}"; then
    for i in "${!inc[@]}"; do python3 "$IS/extract_skill_session.py" "${inc[$i]}" --state "$is_state" --upto "${inc_n[$i]}" --mark; done
    for r in "${review[@]}"; do touch "$r/reviewed"; done
    log "[$bid] improve-skills 완료"
  else
    log "[$bid] improve-skills 실패 (exit $?)"
    for t in "${inc[@]}"; do fail_add "$t"; done
    notify_fail improve-skills "$run"
  fi

  # 바뀐 게 없는 스냅샷은 지우고, 바뀐 스킬은 수정 직후 상태도 <snap>-after 로 남긴다
  # (hook-digest.py 가 이후 수동 수정과 섞이지 않게 훅이 바꾼 부분만 diff 로 보여 주려고)
  for d in "${snaps[@]}"; do
    local b="$HISTORY/$(basename "$d")/$snap"
    if diff -rq "$b" "$d" > /dev/null; then rm -rf "$b"
    else
      mkdir -p "$b-after" && cp -R "$d/." "$b-after/"
      log "[$bid] 스킬 수정됨: $(basename "$d") (백업 $b) 위치 $d"
    fi
    rmdir "$HISTORY/$(basename "$d")" 2>/dev/null
  done
}

# ---------------------------------------------------------------- 3) 실행 기록 정리
# 검토 끝난(reviewed) 기록 중 스킬별 최신 N개 밖이고 N일 지난 것만 지운다.
# 검토 대기와, hook-digest 가 아직 알려야 하는(마지막 확인 이후) 실패 기록은 남긴다.
prune_runs() {
  local cutoff seen r i name deleted=0
  cutoff=$(date -v-${RUNS_KEEP_DAYS}d +%Y%m%d 2>/dev/null || date -d "$RUNS_KEEP_DAYS days ago" +%Y%m%d)
  seen=$(jq -r '.seen_at // empty' "$STATE/hook-review.json" 2>/dev/null)
  for skill_runs in "$RUNS"/*/; do
    i=0
    for r in $(ls -1d "$skill_runs"*/ 2>/dev/null | sort -r); do
      r=${r%/}; name=$(basename "$r")
      [ $((i++)) -lt $RUNS_KEEP ] && continue
      [ -f "$r/reviewed" ] && [[ "${name:0:8}" < "$cutoff" ]] || continue
      [ "$(jq -r '.rc' "$r/meta.json" 2>/dev/null)" != 0 ] && [[ "$(jq -r '.finished_at' "$r/meta.json" 2>/dev/null)" > "$seen" ]] && continue
      rm -rf "$r"; deleted=$((deleted + 1))
    done
  done
  [ $deleted -gt 0 ] && log "[$bid] 실행 기록 정리: ${deleted}개 삭제"
}

archive_me
improve_skills
prune_runs

# 실패한 세션은 mark 하지 않았으니 다시 대기열로 (mark 위치 이후만 다시 보므로 중복 처리되지 않는다)
for t in "${failed[@]}"; do enqueue "$t"; done
# 진입점이 rename 직전에 연 파일에 쓴 줄은 가져간 파일 쪽에 들어가 있을 수 있으니, 지우기 전에 처리 안 한 줄을 돌려놓는다
for f in "${taken[@]}"; do
  while read -r t; do [ -n "$t" ] && ! printf '%s\n' "${items[@]}" | grep -qxF "$t" && enqueue "$t"; done < "$f"
done
[ ${#taken[@]} -gt 0 ] && rm -f "${taken[@]}"
log "[$bid] 일괄 실행 끝: 세션 ${#ts[@]}개, 실패로 대기열에 남김 ${#failed[@]}개"
exit 0
