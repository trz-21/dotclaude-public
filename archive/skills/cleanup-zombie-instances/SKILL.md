# Cleanup Zombie Instances

MIG에서 빠졌지만 RUNNING 상태로 남아있는 좀비 인스턴스를 식별하고, SIGTERM을 보내 graceful drain 후 자동 셧다운시키는 스킬.

## Trigger

- "좀비 인스턴스 정리", "zombie cleanup", "인스턴스 정리"
- "MIG 밖 인스턴스 확인", "남아있는 인스턴스 정리"

## Parameters

- `env`: 환경 (production, dev). 기본값: production
- `project_id`: GCP 프로젝트 ID. `.env`의 `GCP_PROJECT_ID`에서 읽음
- `region`: GCP 리전. `.env`의 `GCP_REGION`에서 읽음

## Workflow

### Phase 1: 좀비 식별

1. 전체 인스턴스 목록 조회:
```bash
gcloud compute instances list \
  --project=$PROJECT_ID \
  --filter="name~<INSTANCE_PREFIX>-$ENV" \
  --format="table(name,zone.basename(),status,creationTimestamp.date())" \
  --sort-by=creationTimestamp
```

2. MIG 멤버 목록 조회:
```bash
gcloud compute instance-groups managed list-instances \
  <MIG>-$ENV \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(instance.basename())"
```

3. 두 목록을 비교하여 **RUNNING이지만 MIG에 없는 인스턴스**를 좀비로 식별

4. 결과를 테이블로 사용자에게 보여주기:
```
| 좀비 인스턴스 | Zone | 생성일 |
|---|---|---|
| instance-abc | <ZONE> | 2/20 |
```

좀비가 없으면 "좀비 인스턴스 없음"을 출력하고 종료.

### Phase 2: SIGTERM + Auto-Shutdown 적용

각 좀비 인스턴스에 SSH로 접속하여 다음 명령어 실행:

```bash
gcloud compute ssh $INSTANCE_NAME \
  --zone=$ZONE \
  --project=$PROJECT_ID \
  --command="sudo docker update --restart=no <CONTAINER> \
    && sudo docker kill --signal=SIGTERM <CONTAINER> \
    && sudo nohup bash -c 'while sudo docker inspect --format={{.State.Status}} <CONTAINER> 2>/dev/null | grep -qE \"running|restarting\"; do sleep 30; done; sudo shutdown -h now' &>/dev/null &"
```

명령어 동작:
1. `docker update --restart=no` - 컨테이너 재시작 정책 비활성화
2. `docker kill --signal=SIGTERM` - LiveKit SDK drain 모드 진입 (새 job 거부, 활성 통화 완료 대기)
3. Background 모니터 - 컨테이너 종료 감지 후 `shutdown -h now`로 VM 셧다운

### Phase 3: 결과 보고

각 인스턴스별 성공/실패 상태를 테이블로 보고:

```
| 인스턴스 | 결과 |
|---|---|
| instance-abc | SIGTERM 완료 |
| instance-def | 실패: SSH 접속 불가 |
```

## 주의사항

- SSH exit code 255 + `<CONTAINER>` 두 번 출력 = **성공** (nohup 후 SSH 세션 끊김)
- SSH 접속 불가 (port 22 실패) = 인스턴스가 이미 TERMINATED 상태일 가능성 높음
- 병렬 SSH 실행 시 sibling tool call error 발생 가능 -> 실패한 것만 순차 재시도
- 활성 통화가 있는 인스턴스는 통화 완료 후 자동 셧다운됨 (최대 1시간)

## 기존 자동화와의 관계

- **Watchdog (`<STARTUP_SCRIPT>`)**: MIG에서 빠진 지 30분 후 자동 self-drain. 단, watchdog가 죽으면 동작하지 않음 (이 스킬이 필요한 이유)
- **Cloud Function (`<CLOUD_FUNCTION>`)**: TERMINATED 인스턴스 자동 삭제. RUNNING 좀비는 처리하지 않음
- **이 스킬**: watchdog가 죽어서 남아있는 RUNNING 좀비를 수동으로 force-drain
