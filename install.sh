#!/bin/bash
# dotclaude 원본 레포를 ~/.claude 에 심볼릭 링크로 연결한다.
#
#   install.sh [--dry-run] [REPO]      설치. 기존 파일·디렉토리는 ~/.claude/backups/dotclaude-<시각>/ 로 옮긴다
#   install.sh --repair [REPO]         훅용. 빠진 링크를 만들고, 일반 파일로 바뀐 링크는 내용을 레포로 가져와 되살린다.
#                                      실제 디렉토리가 자리를 차지하고 있으면 건드리지 않는다
#   install.sh --export PUBLIC_REPO    공개 레포(export 결과가 들어갈 곳)를 등록만 한다
#
# REPO 를 생략하면 등록된 원본(~/.claude/dotclaude/source), 없으면 이 스크립트가 있는 레포를 쓴다.
# 레포 역할은 .dotclaude-role 로 구분한다: source(원본, 링크 대상) / export(공개 사본, 링크하지 않음)
#
# 링크 규칙 (원본 레포 → ~/.claude)
#   skills/<이름>, agents/<이름>, commands/<이름>, hooks/<파일>  → 같은 이름
#   memory/HOME<나머지>   → projects/<인코딩된 $HOME><나머지>/memory
#   links.tsv             → "레포 경로<TAB>링크될 위치" 로 적은 그 외 항목
# 레포에서 사라진 항목(아카이브 등)을 가리키던 링크는 지운다.
#
# 공개 사본(.dotclaude-role = export)에 들어 있는 이 파일은 참고용이다. 거기서 실행하면 안내만 하고 아무것도 바꾸지 않는다.

C="$HOME/.claude"
REG="$C/dotclaude"
SELF="$(cd "$(dirname "$0")" && pwd -P)"
# Claude Code 는 경로의 영숫자 아닌 글자를 한 글자당 '-' 하나로 바꾼다 (한글 포함). 로케일에 흔들리지 않게 python 으로
HOMEENC="$(python3 -c 'import os,re; print(re.sub(r"[^A-Za-z0-9]", "-", os.environ["HOME"]))')"
BACKUP="$C/backups/dotclaude-$(date +%Y%m%d-%H%M%S)"

# 공개 사본에서는 실행하지 않는다 (등록된 원본 레포를 대신 건드리지 않도록 인자와 상관없이 먼저 멈춘다)
if [ "$(cat "$SELF/.dotclaude-role" 2>/dev/null)" = export ]; then
  cat >&2 <<'MSG'
이 레포는 비공개 원본에서 자동으로 만들어진 공개 사본이라 install.sh 는 참고용이에요. 아무것도 바꾸지 않았어요.
직접 쓰려면 이 레포를 복사해 자기 원본 레포로 만들고(.dotclaude-role 을 source 로 바꾸고 🔒 폴더는 비우기),
그 레포의 install.sh 를 실행하세요. 자세한 절차는 CLAUDE.md 의 "새 기기 셋업"에 있어요.
MSG
  exit 0
fi

MODE=install
case "${1:-}" in
  --dry-run) MODE=dry; shift ;;
  --repair) MODE=repair; shift ;;
  --export)
    [ -d "${2:-}" ] || { echo "사용법: $0 --export PUBLIC_REPO" >&2; exit 1; }
    out="$(cd "$2" && pwd -P)"
    [ "$(cat "$out/.dotclaude-role" 2>/dev/null)" = export ] || [ -z "$(ls -A "$out" | grep -v '^\.git$')" ] \
      || { echo "공개 레포가 아니에요 (.dotclaude-role 이 export 가 아니고 비어 있지도 않음): $out" >&2; exit 1; }
    [ -e "$REG/export" ] && [ ! -L "$REG/export" ] && { echo "$REG/export 가 링크가 아닌 실제 파일이에요. 확인 후 지우세요" >&2; exit 1; }
    mkdir -p "$REG" && ln -sfn "$out" "$REG/export"
    echo "공개 레포 등록: $REG/export → $out"
    exit 0 ;;
esac

if [ $# -eq 0 ]; then
  if [ -d "$REG/source" ]; then set -- "$(cd "$REG/source" && pwd -P)"; else set -- "$SELF"; fi
fi

say() { if [ "$MODE" = repair ]; then echo "[dotclaude] $*" >&2; else echo "$*"; fi; }
run() { if [ "$MODE" = dry ]; then echo "  (dry) $*"; else "$@"; fi; }

backup() {
  local rel="${1#"$HOME"/}"
  run mkdir -p "$BACKUP/$(dirname "$rel")"
  run mv "$1" "$BACKUP/$rel"
}

# 레포의 "원본<TAB>링크 위치" 목록
entries() {
  local repo=$1 kind p n s d
  for kind in skills agents commands; do
    for p in "$repo/$kind"/*; do [ -e "$p" ] && printf '%s\t%s\n' "$p" "$C/$kind/$(basename "$p")"; done
  done
  for p in "$repo/hooks"/*; do [ -f "$p" ] && printf '%s\t%s\n' "$p" "$C/hooks/$(basename "$p")"; done
  for p in "$repo/memory"/HOME*; do
    [ -d "$p" ] || continue; n=$(basename "$p")
    printf '%s\t%s\n' "$p" "$C/projects/$HOMEENC${n#HOME}/memory"
  done
  [ -f "$repo/links.tsv" ] && while IFS=$'\t' read -r s d; do
    [ -z "$s" ] || [ "${s:0:1}" = "#" ] && continue
    printf '%s\t%s\n' "$repo/$s" "${d/#\~/$HOME}"
  done < "$repo/links.tsv"
}

link_one() {
  local src=$1 dst=$2
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && return

  if [ "$MODE" = repair ]; then
    if [ -L "$dst" ]; then
      rm "$dst"; ln -s "$src" "$dst"; say "링크 갱신: $dst"
    elif [ -f "$dst" ] && [ -f "$src" ]; then
      # Claude Code 등이 링크를 일반 파일로 덮어쓴 경우: 새 내용을 레포로 가져온다
      cmp -s "$dst" "$src" || { cp "$dst" "$src"; say "풀린 링크의 변경분을 레포로 가져옴: $src"; }
      rm "$dst"; ln -s "$src" "$dst"; say "링크 복구: $dst"
    elif [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; say "링크 생성: $dst"
    else
      say "경고: 링크 자리에 실제 파일·디렉토리가 있어 건너뜀 (레포 쪽과 비교해 정리 필요): $dst"
    fi
    return
  fi

  if [ -L "$dst" ]; then say "링크 갱신: $dst"; run rm "$dst"
  elif [ -e "$dst" ]; then say "백업 후 링크: $dst"; backup "$dst"
  else say "링크: $dst"; fi
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
}

repo="$(cd "$1" && pwd -P)" || exit 1
role="$(cat "$repo/.dotclaude-role" 2>/dev/null)"
[ "$role" = source ] || { echo "원본 레포가 아니에요 (.dotclaude-role: ${role:-없음}): $repo" >&2; exit 1; }

# 원본 레포 등록: 훅·스크립트는 ~/.claude/dotclaude/source 라는 고정 경로로 레포를 찾는다
if [ "$(readlink "$REG/source" 2>/dev/null)" != "$repo" ]; then
  say "원본 레포 등록: $REG/source → $repo"
  run mkdir -p "$REG"; run ln -sfn "$repo" "$REG/source"
fi
while IFS=$'\t' read -r src dst; do link_one "$src" "$dst"; done < <(entries "$repo")

# 레포에서 사라진 항목을 가리키던 링크 정리
for l in "$C"/skills/* "$C"/agents/* "$C"/commands/* "$C"/hooks/* "$C"/projects/*/memory; do
  [ -L "$l" ] || continue
  t="$(readlink "$l")"
  # 이 레포(또는 옮기기 전 dotclaude 레포)를 가리키다 끊긴 링크만
  if [[ "$t" == "$repo"/* || "$t" == *dotclaude* ]] && [ ! -e "$t" ]; then say "사라진 항목의 링크 제거: $l"; run rm "$l"; fi
done

[ "$MODE" = install ] && [ -d "$BACKUP" ] && echo "기존 파일 백업 위치: $BACKUP"
exit 0
