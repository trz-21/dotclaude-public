#!/bin/bash
# 공개되면 안 되는 내용이 있는지 검사한다. 하나라도 걸리면 exit 1.
#
#   leak-check.sh PATH ...    주어진 파일·디렉토리 검사
#   leak-check.sh --staged    공개 레포의 커밋 대상 검사 (.githooks/pre-commit 에서 호출)
#   leak-check.sh --paths-from DIR PUBLIC_PREFIX   DIR 을 PUBLIC_PREFIX 경로로 공개한다고 보고 검사
# 파일 내용뿐 아니라 (공개될) 파일 경로도 검사한다
#
# 검사 항목
#   - 비밀 값 패턴 (Slack·GitHub·AWS·Google·Anthropic·OpenAI 토큰, 개인 키)
#   - 이메일 주소 (noreply@anthropic.com, example.* 제외)
#   - 실제 사용자 홈 경로 (/Users/<이름>, /home/<이름>)와 홈 아래 개인 폴더(Desktop·Documents 등)로 시작하는 로컬 위치
#   - 원본 레포의 blocklist.txt 에 적힌 문자열 (대소문자 무시). 회사명·프로젝트 ID 등 목록 자체가 민감해서 비공개 쪽에 둔다
BLOCK="$HOME/.claude/dotclaude/source/blocklist.txt"

PATTERNS='xox[abposr]-[0-9A-Za-z-]{10,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9]{32,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
EMAIL_OK='noreply@anthropic\.com|@example\.(com|org)|@users\.noreply\.github\.com'
# 실제 홈(기기마다 다를 수 있음)과 일반적인 사용자 홈 형태 둘 다 (문서 속 /Users/<이름> 같은 설명은 통과)
HOMEPATH="$(printf %s "$HOME" | sed 's/[][\.*^$/]/\\&/g')|(/Users|/home)/[A-Za-z0-9._-]+"
LOCALPATH='(~|\$HOME|\$\{HOME\})/(Desktop|Documents|Downloads|Dropbox|OneDrive|iCloud)\b'

files=(); names=()
if [ "${1:-}" = --staged ]; then
  while IFS= read -r -d '' f; do [ -f "$f" ] && files+=("$f"); names+=("$f"); done < <(git diff --cached --name-only --diff-filter=ACMR -z)
elif [ "${1:-}" = --paths-from ]; then
  base="$2"; prefix="$3"
  while IFS= read -r -d '' f; do files+=("$f"); names+=("$prefix${f#"$base"}"); done < <(find "$base" -type f -print0)
  names+=("$prefix")
else
  for p in "$@"; do
    if [ -d "$p" ]; then while IFS= read -r -d '' f; do files+=("$f"); names+=("$f"); done < <(find "$p" -type f -not -path '*/.git/*' -print0)
    else files+=("$p"); names+=("$p"); fi
  done
fi
[ ${#files[@]} -eq 0 ] && [ ${#names[@]} -eq 0 ] && exit 0

hits=$(
  grep -nIE "$PATTERNS" "${files[@]}" /dev/null | sed 's/^/[비밀 값] /'
  grep -noIE "$EMAIL" "${files[@]}" /dev/null | grep -vE "$EMAIL_OK" | sed 's/^/[이메일] /'
  grep -nIE "$HOMEPATH" "${files[@]}" /dev/null | sed 's/^/[홈 경로] /'
  grep -nIE "$LOCALPATH" "${files[@]}" /dev/null | sed 's/^/[로컬 위치] /'
  if [ -f "$BLOCK" ]; then
    grep -v -e '^#' -e '^[[:space:]]*$' "$BLOCK" > "${TMPDIR:-/tmp}/dotclaude-block.$$"
    grep -noIiFf "${TMPDIR:-/tmp}/dotclaude-block.$$" "${files[@]}" /dev/null | sed 's/^/[차단 목록] /'
    printf '%s\n' "${names[@]}" | python3 -c 'import sys,unicodedata; print(unicodedata.normalize("NFC", sys.stdin.read()), end="")' \
      | grep -iFf "${TMPDIR:-/tmp}/dotclaude-block.$$" | sed 's/^/[차단 목록·경로] /'
    rm -f "${TMPDIR:-/tmp}/dotclaude-block.$$"
  fi
  printf '%s\n' "${names[@]}" | grep -E "$HOMEPATH" | sed 's/^/[홈 경로·경로] /'
)
if [ -n "$hits" ]; then
  echo "leak-check: 공개하면 안 되는 내용이 있어요" >&2
  echo "$hits" | sed -E 's/(xox[a-z]-|gh[a-z]_|sk-|AKIA|AIza)[A-Za-z0-9_-]{4,}/\1…/g' | head -50 >&2
  exit 1
fi
exit 0
