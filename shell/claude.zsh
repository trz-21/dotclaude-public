# Claude Code 관련 쉘 함수. ~/.zshrc 에서 source 한다 (install.sh 가 연결).

# ccd: 최근 30일 Claude Code 사용 빈도순으로 폴더를 골라 실행
#   ccd          목록에서 선택
#   ccd 키워드    검색어로 바로 선택 (하나만 맞으면 즉시 실행)
#   ccd -c       선택 후 그 폴더의 마지막 대화 이어서 (-c/-r 등 옵션은 claude에 전달)
#   ~/.claude-dirs 에 적은 폴더는 기록이 없어도 목록 아래쪽에 항상 표시
ccd() {
  local opts=() query=() a
  for a in "$@"; do [[ $a == -* ]] && opts+=("$a") || query+=("$a"); done
  local sel
  sel=$(
    {
      find ~/.claude/projects -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime -30 -print0 \
        | xargs -0 grep -m1 -ho '"cwd":"[^"]*"' \
        | sed 's/^"cwd":"//; s/"$//' \
        | grep -v -e '^/private/' -e '/\.claude/' -e '/Library/' \
        | sort | uniq -c | sort -rn
      [[ -f ~/.claude-dirs ]] && grep -v -e '^\s*#' -e '^\s*$' ~/.claude-dirs \
        | sed "s#^~#$HOME#; s/^/      0 /"
    } | awk '{n=$1; sub(/^ *[0-9]+ /,""); if (!seen[$0]++) print n "\t" $0}' \
      | while IFS=$'\t' read -r n d; do
          [[ -d $d ]] && printf '%4s\t%s\n' "$([[ $n == 0 ]] && echo - || echo $n)" "${d/#$HOME/~}"
        done \
      | fzf --height=40% --reverse --prompt='claude > ' --header='최근 30일 세션 수' \
            --delimiter=$'\t' --nth=2 --query="${query[*]}" --select-1 --exit-0
  ) || return
  local dir="${sel#*$'\t'}"
  dir="${dir/#\~/$HOME}"
  cd "$dir" && claude --dangerously-skip-permissions "${opts[@]}"
}

# ccr: 모든 폴더의 지난 세션을 최근순으로 골라 이어가기 (그 폴더로 이동 후 --resume)
#   ccr            전체 세션 목록 (제목·폴더로 검색, 오른쪽에 입력했던 내용 미리보기)
#   ccr 키워드      검색어를 채운 채로 목록 열기
#   ccr -g 키워드   대화 본문 전체에서 키워드가 들어간 세션만 보기
ccr() {
  local py=~/.claude/dotclaude/source/shell/ccr_sessions.py src=() query=""
  if [[ $1 == -g ]]; then shift; src=(--grep "$*"); else query="$*"; fi
  local sel
  sel=$(python3 -I $py "${src[@]}" \
    | fzf --height=80% --reverse --prompt='resume > ' \
          --header='날짜 · 폴더 · 제목' \
          --delimiter=$'\t' --with-nth=1,2,3 --nth=2,3 --query="$query" \
          --preview="python3 -I $py --preview {4}" --preview-window=right,45%,wrap) || return
  local sid=$(cut -f4 <<< "$sel") dir=$(cut -f5 <<< "$sel")
  cd "$dir" && claude --dangerously-skip-permissions --resume "$sid"
}
