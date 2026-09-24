#!/bin/bash
# 홈 아래의 프로젝트별 .claude 를 찾아 <비공개 레포>/projects/<홈 기준 경로>/ 로 복사한다 (프로젝트 → 레포 한 방향).
#   mirror-projects.sh PRIVATE_REPO
#
# 건너뛰는 것
#   - 시스템·도구 폴더 (Library, 휴지통, node_modules, 에디터 확장, 플러그인, ~/.claude 자체 등)
#   - <비공개 레포>/mirror-ignore.txt 에 적힌 경로(홈 기준, 접두어 일치) — 남의 설정, 아카이브한 프로젝트 등
#   - 권한 기록(settings.local.json)·잠금·로그뿐인 .claude
PRI="$1"; [ -d "$PRI" ] || { echo "사용법: $0 PRIVATE_REPO" >&2; exit 1; }
IGN="$PRI/mirror-ignore.txt"
EXCL=(--exclude settings.local.json --exclude '*.lock' --exclude '*.log' --exclude .DS_Store --exclude worktrees/ --exclude '.plan-exists' --exclude .mirror-source)

# macOS 는 한글 경로를 NFD 로 돌려줄 때가 있어 비교·저장 전에 NFC 로 맞춘다
nfc() { python3 -c 'import sys,unicodedata; print(unicodedata.normalize("NFC", sys.argv[1]))' "$1"; }

ignored() {
  [ -f "$IGN" ] || return 1
  local line
  while IFS= read -r line; do
    [ -z "$line" ] || [ "${line:0:1}" = "#" ] && continue
    line="$(nfc "$line")"
    [[ "$1" == "$line" || "$1" == "$line"/* ]] && return 0
  done < "$IGN"
  return 1
}

find "$HOME" -maxdepth 8 \
  \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -path "$HOME/.claude" -o -path "$HOME/.local" \
     -o -path "$HOME/.cache" -o -path "$HOME/.npm" -o -path "$HOME/.vscode" -o -path "$HOME/.cursor" \
     -o -name node_modules -o -name .git -o -name .worktrees -o -path "$PRI" -o -name 'dotclaude-*' \) -prune \
  -o -type d -name .claude -print 2>/dev/null |
while IFS= read -r d; do
  rel="${d#"$HOME"/}"; rel="$(nfc "${rel%/.claude}")"
  [ "$d" = "$HOME/.claude" ] && continue
  ignored "$rel" && continue
  # 의미 있는 파일이 하나라도 있는지
  [ -n "$(find "$d" -type f ! -name settings.local.json ! -name '*.lock' ! -name '*.log' ! -name .DS_Store \
          ! -name .plan-exists ! -path '*/worktrees/*' -print -quit)" ] || continue
  mkdir -p "$PRI/projects/$rel"
  rsync -a --delete "${EXCL[@]}" "$d/" "$PRI/projects/$rel/"
  # 미러 표시 (아카이브 검토가 프로젝트 단위를 알아보는 데 쓴다)
  [ -f "$PRI/projects/$rel/.mirror-source" ] || echo "~/$rel/.claude" > "$PRI/projects/$rel/.mirror-source"
done
