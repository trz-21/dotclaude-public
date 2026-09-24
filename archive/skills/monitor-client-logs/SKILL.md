---
name: monitor-client-logs
description: 어제(또는 지정 날짜)의 클라이언트 로그를 빠르게 요약하여 에러 패턴 대시보드를 제공한다.
argument-hint: [날짜(YYYY-MM-DD), 기본값=어제]
---

# Client Log Monitor

`/analyze-client-log`의 경량 버전. 코드 심층 분석 없이 **에러 패턴 집계와 트렌드**만 빠르게 보여준다.

## 입력

- `YYYY-MM-DD` 형식의 날짜 (기본값: 어제)
- `YYYY-MM-DD ~ YYYY-MM-DD` 형식의 기간도 가능

## 인프라 정보

`/analyze-client-log` 스킬과 동일한 Slack/GCS 인프라를 사용한다:
- **Slack 채널**: `#<SLACK_CHANNEL>` (ID: `<SLACK_CHANNEL_ID>`)
- **Token**: `<SLACK_USER_TOKEN>`
- **GCS 버킷**: `<BUCKET>`

---

## Phase 1: Slack 메시지 수집

```bash
# 대상 날짜를 KST 기준 Unix timestamp로 변환
# oldest = YYYY-MM-DD 00:00:00 KST
# latest = YYYY-MM-DD 23:59:59 KST

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://slack.com/api/conversations.history?channel=<SLACK_CHANNEL_ID>&oldest=<oldest>&latest=<latest>&limit=200"
```

페이지네이션으로 전체 메시지를 수집하고, 총 건수를 기록한다.

---

## Phase 2: GCS 로그 병렬 다운로드 + 집계

### 2-1. 병렬 다운로드

```bash
for path in "${GCS_PATHS[@]}"; do
  gcloud storage cat "gs://<BUCKET>/$path" > "/tmp/monitor-log-$(basename $path)" &
done
wait
```

### 2-2. 에러 패턴 집계

각 로그에서 아래 항목만 빠르게 추출한다 (전체 로그 상세 분석은 하지 않음):

| 항목 | 추출 방법 |
|------|----------|
| 플랫폼 분포 | `deviceInfo.platform` 별 count |
| 앱 버전 분포 | `deviceInfo.appVersion` 별 count |
| ERROR 로그 메시지 | `level == "error"` 인 로그의 message 수집 |
| WARNING 로그 메시지 | `level == "warning"` 인 로그의 message 수집 |
| HTTP 실패 | 4xx/5xx 응답 포함 로그 수집 |
| 통화 시간 분포 | 첫 로그~마지막 로그 시간 차이 → 구간별 count |

### 2-3. 에러 클러스터링

에러/경고 메시지를 유사도 기준으로 그룹핑한다:
- 동일한 에러 메시지 패턴 (변수 부분 제거 후 매칭)
- 각 클러스터의 발생 건수, 영향받은 고유 유저 수 집계

---

## Phase 3: 대시보드 출력

```
## Client Log Monitor: YYYY-MM-DD

### 요약
- 총 로그 건수: N건
- 플랫폼: iOS N건 / Android N건
- 앱 버전 Top 3: v1.2.3 (N건), v1.2.2 (N건), ...

### 통화 시간 분포
- < 30초: N건
- 30초 ~ 3분: N건
- 3분 ~ 10분: N건
- 10분+: N건

### 에러 패턴 (발생 빈도 순)

| # | 에러 패턴 | 건수 | 유저 수 | 심각도 |
|---|----------|------|---------|--------|
| 1 | Scheduled call ring failed | N | N | P0 |
| 2 | API request failed: POST <API_PATH> | N | N | P1 |
| 3 | ... | ... | ... | ... |

### 트렌드 (이전 데이터 있을 시)
- 전일 대비 증감: +N건 / -N건
- 신규 에러 패턴: 있음/없음

### 권장 액션
- [심각도 높은 에러가 있으면] `/analyze-client-log YYYY-MM-DD`로 코드 심층 분석 권장
- [특정 에러 급증 시] 해당 에러의 Sentry 이슈 확인 권장
```

---

## 규칙

- 이 스킬은 **집계 전용**이다. 코드 분석은 하지 않는다.
- 코드 분석이 필요하면 `/analyze-client-log` 사용을 안내한다.
- 심각도 판정 기준:
  - **P0**: 통화 자체가 불가능한 에러 (STT 실패, LiveKit 연결 실패, Room 참여 실패)
  - **P1**: 통화는 가능하나 기능 장애 (발음 분석 실패, 메트릭 전송 실패)
  - **P2**: 유저 체감 없는 에러 (fire-and-forget 실패, 로깅 실패)
