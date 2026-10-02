# Archive

더 이상 쓰지 않는 스킬·프로젝트 설정·메모리를 사용 당시 모습 그대로 보관한다. `links.tsv`에 넣지 않으므로 Claude Code가 불러오지 않는다.

## Skills

<!-- 이 구역은 개인 정보라 공개 사본에서 가렸습니다 -->
이전 직장에서 서버·앱·음성 에이전트 레포를 운영하며 쓰던 스킬.

| 이름 | 호출 횟수 | 마지막 사용 | 설명 |
|---|---|---|---|
| analyze-agent-logs | 82 | 2026-03-13 | GCP 프로덕션 에이전트 로그 분석 |
| analyze-client-log | 52 | 2026-03-13 | Slack + GCS 클라이언트 로그 분석 |
| fix-issue | 60 | 2026-03-12 | Sentry 이슈 6단계 수정 워크플로우 |
| fix-issue-teams | 1 | 2026-02-12 | fix-issue의 Agent Teams 실험판 |
| fix-issues-parallel | 0 | - | 다수 이슈 병렬 수정 |
| monitor-client-logs | 4 | 2026-02-23 | 클라이언트 로그 일일 요약 |
| cleanup-zombie-instances | 2 | 2026-03-06 | 좀비 인스턴스 정리 |
| infra-task | 2 | 2026-02-27 | 인프라 작업 워크플로우 |
| _shared (repos.md, personas/repo-expert-*) | - | - | 위 스킬들이 참조하던 레포 정보·페르소나 |

## Projects

프로젝트별 `.claude` 스냅샷 (2026-09-24 복사, `settings.local.json`·로그 제외). `init-project` 스킬이 생성한 하네스의 변천을 볼 수 있다.

| 이름 | 원본 위치 | 원본 git 관리 |
|---|---|---|
| temp-workspace | `<WORKSPACE>/temp-workspace` | 없음 |
| boardgame-simulator | `<WORKSPACE>/boardgame-simulator` | 없음 |
| service-for-small-business | `<PROJECTS_DIR>/working_dir/service-for-small-business` | 프로젝트 레포 |
| news | `<PROJECTS_DIR>/working_dir/news` | 프로젝트 레포 |
| commit-to-blog | `<PROJECTS_DIR>/working_dir/commit-to-blog` | 프로젝트 레포 |

## Memory

| 이름 | 원본 위치 |
|---|---|
| boardgame-simulator | `<WORKSPACE_PARENT>/.claude/projects/.../memory` (작업 폴더 상위에서 실행한 세션이 남긴 메모리) |

## 자동 아카이브 기록

| 날짜 | 항목 | 사유 |
|---|---|---|
| 2026-09-24 | `memory/<PROJECT_MEMORY_1>` | 한 프로젝트의 자료 전용 메모리로, 프로젝트가 끝나 다시 쓸 계기가 없다. |
| 2026-09-24 | `memory/<PROJECT_MEMORY_2>` | 한 프로젝트 전용 메모리이고, 담긴 규칙(로컬 문서 누적 금지)은 이미 task-with-harness·init-project 스킬 수정으로 반영돼 있다. |
| 2026-09-24 | `memory/<PROJECT_MEMORY_3>` | 학습용 web-todo 프로젝트 전용 worktree 예외 메모리로, 작업이 끝났고 178일간 쓰이지 않았다. |
| 2026-10-01 | `skills/init-project` | 사용자가 더 이상 쓰지 않는다고 확인 (마지막 사용 2026-06). Rust/Axum + Next.js 하네스 프로젝트 초기화용이었다. |
| 2026-10-01 | `skills/task-with-harness` | 사용자가 더 이상 쓰지 않는다고 확인 (마지막 사용 2026-06). boardgame-simulator 구조(루트 단일 레포, backend/·frontend/)를 전제한 하네스 구현 워크플로우였다. |
| 2026-10-01 | `memory/boardgame-simulator` | 165일간 쓰이지 않은 boardgame-simulator 전용 메모리로, 이 프로젝트의 .claude 설정과 전용 하네스 스킬(task-with-harness, init-project)이 이미 아카이브되어 다시 쓸 계기가 없다. 담긴 내용은 'subagent 적극 활용' 피드백 하나뿐이고, 이 프로젝트 경로에서만 불러온다. |
