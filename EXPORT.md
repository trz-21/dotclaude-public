# 공개 사본 목록

이 레포는 비공개 원본 레포에서 자동으로 만들어진 공개 사본이다. 직접 고치지 않는다.
개인 정보·회사 정보가 들어 있는 항목은 가리거나(🔒) 식별 정보를 자리표시자로 바꿨다.

| 경로 | 공개 방식 | 설명 |
|---|---|---|
| `.githooks` | 그대로 |  |
| `.gitignore` | 그대로 |  |
| `CLAUDE.md` | 그대로 |  |
| `README.md` | 그대로 |  |
| `archive/README.md` | 가려서 공개 | 더 이상 쓰지 않는 스킬·프로젝트 설정·메모리 아카이브의 목록과 자동 아카이브 기록 |
| `archive/memory/boardgame-simulator` | 🔒 비공개 |  |
| `archive/memory/boardgame-simulator` | 그대로 (검토함) | 작업할 때 subagent를 적극적으로 쓰라는 프로젝트 전용 피드백 메모리 (아카이브) |
| `archive/memory/home-MEMORY-skill-notes.md` | 🔒 비공개 |  |
| `archive/memory/masked-131d6a34` | 🔒 비공개 |  |
| `archive/memory/masked-7218b55f` | 🔒 비공개 |  |
| `archive/memory/no-local-doc-accumulation` | 가려서 공개 | 스킬이 로컬 프로젝트에 작업 로그·계획·세션 문서를 쌓지 않고 대화로 보고하도록 한 피드백 메모 |
| `archive/projects/boardgame-simulator` | 가려서 공개 | Rust/Axum + Next.js 프로젝트에 쓰던 .claude 하네스 스냅샷 (컴파일·테스트·스펙 동기화 훅, DoD, 커밋 규칙) |
| `archive/projects/commit-to-blog` | 가려서 공개 | plans 항목 하나를 spec/design 근거로 공백 점검·병렬 분해·서브에이전트 구현·메인 직접 검증·커밋까지 진행하는 implement-plan-item 스킬과 eval |
| `archive/projects/service-for-small-business` | 가려서 공개 | Rust+TS 풀스택 프로젝트에서 로컬 docs 대신 GitHub Issue→브랜치→PR→Wiki 흐름을 강제하고 컴파일·테스트·커버리지·Wiki 갱신 리마인드를 훅으로 건 하네스 설정 |
| `archive/projects/temp-workspace` | 가려서 공개 | 작업 로그 누락 시 응답을 막는 문서 강제 훅 중심의 초기 .claude 하네스 스냅샷 |
| `archive/projects/weekly-plan-work` | 가려서 공개 | 주차별 스펙으로 plan을 세우고 항목을 wave 단위로 병렬 구현해 항목마다 커밋하는 /work 스킬, 커밋 메시지의 리뷰 칸을 채우는 /commit-review 스킬, 대화에서 나온 규칙을 CLAUDE.md에 자동으로 추가하는 Stop 훅 |
| `archive/skills/_shared` | 가려서 공개 | 보관된 스킬들이 참조하던 대상 레포 정보, 레포 전문가·검증자 페르소나, 서브에이전트 활용 원칙 |
| `archive/skills/analyze-agent-logs` | 가려서 공개 | LiveKit 음성 에이전트의 GCP Cloud Logging 프로덕션 로그를 call_id나 기간으로 조회해 심각도별로 분류·요약하던 스킬 |
| `archive/skills/analyze-client-log` | 가려서 공개 | Slack 알림과 GCS에서 클라이언트 로그를 찾아 받아 코드 기준으로 비정상 통화 원인을 분석하는 워크플로우 |
| `archive/skills/cleanup-zombie-instances` | 가려서 공개 | MIG에서 빠졌지만 RUNNING으로 남은 GCE 인스턴스를 찾아 SIGTERM으로 drain한 뒤 자동 셧다운시키는 스킬 |
| `archive/skills/fix-issue` | 가려서 공개 | Sentry 이슈나 증상 설명을 받아 시나리오 분류, 병렬 탐색, worktree 수정, 다관점 검증까지 진행하는 6단계 이슈 수정 워크플로우 |
| `archive/skills/fix-issue-teams` | 가려서 공개 | Agent Teams로 레포별 팀원이 병렬 탐색·수정하고 검증 팀원이 교차 검증하는 이슈 수정 워크플로우(실험판) |
| `archive/skills/fix-issues-parallel` | 가려서 공개 | 여러 Sentry 이슈마다 worktree를 미리 만들어 subagent에 나눠 맡기고 메인 컨텍스트에서 검증·커밋하는 병렬 수정 워크플로우 |
| `archive/skills/infra-task` | 가려서 공개 | 사용자와 스펙을 반복 구체화한 뒤 인프라 변경을 구현하고 호환성·보안·인프라 정합성 관점으로 검증하는 워크플로우 |
| `archive/skills/init-project` | 가려서 공개 | 서비스 설명을 받아 Rust/Axum + Next.js 프로젝트와 스펙 문서, Claude 훅 하네스를 한 번에 세팅하던 스킬 |
| `archive/skills/monitor-client-logs` | 가려서 공개 | 하루치 클라이언트 로그를 Slack·GCS에서 모아 에러 패턴과 트렌드를 대시보드로 요약하는 스킬 |
| `archive/skills/task-with-harness` | 그대로 (검토함) | 기능 하나를 서브에이전트로 구현시키고 메인이 컴파일·테스트·커버리지를 직접 검증한 뒤 커밋하던 스킬 |
| `archive/skills/wrap` | 그대로 (검토함) | session-wrap 플러그인에 스킬 개선 분석을 얹었던 세션 마무리 스킬 |
| `bin` | 그대로 |  |
| `blocklist.txt` | 🔒 비공개 |  |
| `export-policy.tsv` | 그대로 |  |
| `global/CLAUDE.md` | 그대로 (검토함) | 모든 프로젝트에 적용하는 전역 지침: 실행 전 검증, git worktree 격리, dotclaude 레포 관리 규칙 |
| `global/settings.json` | 그대로 (검토함) | 전역 Claude Code 설정 (권한 허용·확인 목록, 세션 시작·종료 훅, 플러그인) |
| `hooks/hook-digest.py` | 그대로 (검토함) | 세션 종료 훅의 결과(스킬 자동 수정·실패·확인 대기·무인 실행 비용)를 세션 시작 때 알리고 리포트로 만드는 스크립트 |
| `hooks/session-close.sh` | 그대로 (검토함) | 세션 종료·압축 때 transcript를 대기열에 넣고 하루 한 번 archive-me·improve-skills를 무인 일괄 실행하는 훅 |
| `install.sh` | 그대로 |  |
| `links.tsv` | 그대로 |  |
| `me` | 🔒 비공개 |  |
| `memory` | 🔒 비공개 |  |
| `mirror-ignore.txt` | 🔒 비공개 |  |
| `projects/masked-c1ee805a` | 🔒 비공개 |  |
| `prompts` | 그대로 |  |
| `setup/mcp.json` | 가려서 공개 | 사용자·프로젝트 범위별로 등록한 MCP 서버(Notion, Sentry, Datadog, Figma, Gmail) 설정 목록 |
| `setup/plugins.json` | 그대로 (검토함) | 설치한 Claude Code 플러그인 마켓플레이스와 플러그인 목록 |
| `skills/_shared` | 가려서 공개 | 스킬이 코드를 수정할 때 git worktree로 격리하는 공통 절차 |
| `skills/archive-me` | 그대로 (검토함) | 세션에서 드러난 사용자 정보를 분류 체계에 따라 ~/.claude/me/에 저장하고 CLAUDE.md 인덱스를 갱신하는 스킬 |
| `skills/hook-review` | 가려서 공개 | 세션 종료 훅이 무인으로 한 스킬 자동 수정·실패·확인 대기 수정안을 사용자와 함께 검토하고 처리하는 스킬 |
| `skills/improve-skills` | 가려서 공개 | 세션에서 쓴 스킬을 돌아보고 사용자 교정·실패 신호를 스킬 파일에 백업·변경 기록과 함께 반영하는 스킬 (훅 무인 모드 포함) |
