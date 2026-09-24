---
name: fix-issues-parallel
description: 여러 Sentry 이슈를 병렬로 수정하는 배치 워크플로우. 메인 컨텍스트가 worktree를 먼저 생성하고, 이슈별 subagent에 할당하여 파일 충돌 없이 병렬 작업한다.
argument-hint: [Sentry-링크들-또는-이슈-ID-목록]
---

# Parallel Issue Fix Workflow

여러 Sentry 이슈를 동시에 수정한다. 각 이슈마다 독립된 worktree를 할당하여
파일 충돌 없이 병렬 작업하고, 이슈별 분리 커밋을 보장한다.

## 핵심 원칙

1. **메인 컨텍스트가 worktree를 생성**한다 (subagent는 Bash permission 이슈로 worktree 생성 불가)
2. 각 이슈에 **독립된 worktree**를 할당한다 — 파일 충돌 원천 차단
3. Subagent는 **할당된 worktree 경로에서만** 코드를 수정한다
4. 모든 subagent 완료 후 **메인 컨텍스트에서 검증 및 커밋**한다

## 대상 레포지토리

> **Reference**: `~/.claude/skills/_shared/repos.md`

## 사전 요구사항

`~/.claude/settings.json`에 다음 Bash 패턴이 등록되어야 한다:

```json
"Bash(git *)",
"Bash(mkdir *)",
"Bash(cd * && git *)",
"Bash(rmdir *)"
```

---

## Phase 0: 입력 수집 및 Sentry 조회

### 입력 형식

사용자로부터 아래 중 하나를 받는다:
- Sentry 링크 목록 (공백 또는 줄바꿈으로 구분)
- 자연어 요청: "현재 미해결 이슈들 수정해줘" → Sentry MCP로 조회

### Sentry에서 이슈 수집

```
[병렬 — 각 이슈 URL에 대해]
├── mcp__Sentry__get_issue_details(issueUrl=<URL1>)
├── mcp__Sentry__get_issue_details(issueUrl=<URL2>)
└── ...
```

각 이슈에 대해 수집:
- 이슈 제목, 에러 메시지, 스택트레이스
- 발생 빈도, 영향 유저 수
- 관련 파일명, 함수명 (스택트레이스에서 추출)

### 이슈 → 레포 매핑

스택트레이스에서 파일 경로를 추출하여 레포를 식별한다:

```
[병렬 Grep — 각 이슈의 키워드로 레포 검색]
├── Grep(pattern='<error_or_function>', path='../<SERVER_REPO>')
├── Grep(pattern='<error_or_function>', path='../<APP_REPO>')
└── Grep(pattern='<error_or_function>', path='../<VOICE_AGENT_REPO>')
```

결과: 이슈 → 레포 매핑 테이블

```
ISSUE_MAP:
- ISSUE_1 (APP-1)   → <APP_REPO>
- ISSUE_2 (AGENT-1) → <VOICE_AGENT_REPO>
- ISSUE_3 (APP-2)   → <APP_REPO>
- ...
```

### 파일 충돌 사전 감지

같은 레포를 수정하는 이슈들의 스택트레이스에서 **동일 파일**이 나타나는지 확인한다:

```
CONFLICT_CHECK:
- example.dart → APP-2, APP-3 (2개 이슈가 같은 파일 수정 가능)
- example.py → AGENT-2, AGENT-3, AGENT-4 (3개 이슈가 같은 파일 수정 가능)
```

충돌 감지 시 사용자에게 경고:
- "3개 이슈(AGENT-2, 3, 4)가 example.py를 수정할 수 있습니다"
- 사용자가 진행 여부를 결정한다

→ 사용자 승인 후 Phase 1로 진행

---

## Phase 1: Worktree 생성 (메인 컨텍스트)

**중요**: 이 단계는 반드시 메인 컨텍스트에서 실행한다. Subagent는 Bash permission 제약으로 worktree를 생성할 수 없다.

### 배치 ID 및 Worktree 생성

```
BATCH_ID = "fix-batch-<MMDD-HHMM>"
BATCH_BASE = "../.worktrees/${BATCH_ID}"
```

각 이슈마다 독립된 worktree를 생성한다:

```bash
# 1. 배치 베이스 디렉토리 생성
mkdir -p ${BATCH_BASE}

# 2. 이슈별 worktree 생성 (메인 컨텍스트에서 순차 실행)
for issue in ISSUE_1 ISSUE_2 ...; do
  WORKTREE_ID="fix-${issue_short_id}-<MMDD-HHMM>"

  # 해당 이슈의 대상 레포마다:
  cd ../<REPO> && \
    git worktree add ${BATCH_BASE}/${WORKTREE_ID}/<REPO> -b ${WORKTREE_ID}
done
```

### Worktree 생성 검증

모든 worktree가 정상적으로 생성되었는지 확인한다:

```bash
# 각 레포에서 worktree 목록 확인
cd ../<REPO> && git worktree list
```

**실패 시**: 해당 이슈를 배치에서 제외하고 사용자에게 보고한다. 나머지 이슈는 계속 진행한다.

### 할당 테이블 생성

```
ASSIGNMENT_TABLE:
| 이슈 | Worktree 경로 | 대상 레포 |
|------|--------------|----------|
| APP-1 | ${BATCH_BASE}/fix-app-1-0213-1430/<APP_REPO> | <APP_REPO> |
| AGENT-1 | ${BATCH_BASE}/fix-agent-1-0213-1430/<VOICE_AGENT_REPO> | <VOICE_AGENT_REPO> |
| ... | ... | ... |
```

---

## Phase 2: 병렬 Subagent 배정

각 이슈마다 하나의 background `general-purpose` subagent를 생성한다.

```
[병렬 — 단일 메시지에서 N개 Task 호출]
├── Task(subagent_type="general-purpose", run_in_background=true, prompt="[ISSUE_1 프롬프트]")
├── Task(subagent_type="general-purpose", run_in_background=true, prompt="[ISSUE_2 프롬프트]")
└── ...
```

### Subagent 프롬프트 템플릿

각 subagent에게 아래 프롬프트를 제공한다:

```
[레포별 페르소나 — ~/.claude/skills/_shared/personas/repo-expert-*.md 참조]

## 작업 대상
- 이슈: [이슈 ID]
- Sentry 정보: [에러 메시지, 스택트레이스, 발생 빈도]
- 대상 레포: [레포명]
- Worktree 경로: [${BATCH_BASE}/${WORKTREE_ID}/<REPO>]

## 작업 범위

**읽기 전용 탐색**: 메인 레포 경로에서 수행 (../<REPO>)
**코드 수정**: 반드시 worktree 경로에서만 수행

### 수행할 작업

1. **분석** (Phase 1-2 of fix-issue):
   - 메인 레포 경로에서 코드를 읽고 분석한다
   - 에러 발생 시나리오를 열거하고 분류한다 (A/B/C)
   - 호출 체인과 영향 범위를 파악한다

2. **수정** (Phase 3-4 of fix-issue):
   - 수정 계획을 수립한다
   - **Worktree 경로에서만** 코드를 수정한다: [worktree 경로]
   - Edit 도구 사용 시 file_path가 반드시 worktree 경로여야 한다

3. **검증** (Phase 5 of fix-issue):
   - 수정이 모든 시나리오를 커버하는지 확인한다
   - Regression 가능성을 점검한다

4. **보고**:
   - 수정한 파일 목록과 각 변경 내용을 보고한다
   - 검증 결과 (pass/fail/warning)를 보고한다

## 금지 사항
- 메인 레포 경로(../<REPO>)에서 코드를 수정하지 않는다
- git commit, git branch 등 git 명령을 실행하지 않는다 (커밋은 메인 컨텍스트가 담당)
- 다른 이슈의 worktree를 수정하지 않는다
- 이슈와 무관한 코드를 변경하지 않는다
```

### Subagent 배치 제한

- 동시 실행 subagent는 **최대 10개**로 제한한다
- 10개 초과 시 5개씩 배치로 나눠 순차 그룹 실행한다

---

## Phase 3: 진행 모니터링

Background subagent들의 진행 상태를 모니터링한다.

```
[주기적 확인]
1. TaskOutput(task_id=<id>, block=false) 로 각 subagent 상태 확인
2. 완료된 subagent의 결과를 수집한다
3. 실패한 subagent는 에러 원인을 파악하고 사용자에게 보고한다
```

### 실패 처리

- **Permission denied**: 사용자에게 보고, 해당 이슈를 수동 처리로 전환
- **분석 불가**: 사용자에게 보고, 추가 정보 요청
- **Worktree 경로 오류**: worktree 상태 확인 후 재할당

모든 subagent 완료 시 Phase 4로 진행한다.

---

## Phase 4: 결과 검증 및 커밋 (메인 컨텍스트)

### 4-1. 변경사항 확인

각 worktree의 변경사항을 확인한다:

```bash
# 이슈별 diff 확인
cd ${BATCH_BASE}/${WORKTREE_ID}/<REPO> && git diff
```

### 4-2. 크로스 이슈 충돌 검증

같은 레포를 수정한 이슈들의 변경사항이 **의미적으로 충돌**하지 않는지 확인한다:

```
[Explore subagent — 통합 검증]
> 아래 이슈들이 같은 레포의 다른 worktree에서 수정되었다.
> 각 이슈의 diff를 비교하여 의미적 충돌이 있는지 확인하라:
>   - ISSUE_A diff: [diff 내용]
>   - ISSUE_B diff: [diff 내용]
> 충돌: 같은 함수의 같은 라인을 다르게 수정, 상충되는 로직 변경 등
```

충돌 발견 시:
- 사용자에게 보고하고 해결 방향을 확인받는다
- 한 이슈의 수정만 적용하거나, 수동으로 통합한다

### 4-3. 이슈별 커밋

충돌이 없으면 각 worktree에서 커밋한다:

```bash
# 각 이슈 worktree에서:
cd ${BATCH_BASE}/${WORKTREE_ID}/<REPO>
git add <modified-files>
git commit -m "fix: [이슈 요약] ([이슈 ID])

[상세 설명]

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

### 4-4. 결과 요약

사용자에게 전체 결과를 보고한다:

```markdown
## 배치 수정 결과

| # | 이슈 | 상태 | 커밋 | 수정 파일 |
|---|------|------|------|----------|
| 1 | APP-1 | 완료 | abc1234 | example.dart |
| 2 | AGENT-1 | 완료 | def5678 | example.py |
| 3 | APP-4 | 실패 | - | 분석만 완료, 추가 검토 필요 |
| ... | ... | ... | ... | ... |
```

---

## Phase 5: 후속 옵션

사용자에게 다음 옵션을 안내한다:

| 옵션 | 설명 |
|------|------|
| **개별 머지** | 각 이슈 브랜치를 개별 PR로 생성 |
| **통합 머지** | 모든 이슈 브랜치를 하나의 브랜치로 머지 후 단일 PR |
| **선택적 머지** | 일부 이슈만 머지, 나머지는 보류 |
| **보류** | worktree를 유지하고 나중에 처리 |

### 통합 머지 시

```bash
# 메인 브랜치에서 통합 브랜치 생성
cd ../<REPO>
git checkout -b fix-batch-<MMDD-HHMM>

# 각 이슈 브랜치를 순차 머지
git merge fix-<issue1-id>-<timestamp>
git merge fix-<issue2-id>-<timestamp>
...
```

### Worktree 정리

**사용자 승인 없이 worktree를 삭제하지 않는다.**

```bash
# 각 이슈 worktree 제거:
cd ../<REPO>
git worktree remove ${BATCH_BASE}/${WORKTREE_ID}/<REPO>

# 배치 디렉토리 정리:
rmdir ${BATCH_BASE}/${WORKTREE_ID}
rmdir ${BATCH_BASE}
```

---

## 규칙

- **Worktree 생성은 반드시 메인 컨텍스트에서** 수행한다. Subagent에게 위임하지 않는다.
- **Subagent는 할당된 worktree 경로에서만** 코드를 수정한다. 메인 레포를 수정하면 안 된다.
- **git 명령어(commit, branch 등)는 메인 컨텍스트에서만** 실행한다.
- 동시 실행 subagent는 **최대 10개**로 제한한다.
- 파일 충돌이 감지되면 **사용자에게 보고**하고 진행 여부를 확인받는다.
- Phase 0에서 사용자에게 이슈 목록과 충돌 가능성을 보고하고, **승인 후** 작업을 시작한다.
- 확신이 없으면 멈추고 질문한다. 추측하지 않는다.
- 이슈와 무관한 코드를 변경하지 않는다.

---

## fix-issue와의 차이점

| | fix-issue | fix-issues-parallel |
|---|---|---|
| **입력** | 단일 이슈 | 다수 이슈 (N개) |
| **Worktree 생성** | Subagent가 시도 (실패 가능) | 메인 컨텍스트가 사전 생성 (보장) |
| **파일 충돌** | 해당 없음 | Phase 0에서 사전 감지 |
| **커밋** | Subagent가 수행 | 메인 컨텍스트가 통합 수행 |
| **검증** | 이슈별 4개 검증 subagent | 이슈별 자체 검증 + 크로스 이슈 통합 검증 |
