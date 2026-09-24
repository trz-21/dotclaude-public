---
name: analyze-agent-logs
description: LiveKit Voice Agent의 GCP 프로덕션 로그를 조회하여 문제 상황을 요약하는 워크플로우. call_id(UUID) 또는 날짜 기간을 입력으로 받는다.
argument-hint: [call-id-uuid 또는 날짜-기간]
allowed-tools: Bash(gcloud *), Bash(jq *), Read, Grep, Glob, Task
---

# Agent Log Analysis Workflow

## 개요

voice-agent의 GCP Cloud Logging 프로덕션 로그를 조회하여, 에이전트에서 발생한 문제를 분석하고 요약한다.

## 입력

사용자로부터 아래 중 하나를 받는다:

| 입력 유형 | 예시 | 설명 |
|-----------|------|------|
| **Call ID** | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | 특정 통화의 전체 로그 조회 |
| **날짜** | `2026-02-13`, `오늘`, `어제` | 해당 일자의 에러/경고 로그 조회 |
| **날짜 범위** | `2026-02-10~2026-02-13`, `최근 3일` | 기간 내 에러/경고 로그 조회 |

## GCP 로그 쿼리 레퍼런스

### 기본 설정

```
GCP_PROJECT_ID = <GCP_PROJECT_ID>
RESOURCE_FILTER = resource.type="gce_instance"
PRODUCTION_FILTER = logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver"
```

> **참고**: `gcplogs-docker-driver`는 Docker 컨테이너의 앱 로그만 포함한다.
> `google_metadata_script_runner` (startup-script 중복 로그)를 자동으로 제외하므로,
> 별도의 startup-script 중복 제거가 불필요하다.

### Call ID로 전체 로그 조회

```bash
gcloud logging read \
  'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND jsonPayload.message=~"CALL_ID"' \
  --project=<GCP_PROJECT_ID> --format=json \
  | jq -r '.[] | "\(.timestamp) | \(.jsonPayload.message // .textPayload // "N/A" | .[0:300])"' | sort
```

### 시간 범위 에러/경고 로그

```bash
gcloud logging read \
  'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND (severity>=ERROR OR jsonPayload.message=~"error|Error|failed|Traceback|\[P0\]|\[P1\]")' \
  --project=<GCP_PROJECT_ID> --format=json \
  | jq -r '.[] | "\(.timestamp) | \(.severity // "INFO") | \(.jsonPayload.message // .textPayload // "N/A" | .[0:300])"' | sort
```

### 세션 시작/종료 조회

```bash
# 세션 시작
gcloud logging read \
  'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND jsonPayload.message=~"Session started - call_id"' \
  --project=<GCP_PROJECT_ID> --format=json \
  | jq -r '.[] | "\(.timestamp) | \(.jsonPayload.message | .[0:200])"' | sort

# 세션 종료
gcloud logging read \
  'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND jsonPayload.message=~"Call ended - call_id"' \
  --project=<GCP_PROJECT_ID> --format=json \
  | jq -r '.[] | "\(.timestamp) | \(.jsonPayload.message | .[0:200])"' | sort
```

### 주요 로그 패턴

| 로그 메시지 패턴 | 의미 |
|-----------------|------|
| `Session started - call_id: {uuid}` | 세션 시작 |
| `Call ended - call_id: {uuid}, duration: Xs, words: N` | 세션 정상 종료 |
| `Call ended via API - call_id: {uuid}` | API를 통한 세션 종료 |
| `[P0] System prompt leak detected` | 시스템 프롬프트 노출 (Critical) |
| `[P0] All STT providers failed` | 모든 STT 실패 (Critical) |
| `[P1] Abnormal language detected` | 비정상 언어 응답 (High) |
| `[P1] Failed to create call_chat` | 대화 기록 실패 (High) |
| `no response from servers` | Agent dispatch 실패 (보통 무영향) |
| `failed to connect to livekit` | WebSocket 연결 끊김 (자동 재연결) |
| `AgentSession isn't running` | 종료 후 지연 이벤트 (무영향) |
| `no worker is available` | Worker 부족 (보통 무영향) |
| `error reading data channel` | 연결 종료 시 정상 발생 (무영향) |

### 에러 심각도 분류

| 심각도 | 기준 | 예시 |
|--------|------|------|
| **P0 (Critical)** | 서비스 불가 | 시스템 프롬프트 노출, 모든 STT 실패, WebRTC 완전 실패 |
| **P1 (High)** | 핵심 기능 장애 | call_chat 생성 실패, 비정상 언어 응답 |
| **P2 (Medium)** | 개별 provider 실패 | STT/LLM/TTS fallback 동작 |
| **Known Non-issue** | 정상 동작 중 발생 | `no response from servers`, `error reading data channel` |

---

## Phase 1: 입력 파싱

### 1-1. 입력 유형 판별

```
UUID 패턴 ([a-f0-9-]{36}) → Call ID
날짜 문자열 (YYYY-MM-DD, 오늘, 어제, 최근 N일 등) → 날짜/기간
```

### 1-2. 시간 범위 결정

| 입력 | START_TIME | END_TIME |
|------|-----------|----------|
| Call ID | 불필요 (call_id 필터로 충분) | 불필요 |
| `2026-02-13` | `2026-02-13T00:00:00Z` | `2026-02-14T00:00:00Z` |
| `오늘` | 오늘 `T00:00:00Z` | 내일 `T00:00:00Z` |
| `어제` | 어제 `T00:00:00Z` | 오늘 `T00:00:00Z` |
| `최근 N일` | N일 전 `T00:00:00Z` | 내일 `T00:00:00Z` |
| `A~B` | `AT00:00:00Z` | `B+1일T00:00:00Z` |

**KST 보정**: 사용자 입력이 KST 기준이므로, UTC 변환을 적용한다 (KST = UTC+9).
- `오늘 2026-02-13 KST` → START: `2026-02-12T15:00:00Z`, END: `2026-02-13T15:00:00Z`

---

## Phase 2: 로그 수집

입력 유형에 따라 분기한다.

### 경로 A: Call ID 기반

```bash
gcloud logging read 'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND jsonPayload.message=~"CALL_ID"' \
  --project=<GCP_PROJECT_ID> --format=json
```

수집한 로그를 시간순으로 정렬하고, 세션 라이프사이클을 재구성한다:
1. **세션 시작**: `Session started` 로그에서 call_id, user_id 추출
2. **대화 흐름**: STT/LLM/TTS 관련 로그로 대화 진행 추적
3. **에러/경고**: severity>=WARNING 또는 에러 키워드 포함 로그 추출
4. **세션 종료**: `Call ended` 로그에서 duration, word_count 추출
5. **비정상 종료**: 세션 시작은 있으나 종료가 없는 경우 식별

### GCP severity vs 앱 에러 태그

GCP `severity` 필드(ERROR/WARNING)는 인프라 수준에서 설정되며, 앱 레벨의 에러 심각도와 일치하지 않는다. 앱은 `jsonPayload.message` 본문에 `[P0]`, `[P1]` 태그를 삽입한다. 따라서 에러 조회 시 `severity>=ERROR`만으로는 부족하고, 반드시 메시지 본문 키워드 검색(`jsonPayload.message=~"error|Error|failed|Traceback|\\[P0\\]|\\[P1\\]"`)을 병행해야 한다.

### 경로 B: 날짜/기간 기반

**순차 실행:**

```
① 에러/경고 로그 수집 (Bash)
  gcloud logging read \
    'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND (severity>=ERROR OR jsonPayload.message=~"error|Error|failed|Traceback|\[P0\]|\[P1\]")' \
    --project=<GCP_PROJECT_ID> --format=json

② 세션 건강성 체크 (Bash) — ①과 병렬 가능
  # 시작된 세션 수
  gcloud logging read \
    'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND jsonPayload.message=~"Session started - call_id"' \
    --project=<GCP_PROJECT_ID> --format=json \
    | jq -r '[.[] | .jsonPayload.message | capture("call_id: (?<id>[a-f0-9-]+)") | .id] | unique | length'

  # 종료된 세션 수
  gcloud logging read \
    'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND jsonPayload.message=~"Call ended - call_id"' \
    --project=<GCP_PROJECT_ID> --format=json \
    | jq -r '[.[] | .jsonPayload.message | capture("call_id: (?<id>[a-f0-9-]+)") | .id] | unique | length'
```

**주의**: `gcplogs-docker-driver` logName 필터를 사용하면 startup-script 중복이 자동 제거된다. 만약 logName 필터 없이 조회할 경우, call_id 기준 `unique` 필터를 반드시 적용한다.

---

## Phase 3: 로그 분석

### 3-1. 에러 분류

수집된 로그를 아래 기준으로 분류한다:

```
[각 로그 라인에 대해]
├── [P0] 태그 포함? → P0 (Critical)
├── [P1] 태그 포함? → P1 (High)
├── severity=ERROR + 알려진 non-issue 패턴? → Known Non-issue
├── severity=ERROR + 기타? → P2 (Medium)
└── severity=WARNING? → Warning (참고)
```

### 3-2. 세션별 그룹화 (날짜/기간 기반인 경우)

에러 로그에서 call_id를 추출하여, 어떤 세션에서 어떤 문제가 발생했는지 그룹화한다.

```bash
# call_id 추출 패턴 (macOS 호환 — grep -oP 대신 grep -oE 사용)
jq -r '.[] | .jsonPayload.message' | grep -oE '"call_id"[: ]+"[a-f0-9-]{36}"' | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
# 또는 plain text 형식
jq -r '.[] | .jsonPayload.message' | grep -oE 'call_id[=: ]+[a-f0-9-]{36}' | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
```

### 3-3. 패턴 분석

- **반복 패턴**: 같은 에러가 여러 세션에서 반복되는지
- **시간대 집중**: 특정 시간대에 에러가 집중되는지
- **provider 장애**: 특정 STT/LLM/TTS provider에 에러가 집중되는지
- **세션 미종료**: 시작은 있으나 종료가 없는 세션 (비정상 종료)

### 3-4. 유저 영향 검증 (User Impact Verification)

P2로 분류된 에러는 반드시 **에러 발생 후 세션이 정상 동작했는지** 검증해야 한다. `Call ended` 존재 여부만으로는 부족하다 — 세션이 종료되었더라도 에러 이후 에이전트가 무응답 상태였을 수 있다.

**검증 절차:**

1. 에러가 발생한 세션의 `job_id`를 추출한다.
2. 해당 세션의 전체 로그를 조회하여, **에러 시점 전후의 STT/TTS 활동**을 확인한다:

```bash
# 에러 세션의 전체 타임라인 조회 후 STT/TTS/Error/Call ended만 필터
gcloud logging read 'resource.type="gce_instance" AND logName="projects/<GCP_PROJECT_ID>/logs/gcplogs-docker-driver" AND timestamp>="START_TIME" AND timestamp<="END_TIME" AND jsonPayload.message=~"JOB_ID"' \
  --project=<GCP_PROJECT_ID> --format=json \
  | jq -r '[.[] | {ts: .timestamp, msg: (.jsonPayload.message // "N/A" | .[0:250])}] | sort_by(.ts) | .[] | "\(.ts) | \(.msg)"' \
  | grep -E "Error|STT used|TTS used|Call ended|Session started"
```

3. 아래 기준으로 유저 영향을 판정한다:

| 에러 후 패턴 | 판정 | 설명 |
|-------------|------|------|
| STT/TTS 정상 교대 지속 | **무영향** | 에러가 발생했으나 회복됨 |
| STT만 계속, TTS 없음 | **유저 영향 있음** | 유저는 말하지만 에이전트 무응답 |
| 에러 후 장시간 (>30s) 활동 없음 → API 종료 | **유저 영향 있음** | 에이전트 먹통 후 강제 종료 |
| 에러 직후 (<10s) 정상 종료 | **경미** | 세션 막바지에 발생 |

**중요**: `Call ended` 로그가 있다고 "정상"이 아니다. `Call ended via API`는 서버 측 강제 종료일 수 있으며, 에러 후 에이전트가 침묵한 채 시간이 경과하다 종료된 것일 수 있다. 반드시 에러 이후의 TTS 존재 여부를 확인한다.

### 3-5. Known Non-issue 필터링

아래 패턴은 **정상 동작** 중 발생하는 로그이므로, 문제 요약에서 별도 섹션으로 분리한다:

| 패턴 | 이유 |
|------|------|
| `no response from servers` | 다른 agent가 처리함 |
| `failed to connect to livekit` | 자동 재연결됨 |
| `AgentSession isn't running` | 세션 종료 후 지연 이벤트 |
| `no worker is available` (JT_PUBLISHER/JT_PARTICIPANT) | 정상 동작 |
| `error reading data channel` | 연결 종료 시 정상 발생 |
| `could not restart participant` | 재연결 시도 실패 (해당 유저만) |
| `process did not exit in time, killing process` | 세션 정상 종료 후 프로세스가 1시간 뒤 kill됨. 리소스 정리 이슈일 뿐 유저 무영향 |

---

## Phase 4: 보고서 작성

분석 결과를 아래 형식으로 사용자에게 보고한다.

### Call ID 기반 보고서

```markdown
## Call Session Analysis: {CALL_ID}

### Session Overview
- **Call ID**: {call_id}
- **User ID**: {user_id}
- **시작**: {start_time} (KST)
- **종료**: {end_time} (KST) / 비정상 종료
- **통화 시간**: {duration}초
- **단어 수**: {word_count}

### Issues Found

#### P0 (Critical)
- [{timestamp}] {에러 내용}

#### P1 (High)
- [{timestamp}] {에러 내용}

#### P2 (Medium)
- [{timestamp}] {에러 내용}

### Session Timeline
{시간순 주요 이벤트 요약}

### Known Non-issues (참고)
- {무영향 로그 요약}
```

### 날짜/기간 기반 보고서

```markdown
## Agent Log Analysis: {기간}

### Overview
- **기간**: {start_date} ~ {end_date} (KST)
- **총 세션 수**: {started} (시작) / {ended} (종료)
- **미종료 세션**: {started - ended}개
- **에러 발생 세션**: {error_session_count}개

### Issues by Severity

#### P0 (Critical) — {count}건
| 시간 | Call ID | 내용 |
|------|---------|------|
| {timestamp} | {call_id} | {에러 요약} |

#### P1 (High) — {count}건
| 시간 | Call ID | 내용 |
|------|---------|------|
| {timestamp} | {call_id} | {에러 요약} |

#### P2 (Medium) — {count}건
{에러 패턴별 요약 — 개별 건 나열 대신 패턴으로 그룹화}

### Error Patterns
- **패턴 1**: {설명} — {N}회 발생
- **패턴 2**: {설명} — {N}회 발생

### Affected Sessions Detail
{에러가 발생한 각 세션의 1줄 요약}

### Known Non-issues (참고)
{무영향 로그 패턴별 건수}
```

---

## 규칙

- 이 스킬은 **읽기 전용**이다. 코드를 수정하지 않는다.
- Git worktree를 생성하지 않는다.
- `gcloud` 명령어에 `--limit`을 사용하지 않는다. 전체 조회 후 `jq`로 필터링한다. 단, timeout이 발생하면 시간 범위를 분할하여 페이징한다.
- `logName` 필터(`gcplogs-docker-driver`)를 사용하면 startup-script 중복 로그가 자동으로 제외된다. LiveKit 서버 로그(`error reading data channel` 등)도 별도 logName이므로 구분 가능하다.
- GCP 로그의 timestamp는 UTC이다. 사용자에게 보고할 때는 **KST (UTC+9)**로 변환한다.
- 에러와 non-issue를 명확히 구분한다. 실제 문제만 강조하고, 정상 동작 로그는 별도 참고 섹션으로 분리한다.
- `gcloud` 인증이 안 되어 있으면 사용자에게 `gcloud auth login`을 안내한다.
- 대량 로그 조회 시 timeout이 발생하면 시간 범위를 **4시간 단위**로 분할하여 재시도한다. 예: 24시간 조회가 timeout되면 `00:00~04:00`, `04:00~08:00`, ... 6개 구간으로 나눠 순차 조회 후 결과를 합친다.
