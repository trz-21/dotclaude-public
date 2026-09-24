---
name: fix-issue
description: Sentry 이슈 로그 또는 유저 문제 상황 설명을 분석하고, 시나리오별 원인을 파악하여 수정하는 워크플로우.
argument-hint: [Sentry-링크-또는-문제-상황-설명]
---

# Issue Fix Workflow

## 입력 정보

사용자로부터 아래 중 하나 이상을 받는다:
- **이슈 로그 content**: 에러/경고 로그 내용
- **Sentry 링크**: Sentry 이벤트 URL
- **자연어 문제 설명**: 유저가 경험하는 증상 설명
- **Project source**: 어떤 프로젝트에서 발생했는지

## 대상 레포지토리

> **Reference**: `~/.claude/skills/_shared/repos.md`

## 병렬 처리 전략

이 워크플로우는 **subagent를 적극 활용**하여 병렬로 탐색/분석한다.

> **Reference**: `~/.claude/skills/_shared/subagent-principles.md`

### Subagent 페르소나

subagent를 생성할 때, 프롬프트의 맨 앞에 해당 페르소나 파일의 내용을 읽어서 주입한다.

#### 레포별 페르소나 (Phase 1, 2, 4에서 사용)

- **<SERVER_REPO> 전문가**: `~/.claude/skills/_shared/personas/repo-expert-server.md`
- **<APP_REPO> 전문가**: `~/.claude/skills/_shared/personas/repo-expert-app.md`
- **<VOICE_AGENT_REPO> 전문가**: `~/.claude/skills/_shared/personas/repo-expert-voice-agent.md`

#### 검증 페르소나 (Phase 5에서 사용)

- **완전성 검증자**: `~/.claude/skills/_shared/personas/verifier-completeness.md`
- **비용 분석가**: `~/.claude/skills/_shared/personas/verifier-cost-analyst.md`
- **동시성/DB 전문가**: `~/.claude/skills/_shared/personas/verifier-concurrency-db.md`
- **성능 분석가**: `~/.claude/skills/_shared/personas/verifier-performance.md`

**플랫폼 안전성 검증자:**
> 너는 크로스 플랫폼(iOS, Android) 개발의 플랫폼 특성 차이를 이해하는 전문가다.
> iOS의 싱글톤/생명주기(AudioSession, CallKit, VoIP 푸시), Android의 권한/백그라운드/포어그라운드 서비스, WebRTC 플랫폼별 구현 차이를 깊이 있게 이해한다.
> 코드 변경이 특정 플랫폼에서만 문제를 일으키는지, 플랫폼별 폴백 경로가 안전한지 검증한다.

---

## Git Worktree 전략

> **Reference**: `~/.claude/skills/_shared/git-worktree.md` 를 따른다.

- **Phase 1~3 (분석)**: 메인 레포에서 읽기 전용으로 탐색한다.
- **Phase 4~6 (수정/검증/커밋)**: git worktree에서 작업한다.
- prefix는 `fix`를 사용한다. (예: `fix-proj-123-0213-1430`)

---

## Phase 1: 입력 분석

입력 유형을 판별하여 분기한다.

### 입력 유형 판별 기준

- **Sentry 입력**: Sentry 링크, 스택트레이스, 로그 레벨(ERROR/WARNING), 에러 메시지가 포함된 경우
- **자연어 입력**: 유저 증상 설명, 기능 동작 이상 등 코드 로그가 아닌 자연어 설명인 경우
- **혼합 입력**: 둘 다 포함된 경우 Sentry 입력 경로를 따르되, 자연어 설명도 컨텍스트로 활용

---

### 경로 A: Sentry 로그 기반 분석

1. 로그 content를 분석한다:
   - 에러 메시지, 스택트레이스, 로그 레벨 파악

2. **Sentry 링크가 있으면 Sentry MCP로 상세 정보를 수집**한다:

   ```
   [순차 실행 — Sentry MCP 도구 활용]

   ① mcp__Sentry__get_issue_details(issueUrl=<Sentry URL>)
      → 이슈 제목, 스택트레이스, 발생 빈도, 영향 유저 수, 최초/최근 발생 시간

   ② 필수 tag 값 조회 (병렬 실행):
      ├── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='environment')
      ├── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='release')
      └── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='url')
      → 환경/릴리즈/URL별 분포 파악

      선택적 tag 조회 (클라이언트 이슈 의심 시):
      ├── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='browser')
      ├── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='os')
      └── mcp__Sentry__get_issue_tag_values(issueUrl=<URL>, tagKey='device')

   ③ (필요시) mcp__Sentry__search_events(organizationSlug=<org>, naturalLanguageQuery='...')
      → 관련 이벤트 패턴 검색 (특정 시간대 집중 발생, 특정 릴리즈 이후 급증 등)
   ```

   **수집한 Sentry 컨텍스트를 정리**한다:
   - 이슈 요약: 에러 메시지, 발생 빈도, 영향 유저 수
   - 분포 패턴: 특정 환경/디바이스/릴리즈에 집중되는지
   - ~~Seer 분석~~: 스킵 (비용 대비 효용 낮음, `analyze_issue_with_seer` 호출하지 않음)
   - 스택트레이스에서 추출한 파일명, 함수명, 라인 번호

   Sentry 링크가 없는 로그 content만 있는 경우, 이 단계를 건너뛰고 로그에서 직접 키워드를 추출한다.

3. **Identify relevant repos** using quick Grep from the main context (NOT subagents):

   ```
   [Parallel Grep — main context, no subagents]
   ├── Grep(pattern='<error_message_or_function_name>', path='../<SERVER_REPO>')
   ├── Grep(pattern='<error_message_or_function_name>', path='../<APP_REPO>')
   └── Grep(pattern='<error_message_or_function_name>', path='../<VOICE_AGENT_REPO>')
   ```

   Use error messages, function names, and file names from the stack trace as search keywords.
   If Sentry provided exact file:line info, check that specific repo first.

   **Launch Explore subagents ONLY for repos where Grep found matches:**

   ```
   [Parallel — matched repos only, inject repo persona]
   └── Explore subagent (matched repo persona) → deep code exploration
   ```

   Each Explore subagent receives:
   - The repo-specific persona (from Subagent Personas section)
   - Sentry context from step 2 (stack trace, error message, Seer analysis, tag distribution)
   - Instructions:
     - Read matched code and surrounding context (conditions, try-catch, call chains)
     - If Sentry tags show anomalies (e.g., specific OS/device), explore related code branches
     - Check logging config (log levels, Sentry dispatch conditions)
     - Report: file:line locations, code logic, potential failure scenarios

4. subagent 결과를 종합하여, 해당 로그가 **찍힐 수 있는 모든 시나리오**를 열거한다.

5. 각 시나리오를 **유저 영향 관점**에서 분류한다:

| 분류 | 기준 | 대응 방향 |
|------|------|----------|
| **A. 유저 무영향** | 유저가 인지하지 못하며 기능에 문제 없음 | 로그 레벨 조정 또는 조건부 로깅 |
| **B. 조건부 이슈** | 특정 상황에서만 유저에게 영향 | 조건 분기: **알려진 시나리오만** 분기 처리, 미분류 케이스는 기본 error 유지 |
| **C. 실제 이슈** | 유저가 기능 장애를 경험 | 근본 원인 수정 |

6. **분석 결과를 사용자에게 보고**한다:
   - 발견한 모든 시나리오 목록
   - 각 시나리오의 분류 (A/B/C)
   - 어떤 레포를 수정해야 하는지 (단일 vs 복수 레포)
   - 사용자에게 시나리오별 판단을 확인받는다

→ Phase 2로 진행

---

### 경로 B: 자연어 문제 설명 기반 분석

1. 문제 설명에서 단서를 추출한다:
   - **유저 행동**: 유저가 무엇을 하고 있었는가
   - **기대 동작**: 정상적으로는 어떻게 되어야 하는가
   - **실제 증상**: 무엇이 잘못되고 있는가
   - **관련 기능 키워드**: 해당 증상과 연결될 수 있는 기능/모듈

2. **Identify relevant repos** using quick Grep from the main context (NOT subagents):

   ```
   [Parallel Grep — main context, no subagents]
   ├── Grep(pattern='<feature_keyword>', path='../<SERVER_REPO>')
   ├── Grep(pattern='<feature_keyword>', path='../<APP_REPO>')
   └── Grep(pattern='<feature_keyword>', path='../<VOICE_AGENT_REPO>')
   ```

   **Launch Explore subagents ONLY for repos where Grep found matches:**

   ```
   [Parallel — matched repos only, inject repo persona]
   └── Explore subagent (matched repo persona) → deep code exploration
   ```

   Each Explore subagent receives:
   - The repo-specific persona (from Subagent Personas section)
   - Instructions:
     - Search for routers, controllers, service files related to the keywords
     - Trace the full flow (entry point → processing → response)
     - Focus on error handling, timeouts, state transition logic
     - List all potential failure points in the flow
     - **네이티브 패키지 소스 조사**: 문제가 SDK/패키지의 네이티브 구현과 관련될 수 있으면, `.pub-cache`(Flutter) 또는 `node_modules`(Node.js)의 네이티브 소스를 읽어 실제 플랫폼별 동작을 확인한다. 특히 iOS/Android AudioSession, WebRTC, CallKit 등 플랫폼 API 래퍼의 실제 구현을 파악한다.

3. subagent 결과를 종합하여, 문제 증상이 **발생할 수 있는 모든 시나리오**를 열거한다.

4. 시나리오별 가능성을 평가하고, 가장 유력한 원인을 코드 근거와 함께 결정한다.

→ Phase 2로 진행

---

### 공통 시나리오 체크리스트

경로 A/B 모두에서 아래 시나리오를 빠짐없이 고려한다:
- 정상적인 사용 흐름에서 발생 가능한 경우
- 네트워크 오류, 타임아웃, 외부 서비스 장애
- Race condition, 동시 요청, 상태 불일치
- 클라이언트-서버 간 프로토콜 불일치 (버전 차이 등)
- 엣지 케이스 (빈 데이터, null, 비정상 입력)
- 사용자의 비정상 행동 (앱 강제 종료, 네트워크 전환 등)
- 외부 프로바이더 오류 (STT/LLM/TTS fallback 과정에서 발생)
- 타이밍 이슈 (비동기 작업 완료 전 UI 전환, 이벤트 순서 역전)
- 인증/세션 만료 (토큰 refresh 타이밍)
- **빠른 상태 전환**: BT 연결→즉시 해제, 네트워크 WiFi→셀룰러→WiFi 빠른 전환, 앱 백그라운드→포그라운드 반복 등 짧은 시간 내 상태가 여러 번 변경되는 시나리오. 디바운싱/쓰로틀링이 이를 올바르게 처리하는지 검증
- **미래 시나리오**: 플랫폼 업데이트, 라이브러리 버전 변경, 새로운 에러 코드 등장 등 아직 발생하지 않은 케이스. 로그 레벨 변경 시 미지의 에러를 놓치지 않도록 기본 error 수준을 유지해야 하는지 검토

---

### Phase 1 → 2 Handoff

Before proceeding to Phase 2, compile the following **PHASE_1_CONTEXT** block.
Pass this block to all Phase 2 subagents. This is NOT a summary — include all essential data.

```
PHASE_1_CONTEXT:
- Issue: [exact error message or user symptom description]
- Input type: [Sentry / natural language / mixed]
- Sentry metrics (if applicable): events=[count], users=[count], first_seen=[date], release_trend=[versions]
- Sentry tags (if applicable): environment=[distribution], release=[distribution], os=[distribution]
- Affected repos: [list of repos where Grep/Explore found matches]
- Code locations: [file:line for each match, with brief description of what the code does]
- Scenarios identified:
  - Scenario 1: [description] → Classification: [A/B/C] → Affected repo: [repo]
  - Scenario 2: ...
- Key code findings: [critical logic, conditions, error handling patterns discovered]
```

---

## Phase 2: 코드 탐색 및 영향 범위 파악

Phase 1에서 관련 레포가 복수로 식별된 경우, **레포별 Explore subagent를 병렬 실행**한다.

```
[병렬 실행 - 각 subagent에 레포별 페르소나 주입]
├── Explore subagent (레포 A 페르소나) → 로그 발생 지점의 호출 체인 상위 추적
└── Explore subagent (레포 B 페르소나) → 연동 지점의 요청/응답 흐름 추적
```

각 subagent에게 **해당 레포 페르소나를 프롬프트 맨 앞에 포함**하고 아래를 지시한다:
1. 로그/문제 발생 지점의 **전체 호출 체인**을 추적한다:
   - 해당 함수를 호출하는 모든 caller를 찾는다
   - 해당 함수가 호출하는 모든 callee를 찾는다
   - API 엔드포인트 ↔ 클라이언트 호출 매핑을 확인한다
2. **관련 코드를 읽고 이해**한다:
   - 해당 함수/메서드의 전체 로직
   - 호출하는 외부 서비스 및 DB 쿼리
   - 에러 핸들링 패턴 (try-catch, fallback, retry)
   - 관련 미들웨어, 인터셉터 (AuthMiddleware, TokenRefreshInterceptor 등)

결과를 종합한다.

### Phase 2 → 3 Handoff

Before proceeding to Phase 3, compile the following **PHASE_2_CONTEXT** block.
Includes PHASE_1_CONTEXT + Phase 2 findings. Pass this to Phase 3+ subagents.

```
PHASE_2_CONTEXT:
- [Include all of PHASE_1_CONTEXT above]
- Call chains:
  - [function_A] → called by [caller1, caller2] → calls [callee1, callee2]
  - [function_B] → ...
- Cross-repo interactions: [API endpoint ↔ client call mappings]
- Error handling patterns: [try-catch structure, fallback logic, retry behavior]
- Middleware/interceptors involved: [list with brief description]
- Root cause assessment: [most likely cause with code evidence]
```

---

## Phase 3: 수정 계획 수립

분석 결과에 따라 대응 계획을 수립한다.

### 진행 불가 판단 — 사용자에게 보고하는 경우

아래 두 조건 중 하나에 해당하면 **사용자에게 보고하고 판단을 요청**한다:

1. **코드 레벨에서 해결할 수 없는 경우**
   - 외부 서비스(LiveKit, STT/LLM/TTS 프로바이더) 자체의 장애 또는 제약
   - 인프라/배포 설정 문제 (DNS, 로드밸런서, 방화벽 등)
   - OS/디바이스 레벨 제약 (iOS 백그라운드 정책, 안드로이드 권한 등)
   - 서드파티 SDK의 알려진 버그

2. **코드에서 확인 불가능한 맥락이 추가로 필요한 경우**
   - 특정 유저의 계정/구독 상태, 디바이스 정보
   - 문제 발생 시점의 서버/인프라 상태 (배포 중이었는지, 스케일링 이벤트 등)
   - 외부 서비스의 장애 타임라인
   - 유저의 구체적 행동 순서 (재현 스텝)
   - 비즈니스 요구사항에 대한 의사결정 (기능 변경, 우선순위 등)

   이때 요청하는 정보는 **코드 탐색으로 절대 알 수 없는 것**이어야 한다.
   코드에서 확인할 수 있는 정보를 사용자에게 물어서는 안 된다.

위 조건에 해당하지 않으면, 바로 Phase 4 구현으로 진행한다.

### 공식 문서 참조 (선택적)

다음 중 하나라도 해당하는 경우에만 공식 문서를 WebSearch/WebFetch로 조회한다:
- 새로운 라이브러리/API를 처음 사용할 때
- deprecated API 또는 버전 업그레이드가 관련될 때
- 에러 핸들링, 타임아웃, 재시도 등 비표준 패턴을 사용할 때
- 라이브러리의 알려진 제약사항/버그가 의심될 때

이미 숙지된 기본 API 사용(route decorator, ORM select, Widget lifecycle 등)은 생략한다.

주요 문서 소스:
| 스택 | 문서 |
|------|------|
| FastAPI | fastapi.tiangolo.com |
| Tortoise ORM | tortoise.github.io |
| Sentry Python/Flutter | docs.sentry.io |
| Flutter | api.flutter.dev, docs.flutter.dev |
| GetX | pub.dev/packages/get |
| Dio | pub.dev/packages/dio |
| LiveKit Agents | docs.livekit.io/agents |
| LiveKit Client | docs.livekit.io/client-sdk |
| OpenAI API | platform.openai.com/docs |
| Google GenAI | ai.google.dev/gemini-api/docs |
| Apple Developer | developer.apple.com/documentation (AVAudioSession, CallKit, CoreBluetooth 등) |

### 대응 유형 (Sentry 입력인 경우)

| 분류 | 대응 |
|------|------|
| **A. 유저 무영향** | 로그 레벨을 ERROR → WARNING/INFO로 변경 또는 제거. Sentry 이벤트 차단 |
| **B. 조건부 이슈** | 조건 분기: 이슈인 경우만 ERROR, 아닌 경우 INFO/DEBUG 또는 제거 |
| **C. 실제 이슈** | 근본 원인 수정 |

### 조건 분기 설계 원칙 (A/B 케이스)

로그 레벨을 하향 조정하거나 조건 분기를 구현할 때:

1. **알려진 시나리오만 분기**: Phase 1에서 명확히 분류한 시나리오만 info/warning으로 변경
2. **미지의 케이스는 error 유지**: 현재 분석에서 커버하지 않은 상황은 항상 ERROR로 로깅. 미래에 새로운 에러 패턴이 등장했을 때 감지할 수 있어야 한다
3. **일괄 변경 금지**: 모든 에러를 한번에 다운그레이드하지 않는다. 알려진 것만 분기하고 나머지는 기본 레벨을 유지한다

```
if (isKnownNonActionableError) {
  Logger.info(...);   // 알려진 비조치 에러 → 로컬 기록만
} else {
  Logger.error(...);  // 미지의 에러 → Sentry 전송 (미래 버그 감지)
}
```

### 대응 유형 (자연어 입력인 경우)

- **코드 버그 수정**: 로직 오류, 누락된 조건, 잘못된 상태 전이
- **타이밍/동기화 개선**: await 누락, 이벤트 순서 보장, retry 로직 추가
- **에러 핸들링 보강**: 실패 시 유저에게 적절한 피드백, 자동 복구
- **상태 동기화 개선**: 클라이언트-서버 간 상태 일관성 확보

---

## Phase 4: 구현

수정 계획에 따라 코드를 수정한다.

### 4-0. Worktree 생성

`~/.claude/skills/_shared/git-worktree.md`의 **Worktree 생성** 절차를 따른다.
prefix는 `fix`를 사용하여, 수정 대상 레포에만 worktree를 생성한다.

이후 Phase 4~6의 모든 코드 수정/읽기 작업은 `${WORKTREE_BASE}/<REPO>` 경로에서 수행한다.

### 크로스 레포 수정 시 Task List 활용

여러 레포를 수정해야 하는 경우, **TaskCreate로 레포별 작업을 태스크로 등록**한다.

**레포 간 의존성이 없는 경우:**
```
TaskCreate: "<SERVER_REPO> 로그 레벨 수정"     (pending)
TaskCreate: "<VOICE_AGENT_REPO> 에러 핸들링 수정" (pending)
→ 두 태스크를 병렬 subagent로 동시 실행
```

**레포 간 의존성이 있는 경우:**
```
TaskCreate: "<SERVER_REPO> API 응답 형식 수정"   (pending)
TaskCreate: "<APP_REPO> API 호출부 수정"     (pending, blockedBy: 위 태스크)
→ blockedBy로 의존성을 명시하고, 선행 태스크 완료 후 후행 태스크 실행
```

**혼합된 경우:**
```
TaskCreate: "<SERVER_REPO> API 수정"                          (pending)
TaskCreate: "<APP_REPO> API 호출부 수정"                   (pending, blockedBy: 서버)
TaskCreate: "<VOICE_AGENT_REPO> 독립적 로깅 수정"             (pending)
→ 서버 + voice-agent는 병렬 실행, flutter는 서버 완료 후 실행
```

각 태스크는 subagent에 배정하여 실행하며, 시작 시 `in_progress`, 완료 시 `completed`로 상태를 업데이트한다.

### 수정 subagent 지시 사항

각 수정 subagent에게는 **해당 레포 페르소나를 프롬프트 맨 앞에 포함**하고 아래를 지시한다:
1. **Worktree 경로에서 작업한다**: `${WORKTREE_BASE}/<REPO_NAME>` 경로의 파일을 수정한다. 원본 레포 경로를 수정하지 않는다.
2. 수정에 사용하는 API/패턴의 **공식 문서를 WebSearch/WebFetch로 확인**한다.
   - 정확한 함수 시그니처, 파라미터, 반환값 확인
   - 공식 예제 코드와 비교하여 올바른 사용법인지 검증
   - 해당 버전에서의 breaking change, 알려진 이슈 확인
3. 수정 코드를 작성한다.
4. 수정이 올바른지 코드 레벨에서 재확인한다:
   - 변경된 조건문/로직이 의도한 시나리오를 정확히 커버하는지 검증
   - 변경된 코드의 전후 흐름이 자연스러운지 확인
   - **실행 순서(ordering) 검증**: 비동기 호출, 이벤트 리스너, 콜백 체인에서 실행 순서가 의도대로인지 확인한다. 특히 iOS/Android 네이티브 API는 호출 순서에 따라 동작이 달라지는 경우가 많다 (예: setCategory → overrideOutputAudioPort 순서)
5. 이슈와 무관한 코드를 변경하지 않는다.

메인 컨텍스트에서 모든 태스크 완료를 확인하고 정합성을 점검한다.

### Phase 4 → 5 Handoff

Before proceeding to Phase 5, compile the following **PHASE_4_CONTEXT** block.
Pass this block to all Phase 5 verification subagents.

```
PHASE_4_CONTEXT:
- Original issue: [error message or symptom]
- Root cause: [identified cause from Phase 2]
- Scenarios addressed: [which A/B/C scenarios this fix covers]
- Worktree info:
  - WORKTREE_ID: [worktree identifier]
  - WORKTREE_BASE: [worktree base path]
  - Repos: [list of repos with worktree paths]
- Modified files:
  - [worktree_path]/[file:line]: [what was changed and why]
  - ...
- Git diff: [full diff output of all changes, run in each worktree]
- Fix logic: [explanation of how the fix resolves each scenario]
```

---

## Phase 5: 검증 분석

수정된 코드를 바탕으로 검증 분석을 수행한다.

### 필수 검증 (항상 실행)
```
[병렬 실행]
├── Explore subagent (완전성 검증자 페르소나) → 문제 해결 완전성 + 기타 사이드이펙트 검증
├── Explore subagent (동시성/DB 전문가 페르소나) → DB 트랜잭션/Lock + uvicorn 멀티워커 동시성 검증
└── Explore subagent (플랫폼 안전성 검증자 페르소나) → iOS/Android 플랫폼별 동작 차이 + 네이티브 API 안전성 검증 (모바일 앱 변경 시)
```

### 선택 검증 (해당 시에만 실행)
```
├── Explore subagent (비용 분석가 페르소나)   → 외부 API 호출이 추가/변경되는 경우만
└── Explore subagent (성능 분석가 페르소나)   → 요청 처리 경로에 동기 블로킹/추가 IO가 있는 경우만
```

각 subagent에게 **해당 검증 페르소나를 프롬프트 맨 앞에 포함**하고, **수정 전후 코드의 diff**와 **worktree 내 변경 대상 파일 경로** (`${WORKTREE_BASE}/<REPO>`)를 제공하여 해당 검증 관점에서 분석하도록 지시한다. 검증 시 코드를 읽을 때는 worktree 경로에서 읽는다.

### 5-1. 문제 해결 완전성 (subagent 1)
- 수정이 Phase 1에서 식별한 모든 시나리오를 커버하는가?
- Sentry 입력: 수정 후 해당 로그가 Sentry에 더 이상 찍히지 않는가? 조건 분기가 정확한가?
- 자연어 입력: 유저가 보고한 증상이 이 수정으로 해결되는가?
- 근본 원인이 해결되는가? 증상만 가리는 것은 아닌가?
- 다른 기능에 대한 regression 가능성
- 에러 핸들링 체인 변경으로 인한 영향 (fallback 동작 변경 등)
- 로그 레벨 변경 시 모니터링/알럿에 미치는 영향
- 위 항목 외에 발견되는 잠재적 사이드이펙트도 모두 나열

### 5-2. 외부 서비스 비용 (subagent 2)
- 수정으로 인해 외부 API 호출이 추가/증가하는가?
  - STT/LLM/TTS 프로바이더 (OpenAI, Google, Anthropic, Groq, Azure, AssemblyAI)
  - Google Cloud 서비스 (Pub/Sub, Firestore, Cloud Storage, Speech)
  - LiveKit 서버
- 변경 대상 코드 주변의 API 호출 패턴을 읽고, 호출 빈도 변화를 추정

### 5-3. DB 트랜잭션/Lock + 멀티워커 동시성 (subagent 3)
- Tortoise ORM 쿼리에서 트랜잭션 경합이 발생할 수 있는가?
- SELECT FOR UPDATE, 데드락 가능성은 없는가?
- 벌크 쿼리가 테이블 락을 유발하지 않는가?
- 커넥션 풀(min=2, max=10) 고갈 가능성은 없는가?
- 7개 uvicorn 워커에서 동시에 같은 코드가 실행될 때 문제되는 지점이 있는가?
- 공유 상태(전역 변수, 싱글톤, 파일 I/O)에 대한 race condition은 없는가?
- APScheduler 작업이 여러 워커에서 중복 실행될 가능성은 없는가?
- in-memory 캐시나 상태가 워커 간에 불일치할 수 있는가?

### 5-4. 유저 경험 레이턴시 (subagent 4)
- 요청 처리 경로에 동기 블로킹 호출이 추가되는가?
- 추가 DB 쿼리나 외부 API 호출로 인한 응답 지연은 없는가?
- voice-agent의 음성 파이프라인(VAD→STT→LLM→TTS) 지연에 영향이 있는가?
- 클라이언트(Flutter) 쪽 UI 반응성에 영향이 있는가?

### 5-5. 시나리오 기반 End-to-End 검증

Phase 1에서 식별한 시나리오를 기반으로, 수정된 코드가 각 시나리오에서 올바르게 동작하는지 end-to-end로 추적한다.
각 시나리오에 대해: 트리거 조건 → 코드 실행 경로 → 최종 상태를 순차적으로 따라가며, 수정 전/후 동작 차이를 명시한다.
이 검증은 필수 검증 subagent 중 하나(완전성 검증자)에게 위임하거나, 시나리오가 복잡한 경우 별도 subagent를 배정한다.

### 검증 결과 종합

메인 컨텍스트에서 subagent 결과를 종합한다.

**IMPORTANT: 문제 발견 여부와 관계없이, 다음을 수행한다:**
1. **검증 결과를 사용자에게 상세히 보고한다** — 각 항목별 발견 사항, 심각도, 대응 방향 후보
2. **사용자의 의사결정을 기다린다** — 임의로 수정하지 않는다
3. 사용자가 **수정을 지시한 경우에만** Phase 3으로 돌아가 계획을 재수립한 뒤 Phase 4 → Phase 5를 다시 수행한다.
4. 사소한 조정(로그 레벨 변경 등)은 사용자가 명시적으로 승인하면 Phase 3 재진입 없이 바로 적용한다.
5. 사용자가 **수정을 거부한 경우**: worktree의 변경사항을 폐기하고 (`git checkout -- .` 또는 worktree 제거), 사용자에게 Phase 3 재분석 또는 종료 중 선택을 안내한다.

---

## Phase 6: 커밋 및 Worktree 정리

`~/.claude/skills/_shared/git-worktree.md`의 **커밋**, **후속 옵션**, **정리** 절차를 따른다.

1. 각 worktree에서 변경사항을 리뷰하고 커밋한다.
   - 커밋 메시지에 수정이 커버하는 시나리오를 간략히 명시한다 (예: "BT 해제 시 스피커 비활성화 → mic restart 후 speaker override 재적용")
2. 변경사항을 원래 브랜치에 머지한다 (기본 동작). 사용자가 PR 생성 또는 보류를 원하면 해당 옵션을 제공한다.
3. worktree와 임시 브랜치를 정리한다.

---

## 규칙

- **Sentry 입력**: Phase 1 완료 시 시나리오 분석 결과를 사용자에게 보고하고, **사용자의 승인 없이 Phase 2~4를 연속 진행한다.** Phase 5 완료 시 검증 결과를 사용자에게 보고하고 판단을 확인받는다.
- **자연어 입력**: Phase 1~4는 사용자 승인 없이 연속 진행한다. Phase 5 완료 시 검증 결과를 사용자에게 보고하고 판단을 확인받는다.
- Phase 3에서 진행 불가하거나 코드에서 확인 불가능한 맥락이 필요하면 사용자에게 보고.
- 확신이 없으면 멈추고 질문한다. 추측하지 않는다.
- 이슈와 무관한 코드를 변경하지 않는다 (no drive-by fixes).
- Sentry 로그가 없는 경우 **가설 기반 추론**이 필요하다. 가설의 근거를 코드에서 반드시 뒷받침한다.
- 가능한 많은 시나리오를 고려한다. 하나의 로그/증상이라도 여러 원인이 있을 수 있다.
- 크로스 레포 이슈인 경우, 반드시 양쪽 코드를 모두 확인한 후에 판단한다.
- **독립적인 탐색/분석 작업은 항상 병렬 subagent로 실행한다. 순차 실행은 의존성이 있을 때만 한다.**
