# dotclaude

Claude Code 사용 환경(`~/.claude`)을 git으로 관리하는 레포다.

- **원본 레포(비공개)** 가 유일한 원본이다. 스킬·훅·스크립트·설정·개인 아카이브·메모리·프로젝트별 설정·은퇴한 항목이 전부 여기 있고,
  `~/.claude`에는 이 레포를 가리키는 심볼릭 링크만 있다. 사람과 Claude는 이 레포만 고친다.
- **공개 레포** 는 원본에서 자동으로 만들어지는 사본이다. 공개에 필요 없는 정보(개인 정보, 회사 정보, 로컬 경로, 비밀 값)는
  가리거나 구조만 남긴다. 직접 고치지 않는다 — 다음 동기화 때 원본 기준으로 다시 만들어진다.

두 레포는 기기마다 어디에 있어도 된다. `install.sh`가 `~/.claude/dotclaude/source`(원본), `~/.claude/dotclaude/export`(공개 사본)에
실제 위치로 가는 링크를 만들고, 훅과 스크립트는 모두 이 고정 경로로 레포를 찾는다. 레포 역할은 `.dotclaude-role`(source / export)로 구분한다.

## 새 기기 셋업

사용자가 "셋업", "초기화", "initialize" 등을 요청하면 아래 순서로 진행한다. 단계마다 결과를 확인하고, 실패하면 멈추고 알린다.

### 1. 준비물 확인

- `claude`(설치·로그인 완료), `git`, `jq`, `python3`, `rsync`가 있는지 `command -v`로 확인한다. 없으면 설치 방법을 안내한다.
- GitHub 인증: `gh auth status`. 안 되어 있으면 사용자에게 `! gh auth login`을 실행해 달라고 한다.
- 커밋에 쓸 git 사용자 이름·이메일이 설정돼 있는지 확인한다.

### 2. 레포 받기

어느 레포에서 이 문서를 읽고 있는지 `.dotclaude-role`로 확인한다.

- **원본 레포(source)를 쓰는 사람(레포 주인)**: 원본 레포를 원하는 곳에 받는다. 공개 레포도 쓰려면 같이 받는다.
  위치는 사용자에게 묻는다 (두 레포를 같은 폴더에 두는 것을 권한다).
  ```bash
  gh repo clone <계정>/dotclaude-private <원하는 경로>/dotclaude-private
  gh repo clone <계정>/dotclaude-public  <원하는 경로>/dotclaude-public    # 선택
  ```
- **공개 사본(export)을 받은 다른 사람**: 공개 사본은 가려진 부분이 있는 참고용이다. 자기 원본으로 쓰려면
  레포를 복사해 `.dotclaude-role`을 `source`로 바꾸고, `🔒 비공개`로 가려진 폴더(`me/`, `memory/` 등)는 비우거나 지운 뒤 3단계부터 진행한다.

### 3. 링크 설치

```bash
<원본 레포>/install.sh --dry-run          # 무엇이 바뀌는지 사용자에게 보여 준다
<원본 레포>/install.sh
<원본 레포>/install.sh --export <공개 레포>                  # 공개 레포를 쓸 때만
git -C <공개 레포> config core.hooksPath .githooks          # 공개 레포 커밋 전 유출 검사
# 공개 커밋 작성자는 GitHub noreply 주소로 (개인 메일이 공개 기록에 남지 않게). 설정 안 하면 export 가 커밋하지 않는다
git -C <공개 레포> config user.name  "<GitHub 사용자명>"
git -C <공개 레포> config user.email "$(gh api user -q .id)+<GitHub 사용자명>@users.noreply.github.com"
```
기존 `~/.claude` 파일은 지우지 않고 `~/.claude/backups/dotclaude-<시각>/`으로 옮긴다.
새 기기에 원래 있던 `settings.json`에 그 기기에서만 쓰던 설정이 있었다면 백업을 보고 `global/settings.json`에 합칠지 사용자에게 묻는다.

### 4. 플러그인·MCP

```bash
~/.claude/dotclaude/source/bin/setup-env.sh --dry-run
~/.claude/dotclaude/source/bin/setup-env.sh
```
마지막에 나오는 "직접 해야 할 일"을 사용자와 하나씩 처리한다.
- `<SET_ME>`가 있는 MCP 서버: 필요한 비밀 값을 사용자에게 받아 `claude mcp add-json`으로 추가한다. 비밀 값은 레포나 파일에 쓰지 않는다.
- HTTP MCP 서버의 OAuth 로그인: 사용자가 Claude Code 안에서 `/mcp`로 직접 한다.
- claude.ai 커넥터(`claude mcp list`에 `claude.ai ...`로 보이는 것)는 같은 계정으로 로그인하면 따라온다. 설치할 필요 없다.
- 기록 파일: `setup/plugins.json`, `setup/mcp.json` (동기화가 매번 갱신)

### 5. 훅 확인

`global/settings.json`(→ `~/.claude/settings.json`)에 아래 훅이 들어 있어야 한다. 원본 레포 없이 공개 사본만 참고하는 경우에는 직접 넣는다.
```json
"hooks": {
  "SessionStart": [{ "hooks": [{ "type": "command", "command": "~/.claude/dotclaude/source/install.sh --repair", "timeout": 10 }] }],
  "SessionEnd":   [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-close.sh", "timeout": 10 }] },
                   { "hooks": [{ "type": "command", "command": "~/.claude/dotclaude/source/bin/sync.sh --detach", "timeout": 10 }] }],
  "PreCompact":   [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-close.sh", "timeout": 10 }] }]
}
```
`session-close.sh`는 세션이 끝날 때 `archive-me`(사용자 정보 아카이빙)와 `improve-skills`(스킬 자동 보완)를 돌린다. 원하지 않으면 빼도 된다.

### 6. 검증

- `ls -l ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/skills/ ~/.claude/dotclaude/`로 링크가 레포를 가리키는지 확인
- `~/.claude/dotclaude/source/bin/sync.sh --no-push --no-review` 한 번 실행 후 `~/.claude/dotclaude-sync.log` 확인
- 새 세션에서 스킬 목록에 `skills/`의 스킬이 보이는지 확인

## 동작 방식

| 언제 | 무엇을 | 어디서 |
|---|---|---|
| 세션 시작 | 빠진 링크 생성, 일반 파일로 바뀐 링크 복구 (변경분은 레포로) | `install.sh --repair` |
| 세션 종료 | 원본: 원격 변경 받기 → 새 스킬·메모리 흡수 → 프로젝트 `.claude` 미러 → 플러그인·MCP 기록 → 사용 기록 누적 → 커밋·푸시 | `bin/sync.sh` |
| 세션 종료 | 공개 사본: 원본에서 다시 만들기 → 유출 검사 → 커밋·푸시 | `bin/export.py` |
| 7일마다 | 오래 안 쓴 항목 판단 후 `archive/`로 이동 | `bin/archive-review.py` |

- **흡수**: `~/.claude/skills|agents|commands/`에 실제 폴더로 새로 생긴 것과 `~/.claude/projects/*/memory`를 원본 레포로 옮기고 링크로 바꾼다.
  `skills/synced/`(claude.ai 스킬 동기화)는 건드리지 않는다.
- **프로젝트 미러**: 홈 아래 프로젝트별 `.claude`를 `projects/<홈 기준 경로>/`로 복사한다 (프로젝트 → 레포 한 방향).
  `settings.local.json`·로그·잠금 파일은 빼고, 그것뿐인 `.claude`는 미러하지 않는다. 제외할 경로는 `mirror-ignore.txt`.
  새 기기에서 프로젝트 설정을 되살리려면 해당 폴더를 프로젝트의 `.claude/`로 복사한다.
- **아카이브**: 60일 넘게 안 쓴 스킬·에이전트·커맨드, 활동 없는 프로젝트 미러·메모리를 후보로 뽑고,
  Claude가 `prompts/archive-judge.md` 기준으로 판단한다. 아카이브된 항목은 `archive/`로 옮겨지고 링크가 사라진다.
  git 밖에 있던 프로젝트는 원본 `.claude`도 지운다 (레포 사본과 같은지 확인한 뒤). 사유는 `archive/README.md`.
- **공개 사본 만들기** (`bin/export.py`, 처리 방식은 `export-policy.tsv`)
  - 항목마다 `exclude`(두지 않음) / `redact`(폴더 구조와 비공개 안내만) / `copy`(그대로) / `review`(Claude 검토) 중 하나로 처리한다.
  - `review` 항목은 내용이 바뀔 때만 Claude가 `prompts/mask.md` 기준으로 그대로 공개·가려서 공개·비공개 중 하나로 판정한다.
    결과는 `state/export.json`에 캐시한다. 검토가 밀리거나 실패하면 이전에 검토된 공개본을 유지하고, 없으면 비공개로 둔다.
  - 모든 텍스트 파일에서 `<!-- PRIVATE:START -->` ~ `<!-- PRIVATE:END -->`(그리고 `ME-ARCHIVE`) 구역은 기계적으로 지운다.
  - 프로젝트 미러의 로컬 폴더 구조는 공개하지 않는다 (`projects/<이름>`만). 이름이 차단 목록에 걸리면 이름도 가린다.
  - 마지막에 결과 전체를 `bin/leak-check.sh`로 검사하고, 걸리는 항목은 비공개로 바꾼다. 공개 레포 커밋도 pre-commit에서 한 번 더 검사한다.
  - 공개 레포 `EXPORT.md`에 항목별 공개 방식이 정리된다.
- **유출 검사** (`bin/leak-check.sh`): 비밀 값 패턴, 이메일, 실제 홈 경로, 개인 폴더로 시작하는 로컬 경로, `blocklist.txt`의 문자열을
  파일 내용과 경로 양쪽에서 찾는다.

로그: `~/.claude/dotclaude-sync.log`, 검토 작업 폴더: `~/.claude/dotclaude-runs/`

## 이 레포에서 작업할 때 규칙

- 원본 레포만 고친다. 공개 레포를 직접 고치지 않는다.
- 공개하면 안 되는 이름(회사명, 프로젝트 ID, 개인 폴더 이름 등)을 새로 알게 되면 `blocklist.txt`에 추가한다.
- 문서 안에 공개하면 안 되는 부분이 있으면 `<!-- PRIVATE:START -->` / `<!-- PRIVATE:END -->`로 감싼다.
- 항목의 공개 방식을 바꾸려면 `export-policy.tsv`에 규칙을 추가한다 (위에서부터 처음 맞는 규칙).
- 스킬을 은퇴시킬 때는 `git mv skills/<이름> archive/skills/<이름>` 후 `archive/README.md`에 사유를 적고 `install.sh`를 다시 실행한다. 되살릴 때는 반대로.
- 스크립트를 고쳤으면 `bin/sync.sh --no-push`로 한 번 돌려 로그를 확인한다.
