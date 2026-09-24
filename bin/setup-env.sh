#!/bin/bash
# 새 기기에서 비공개 레포 setup/ 기록대로 플러그인 마켓플레이스·플러그인·MCP 서버를 설치한다.
# 이미 있는 것은 건너뛴다. 비밀 값(<SET_ME>)이 필요한 MCP 서버와 OAuth 로그인은 마지막에 목록으로 알려 준다.
#
#   setup-env.sh [--dry-run]
#
# 기록 형식 (sync.sh 가 매번 갱신)
#   setup/plugins.json  {"marketplaces": {이름: source}, "plugins": [{"id": "플러그인@마켓", "scope": "user"}]}
#   setup/mcp.json      {"user": {이름: 설정}, "local": {"~/경로": {이름: 설정}}}
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
PRI="$HOME/.claude/dotclaude/source"
S="$PRI/setup"
[ -d "$S" ] || { echo "원본 레포가 등록되지 않았거나 setup/ 이 없어요: $S" >&2; exit 1; }
run() { if [ $DRY = 1 ]; then echo "  (dry) $*"; else "$@"; fi; }
has_word() { grep -qE "(^|[^A-Za-z0-9_.-])$(printf %s "$2" | sed 's/[][\.*^$+?(){}|/]/\\&/g')([^A-Za-z0-9_.-]|$)" <<<"$1"; }  # 부분 문자열 말고 이름 단위로
CJ="$HOME/.claude.json"
todo=()

# ---------------------------------------------------------------- 플러그인
if [ -f "$S/plugins.json" ]; then
  have_mk="$(claude plugin marketplace list 2>/dev/null)"
  while IFS=$'\t' read -r name src; do
    has_word "$have_mk" "$name" && continue
    echo "마켓플레이스 추가: $name ($src)"
    run claude plugin marketplace add "$src" || todo+=("마켓플레이스 $name 추가 실패: claude plugin marketplace add $src")
  done < <(jq -r '.marketplaces | to_entries[] |
      [.key, (if .value.source == "github" then .value.repo elif .value.url then .value.url else (.value.path // "") end)] | @tsv' "$S/plugins.json")

  have_pl="$(claude plugin list 2>/dev/null)"
  while IFS=$'\t' read -r id scope; do
    has_word "$have_pl" "$id" && continue
    echo "플러그인 설치: $id ($scope)"
    run claude plugin install "$id" --scope "$scope" || todo+=("플러그인 $id 설치 실패: claude plugin install $id")
  done < <(jq -r '.plugins[] | [.id, .scope] | @tsv' "$S/plugins.json")
fi

# ---------------------------------------------------------------- MCP
add_mcp() {  # scope name json [cwd]
  local scope=$1 name=$2 json=$3 dir=${4:-$HOME}
  if grep -q '<SET_ME>' <<<"$json"; then
    todo+=("MCP $name ($scope${4:+, $4}): 비밀 값을 채워서 추가 → claude mcp add-json -s $scope $name '$json'"); return
  fi
  # 이미 있는지는 스코프별로 ~/.claude.json 에서 확인 (같은 이름이 user·local 양쪽에 있을 수 있음)
  if [ "$scope" = user ]; then jq -e --arg n "$name" '.mcpServers[$n]' "$CJ" >/dev/null 2>&1 && return
  else jq -e --arg d "$dir" --arg n "$name" '.projects[$d].mcpServers[$n]' "$CJ" >/dev/null 2>&1 && return; fi
  echo "MCP 추가: $name ($scope${4:+, $4})"
  (cd "$dir" && run claude mcp add-json -s "$scope" "$name" "$json") || todo+=("MCP $name 추가 실패")
  [[ "$json" == *'"http"'* || "$json" == *'"sse"'* ]] && todo+=("MCP $name: 처음 쓸 때 /mcp 에서 로그인(OAuth)이 필요할 수 있음")
}
if [ -f "$S/mcp.json" ]; then
  while IFS=$'\t' read -r name json; do add_mcp user "$name" "$json"; done \
    < <(jq -r '.user | to_entries[] | [.key, (.value | tojson)] | @tsv' "$S/mcp.json")
  while IFS=$'\t' read -r dir name json; do
    d="${dir/#\~/$HOME}"
    [ -d "$d" ] || { todo+=("MCP $name: 프로젝트 폴더 $dir 가 없어 건너뜀"); continue; }
    add_mcp local "$name" "$json" "$d"
  done < <(jq -r '.local | to_entries[] | .key as $d | .value | to_entries[] | [$d, .key, (.value | tojson)] | @tsv' "$S/mcp.json")
fi

echo
if [ ${#todo[@]} -gt 0 ]; then
  echo "직접 해야 할 일:"
  printf '  - %s\n' "${todo[@]}"
else
  echo "모두 설치됨"
fi
