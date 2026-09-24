---
name: analyze-client-log
description: 클라이언트 로그를 Slack에서 검색하고, GCS에서 다운로드하여 코드 기반으로 분석하는 워크플로우.
argument-hint: [UUID 또는 날짜(YYYY-MM-DD)]
---

# Client Log Analysis Workflow

## 입력 정보

사용자로부터 아래 중 하나를 받는다:

### 입력 A: UUID
- user ID 또는 call ID (UUID 형식)
- 별도 기간 명시가 없으면 **최근 1주일** 이내의 로그만 대상으로 한다.

### 입력 B: 날짜
- `YYYY-MM-DD` 형식의 단일 날짜 또는 기간 (`YYYY-MM-DD ~ YYYY-MM-DD`)
- 해당 날짜에 올라온 모든 클라이언트 로그를 대상으로 한다.

## 참조 레포지토리

| 레포 | 경로 | 역할 |
|------|------|------|
| **<APP_REPO>** | `../<APP_REPO>` | **주 분석 대상** (클라이언트 코드, main 브랜치) |
| <SERVER_REPO> | `../<SERVER_REPO>` | 서버 측 참조 |
| <VOICE_AGENT_REPO> | `../<VOICE_AGENT_REPO>` | 음성 에이전트 측 참조 |

## 인프라 정보

### Slack
- **채널**: `#<SLACK_CHANNEL>` (ID: `<SLACK_CHANNEL_ID>`)
- **Token**: `<SLACK_USER_TOKEN>`
- **메시지 포맷**:
  ```
  user `<user-uuid>` call: `<call-uuid>`
  <GCS 콘솔 링크|GCS에서 보기>
  ```

### GCS
- **버킷**: `<BUCKET>`
- **오브젝트 경로**: `<user-uuid>/<call-uuid>/<timestamp>.json`
- **다운로드 명령**: `gcloud storage cat gs://<BUCKET>/<user-uuid>/<call-uuid>/<timestamp>.json`

### 로그 JSON 구조
```json
{
  "userId": "uuid",
  "deviceInfo": {"platform": "ios|android", "appVersion": "x.y.z", "buildNumber": "nnn"},
  "timestamp": "ISO-8601",
  "sessionId": "uuid",
  "callId": "uuid",
  "uploadedAt": "ISO-8601",
  "logs": [
    {"timestamp": "ISO-8601", "level": "debug|info|warning|error", "message": "..."}
  ]
}
```

---

## Phase 1: Slack 로그 검색

입력 유형에 따라 분기한다.

### 입력 유형 판별
- UUID 형식 (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) → **경로 A: UUID 검색**
- 날짜 형식 (`YYYY-MM-DD` 또는 `YYYY-MM-DD ~ YYYY-MM-DD`) → **경로 B: 날짜 검색**

---

### 경로 A: UUID 검색

#### 1-1A. Slack 검색

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://slack.com/api/search.messages?query=<UUID>%20in%3A<SLACK_CHANNEL>&count=20"
```

#### 1-2A. 기간 필터

- 메시지 `ts` (Unix timestamp)를 확인하여, 지정 기간 외의 메시지는 제외한다.
- 기본값: 최근 1주일 (현재 시간 - 7일)

---

### 경로 B: 날짜 검색

#### 1-1B. Slack 히스토리 조회

`conversations.history` API로 해당 날짜의 메시지를 가져온다.

```bash
# 날짜를 Unix timestamp로 변환
# oldest = 해당 날짜 00:00:00 KST의 Unix timestamp
# latest = 해당 날짜 23:59:59 KST의 Unix timestamp (또는 기간 종료일)

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://slack.com/api/conversations.history?channel=<SLACK_CHANNEL_ID>&oldest=<oldest>&latest=<latest>&limit=200"
```

**200건 초과 시**: `response_metadata.next_cursor`를 사용하여 페이지네이션한다.
**건수가 많을 경우** (20건 초과): 사용자에게 건수를 알리고 전체 분석 여부를 확인한다.

---

### 공통: 메시지 파싱

검색/조회 결과에서 각 메시지의 text를 파싱하여 추출한다:
- **user ID**: `` user `<uuid>` `` 패턴에서 추출
- **call ID**: `` call: `<uuid>` `` 패턴에서 추출
- **GCS 경로**: 콘솔 URL에서 버킷/오브젝트 경로 추출
  - URL 디코딩: `%2F` → `/`
  - 추출 대상: `<BUCKET>/<user-uuid>/<call-uuid>/<timestamp>.json`

### 검색 결과 정리

발견된 로그 목록을 정리한다:
```
SEARCH_RESULTS:
- 입력 유형: UUID / 날짜
- Match 1: user=<uuid>, call=<uuid>, gcs_path=<path>, slack_ts=<timestamp>
- Match 2: ...
총 N건 발견
```

검색 결과가 **0건**이면 사용자에게 보고하고 종료한다.

---

## Phase 2: GCS 로그 수집 및 1차 분류

### 2-1. 로그 다운로드

각 매치에 대해 `gcloud storage cat`으로 JSON 로그를 가져온다.

**다운로드 전략:**
- **5건 이하**: 순차 `gcloud storage cat` 실행
- **6~20건**: Bash에서 `&`로 백그라운드 병렬 다운로드 후 `wait`. 임시 파일에 저장하여 처리.
- **20건 초과**: Phase 1에서 이미 사용자 확인을 받았으므로, 병렬 다운로드 후 전체 처리.

```bash
# 병렬 다운로드 예시 (6건 이상)
for path in "${GCS_PATHS[@]}"; do
  gcloud storage cat "gs://<BUCKET>/$path" > "/tmp/client-log-$(basename $path)" &
done
wait
```

### 2-2. 로그 1차 분류

각 로그 파일에 대해 아래 정보를 추출한다:

| 항목 | 추출 방법 |
|------|----------|
| 디바이스 정보 | `deviceInfo.platform`, `appVersion`, `buildNumber` |
| 통화 시간 | 첫 로그 ~ 마지막 로그 timestamp 차이 |
| 로그 레벨 분포 | level별 count (`debug`, `info`, `warning`, `error`) |
| ERROR/WARNING 로그 | 해당 레벨의 로그 message 전체 |
| HTTP 요청 실패 | `http:` 로 시작하는 로그 중 4xx/5xx 응답 |
| 통화 종료 사유 | `endCallReason` 포함 로그 |
| LiveKit 이벤트 | `livekit_event`, `LivekitService`, `room`, `track` 키워드 포함 로그 (미디어 채널). 연결/끊김 타임스탬프 별도 기록 |
| WebSocket 이벤트 | `VoiceAgentService` 관련 로그 (신호 채널): WebSocket connected/disconnected, Server error, Sent message 등. 연결/끊김 타임스탬프 별도 기록 |
| Abnormality 모니터링 | `Abnormallity` 또는 `Abnormality` prefix 포함 debug 로그 전체. `latency_ms`, `is_waiting_welcome` 필드 추출 |
| 에러 패턴 | Exception, Error, fail, timeout, `internal_server_error` 등 키워드 포함 로그 (**레벨 무관** — debug 포함) |

### 2-3. 문제 후보 식별

1차 분류 결과에서 **비정상 패턴**을 식별한다:
- **ERROR 로그가 있는 경우** (최우선 기준)
- **debug 레벨이지만 실질적 서버 에러인 메시지** (레벨 무관으로 검출):
  - `internal_server_error`, `Server error received`, `type: error` 등 WebSocket 페이로드에서 추출된 서버 측 에러
  - `Cannot send message, not connected` 등 연결 단절 상태에서의 실패
- WARNING 로그가 있으며, 통화 종료나 기능 장애와 연관된 경우
- HTTP 4xx/5xx 응답이 있는 경우
- LiveKit 연결 실패/끊김이 있는 경우 (`ParticipantDisconnected`, `TrackUnsubscribed`)
- WebSocket 조기 종료 (통화 종료 전에 WebSocket이 먼저 끊긴 경우)
- 비정상적으로 짧은 통화 시간 (30초 미만) **AND** error/warning 로그 또는 HTTP 실패가 동반된 경우
- 반복되는 retry/reconnect 패턴 (3회 이상)
- **유저 체감 저하 후보** (error 로그 없어도 비정상 후보로 분류):
  - Abnormality 로그의 `latency_ms` > 5000ms (5초 이상 응답 지연)
  - `is_waiting_welcome: true`가 포함된 Abnormality 로그 (에이전트 재연결 대기 상태)
  - WebSocket과 LiveKit의 끊김 타임스탬프가 통화 종료 이전인 경우 (조기 단절)

**주의**: 이 채널의 모든 로그는 유저가 통화 종료 시 "오류가 발생했어요" 사유를 선택하여 업로드된 것이다. `endCallReason` 값 자체는 유저 선택이므로, **단독으로는 비정상 판정하지 않는다.** ERROR/WARNING 로그, HTTP 실패 등 실제 코드 에러와 결합된 경우에만 참조한다.

**비정상 패턴이 없는 로그**는 "정상 통화"로 분류하고 상세 분석에서 제외한다.
짧은 통화 (<30s)라도 error/warning 없이 유저가 즉시 종료한 경우는 "유저 조기 종료"로 분류한다.

### 2-4. Cross-call 동시 패턴 분석 (날짜 기반 검색 시)

여러 call이 존재할 때, 다음 패턴을 cross-call로 확인한다:

1. **동시 disconnect**: 2건 이상의 call에서 WebSocket 또는 LiveKit 끊김 타임스탬프가 동일 1분 이내에 집중 → **"서버 사이드 인시던트 의심"** 표시
2. **동시 `internal_server_error`**: 2건 이상의 call에서 동일 시간대에 발생 → 동일하게 표시
3. **서버 사이드 인시던트로 판단된 경우**: 개별 call 심층 분석보다 인시던트 시점·범위 파악을 우선하고, Phase 3에서 대표 call 1건만 심층 분석한다.

---

## Phase 3: 코드 기반 심층 분석

Phase 2에서 비정상 패턴이 식별된 로그에 대해, <APP_REPO> 코드를 참조하여 심층 분석한다.

### 3-0. 모니터링 레퍼런스 우선 참조

<APP_REPO>에 `docs/MONITORING_REFERENCE.md`가 존재하면 먼저 읽는다. 이 문서에는 에러 메시지 → 코드 위치 매핑 테이블이 포함되어 있어, Grep 없이 바로 코드 위치를 특정할 수 있다.

```
Read(path='../<APP_REPO>/docs/MONITORING_REFERENCE.md')
```

- 레퍼런스에 매칭되는 에러는 **Grep을 건너뛰고** 바로 해당 코드 위치를 Read한다.
- 레퍼런스에 없는 에러만 3-1 단계(Grep 검색)로 진행한다.

### 3-1. 로그 메시지 → 코드 매핑

비정상 로그의 message를 키워드로 <APP_REPO> 코드베이스를 검색한다.

```
[병렬 Grep - 메인 컨텍스트에서 직접 실행]
├── Grep(pattern='<error_message_keyword>', path='../<APP_REPO>')
├── Grep(pattern='<http_endpoint>', path='../<SERVER_REPO>')  (필요 시)
└── Grep(pattern='<livekit_event_keyword>', path='../<VOICE_AGENT_REPO>')  (필요 시)
```

### 3-2. 코드 흐름 추적

Grep 결과를 바탕으로, 문제가 발생한 코드 경로를 추적한다.

**단일 문제 패턴**: 메인 컨텍스트에서 직접 Read로 코드를 확인한다.

**복수 문제 패턴 또는 크로스 레포 분석 필요 시**: Explore subagent를 병렬로 실행한다.

```
[병렬 실행 - 필요한 레포만]
├── Explore subagent (<APP_REPO> 전문가 페르소나) → 클라이언트 코드 흐름 추적
├── Explore subagent (<SERVER_REPO> 전문가 페르소나) → 서버 API 응답 분석 (필요 시)
└── Explore subagent (<VOICE_AGENT_REPO> 전문가 페르소나) → 음성 에이전트 동작 분석 (필요 시)
```

#### Subagent 페르소나

**<APP_REPO> 전문가:**
> 너는 Flutter + GetX + Dio 클라이언트 전문가다.
> GetX 컨트롤러 생명주기, Dio 인터셉터 체인(TokenRefresh, Retry), Sentry Flutter SDK, LiveKit Client SDK, CallKit에 깊은 이해가 있다.
> 코드를 읽을 때 위젯 생명주기, 상태 관리 흐름, 네트워크 요청/응답 패턴, 에러 전파 경로에 집중한다.
> 작업 경로: ../<APP_REPO>

**<SERVER_REPO> 전문가:**
> 너는 FastAPI + Tortoise ORM + MySQL 백엔드 전문가다.
> uvicorn 멀티워커 환경, aiomysql 비동기 커넥션 풀, Sentry Python SDK, APScheduler, OpenTelemetry에 깊은 이해가 있다.
> 코드를 읽을 때 async/await 흐름, DB 트랜잭션 경계, 미들웨어 체인(AuthMiddleware), 에러 핸들링 패턴에 집중한다.
> 작업 경로: ../<SERVER_REPO>

**<VOICE_AGENT_REPO> 전문가:**
> 너는 Python 비동기 프로그래밍 + LiveKit Agents 프레임워크 전문가다.
> 음성 파이프라인(VAD→STT→LLM→TTS), 멀티 프로바이더 fallback 체인, WebSocket 이벤트 시스템, aiohttp 비동기 HTTP에 깊은 이해가 있다.
> 코드를 읽을 때 asyncio 흐름, 프로바이더 fallback 로직, 세션 상태 관리, 이벤트 발행/구독 패턴에 집중한다.
> 작업 경로: ../<VOICE_AGENT_REPO>

### 3-3. 문제 원인 판단

코드 추적 결과를 종합하여 각 비정상 패턴의 원인을 판단한다:

| 분류 | 기준 | 예시 |
|------|------|------|
| **클라이언트 버그** | Flutter 코드의 로직 오류 | 상태 전이 누락, 예외 미처리 |
| **서버 이슈** | API 응답 오류, 타임아웃 | 500 응답, 느린 응답, `internal_server_error` |
| **네트워크 이슈** | 연결 불안정, 끊김 | WiFi→LTE 전환, SocketException 타임아웃 |
| **LiveKit 이슈** | 미디어 채널 단절 (WebSocket은 정상) | Room 연결 실패, 트랙 손실, ParticipantDisconnected |
| **WebSocket 이슈** | 신호 채널 단절 (LiveKit은 정상 또는 연동 끊김) | VoiceAgentService disconnect, 서버 에러 수신 후 WS 종료 |
| **복합 단절** | LiveKit + WebSocket 동시 끊김 | 서버 재시작, 인프라 이벤트, 네트워크 전환 |
| **유저 행동** | 유저의 의도적/비의도적 동작 | 강제 종료, 빠른 전환 |
| **외부 요인** | 프로바이더 장애, OS 제약 | STT 서비스 장애, iOS 백그라운드 제한 |

---

## Phase 4: 종합 보고

분석 결과를 사용자에게 보고한다.

### 보고 형식

```
## 분석 결과 요약

### 검색 정보
- 입력: <UUID 또는 날짜>
- 매칭 유형: user ID / call ID / 날짜 범위
- 발견 건수: N건
- 분석 기간: YYYY-MM-DD ~ YYYY-MM-DD

### 디바이스 정보
- Platform: ios/android
- App Version: x.y.z (build nnn)

### 통화별 분석

#### Call 1: <call-uuid>
- 시간: YYYY-MM-DD HH:MM ~ HH:MM (N분 N초)
- 상태: 정상 / 비정상
- [비정상인 경우]
  - 문제 패턴: <식별된 문제>
  - 관련 로그:
    - [level] timestamp: message
    - ...
  - 코드 위치: <file:line> — <설명>
  - 원인 분류: 클라이언트 버그 / 서버 이슈 / 네트워크 이슈 / ...
  - 원인 분석: <코드 근거를 포함한 상세 분석>

#### Call 2: ...

### 종합
- 정상 통화: N건
- 비정상 통화: N건
  - 클라이언트 버그: N건
  - 서버 이슈: N건
  - ...
- 공통 패턴: <여러 통화에 걸쳐 반복되는 패턴이 있으면 기술>
- 인시던트 의심 시간대: <동시 disconnect/error가 집중된 타임스탬프 범위> (해당 시 기재)
- UX 영향 요약: <레이턴시 이슈, 에이전트 침묵 구간, WebSocket 끊김 후 유저 대기 시간 등> (해당 시 기재)
- 권장 조치: <수정이 필요한 경우 요약>
```

---

## 규칙

- 이 스킬은 **읽기 전용 분석**이다. 코드를 수정하지 않는다.
- 코드 수정이 필요하다고 판단되면, 사용자에게 보고하고 `/fix-issue` 스킬 사용을 제안한다.
- 확신이 없으면 추측하지 않고, 근거가 부족함을 명시한다.
- 로그의 개인정보(user ID 등)는 분석 컨텍스트에서만 사용하고, 불필요하게 노출하지 않는다.
- GCS 다운로드 실패 시 해당 로그를 건너뛰고 다음을 진행한다. 실패 사유를 보고한다.
- **독립적인 탐색 작업은 항상 병렬 subagent로 실행한다.**
