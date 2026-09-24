# dotclaude-public

Claude Code 사용 환경(`~/.claude`) — 스킬, 훅, 설정, 프로젝트별 하네스, 은퇴한 스킬 — 을 공유하는 레포.

이 레포는 **비공개 원본 레포에서 세션이 끝날 때마다 자동으로 만들어지는 공개 사본**이다.
공개에 필요 없는 정보(개인 정보, 회사 정보, 로컬 경로, 비밀 값)는 자리표시자·상대경로로 바꾸거나,
내용 전체가 개인적인 것은 폴더 구조와 `🔒 비공개` 안내만 남겼다. 항목별 공개 방식은 [`EXPORT.md`](EXPORT.md).

```
skills/          현역 스킬
hooks/           훅 (session-close.sh: 세션 종료 때 사용자 정보 아카이빙·스킬 자동 보완)
global/          전역 CLAUDE.md·settings.json (개인 부분은 가림)
archive/         은퇴한 스킬, 끝난 프로젝트의 Claude 설정(하네스), 메모리
projects/        진행 중인 프로젝트별 .claude
bin/             링크 설치·자동 동기화·아카이브·공개 사본 생성·유출 검사 스크립트
prompts/         아카이브 판단·공개 검토에 쓰는 무인 Claude 실행 프롬프트
me/, memory/     🔒 개인 아카이브·자동 메모리 (구조만)
CLAUDE.md        구조, 셋업 절차, 동작 방식 (Claude 가 읽고 따라 하도록 작성)
```

## 가져다 쓰기

- 스킬 하나만 쓰려면 `skills/<이름>/` 폴더를 `~/.claude/skills/`에 복사한다.
- 전체 구조를 쓰려면 이 레포를 복사해 자기 원본 레포로 만들고, 그 폴더에서 Claude Code를 열어 "셋업해줘"라고 한다
  (`CLAUDE.md`의 절차. `.dotclaude-role`을 `source`로 바꾸고 `🔒` 폴더는 비운다).
