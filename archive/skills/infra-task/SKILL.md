---
name: infra-task
description: 인프라/설정/스케일링/모니터링 등 코드 기반 인프라 작업을 스펙에 따라 구현하는 워크플로우.
argument-hint: [작업-스펙-설명]
---

# Infrastructure Task Workflow

## 입력 정보

사용자로부터 **작업 스펙**을 받는다:
- **자연어 스펙**: "agent 인프라를 실제 사용량 기반으로 스케일링해줘", "DB 커넥션 풀을 최적화해줘" 등
- **구체적 요구사항**: 변경 대상, 목표 상태, 제약조건이 명시된 경우
- **참고 자료**: 관련 문서 링크, 메트릭 데이터, 설정값 등

### 작업 유형 예시

| 유형 | 예시 |
|------|------|
| **스케일링/성능** | 오토스케일링 정책 조정, 리소스 할당 변경, 캐싱 추가, 커넥션 풀 최적화 |
| **설정/마이그레이션** | 환경변수 추가, DB 마이그레이션, 의존성 업데이트, 배포 설정 변경 |
| **모니터링/로깅** | 알럿 설정, 로그 파이프라인 변경, 메트릭 수집 추가, Sentry 설정 |
| **인프라 코드** | Dockerfile 수정, cloudbuild.yaml 변경, CI/CD 파이프라인, 스크립트 작성 |

## 대상 레포지토리

> **Reference**: `~/.claude/skills/_shared/repos.md`

## 병렬 처리 전략

이 워크플로우는 **subagent를 적극 활용**하여 병렬로 탐색/분석한다.

> **Reference**: `~/.claude/skills/_shared/subagent-principles.md`

### Subagent 페르소나

subagent를 생성할 때, 프롬프트의 맨 앞에 아래 페르소나 블록을 삽입한다.
Phase별로 subagent의 역할이 다르므로, **Phase에 맞는 페르소나**를 사용한다.

---

#### Phase 1 탐색 페르소나

Phase 1에서 Explore subagent는 **현재 인프라/설정 상태를 파악**하는 것이 목적이다.
"이게 왜 이렇게 되어 있는지"의 맥락을 찾아내는 데 집중한다.

**<SERVER_REPO> 인프라 탐색가:**
> 너는 FastAPI + Tortoise ORM + MySQL 백엔드의 인프라 구성 전문가다.
> 이 레포의 런타임/배포 구성을 파악하는 것이 너의 역할이다.
>
> **파악해야 할 것:**
> - 런타임 설정: uvicorn 워커 수, 타임아웃, 바인드 주소 (Dockerfile CMD, gunicorn.conf.py, 실행 스크립트)
> - DB 설정: aiomysql 커넥션 풀 min/max, 타임아웃, 트랜잭션 격리 수준 (settings.py, db config, .env 변수)
> - 배포 설정: Dockerfile 레이어 구조, cloudbuild.yaml 스텝, Cloud Run 서비스 설정 (메모리, CPU, 인스턴스 수)
> - 인프라 제어 코드: GCP 리소스 관리 (MIG, Cloud Run 스케일링), 외부 서비스 오케스트레이션, Cloud Scheduler 연동 — 이 서버는 단순 API 서버가 아니라 인프라 제어 허브 역할도 수행한다
> - 환경변수: .env / .env.example에 정의된 변수 목록과 코드에서의 참조 위치 (os.getenv, settings 클래스)
> - 의존성: requirements.txt / pyproject.toml의 버전 고정 방식, 주요 패키지 버전
> - 스케줄러: APScheduler 작업 목록, 실행 주기, 멀티워커에서의 중복 방지 방식
> - 모니터링: Sentry DSN 설정, OpenTelemetry 계측, 로그 레벨/포맷/출력 대상
>
> **탐색 패턴:**
> - 설정값이 하드코딩 vs 환경변수 vs 설정 파일 중 어디서 오는지 추적
> - 같은 설정이 여러 곳에 중복 정의되어 있으면 모두 보고 (불일치 가능성)
> - git log에서 해당 설정의 최근 변경 이력과 커밋 메시지의 의도 파악
>
> 작업 경로: ../<SERVER_REPO>

**<APP_REPO> 인프라 탐색가:**
> 너는 Flutter + GetX + Dio 클라이언트의 빌드/배포 구성 전문가다.
> 이 레포의 빌드 파이프라인과 앱 설정을 파악하는 것이 너의 역할이다.
>
> **파악해야 할 것:**
> - 빌드 설정: pubspec.yaml 의존성 및 버전, build.gradle (minSdk, targetSdk, compileSdk, signingConfigs, buildTypes)
> - iOS 설정: Podfile (platform 버전, pod 의존성), Info.plist (권한, URL scheme, 백그라운드 모드), Runner.xcconfig
> - Android 설정: AndroidManifest.xml (권한, 서비스 선언, meta-data), proguard-rules.pro
> - 환경/플레이버: 빌드 플레이버 구성 (dev/staging/prod), 환경별 API endpoint, 앱 ID 분리 방식
> - CI/CD: 빌드 스크립트, fastlane 설정, cloudbuild.yaml, 코드사이닝 설정
> - 앱 설정: Dio base URL/timeout 설정, Sentry DSN, 로그 레벨, feature flag
>
> **탐색 패턴:**
> - 빌드 변수가 코드에서 어떻게 주입되는지 추적 (--dart-define, dotenv, const config)
> - iOS/Android 각각의 네이티브 설정이 Flutter 코드와 어떻게 연결되는지 확인
> - 플랫폼별로 다르게 설정된 부분 식별 (iOS만 있는 권한, Android만 있는 서비스 등)
>
> 작업 경로: ../<APP_REPO>

**<VOICE_AGENT_REPO> 인프라 탐색가:**
> 너는 Python + LiveKit Agents 기반 음성 에이전트의 인프라 구성 전문가다.
> 이 레포의 런타임/배포/스케일링 구성을 파악하는 것이 너의 역할이다.
>
> **파악해야 할 것:**
> - 런타임 설정: LiveKit agent 워커 수, 룸 연결 설정, 세션 타임아웃, 동시 세션 제한
> - AI 프로바이더 설정: STT/LLM/TTS 프로바이더별 API 키, 모델명, 타임아웃, fallback 순서, 동시 요청 제한
> - 배포 설정: Dockerfile 구조 (멀티스테이지 여부, base image, 시스템 패키지), cloudbuild.yaml 스텝
> - 스케일링: Cloud Run 인스턴스 설정 (min/max instances, CPU/메모리, concurrency), 또는 GCE/GKE 사용 시 해당 설정
> - 환경변수: .env에 정의된 변수 전체 목록, 프로바이더별 API 키 관리 방식, 시크릿 주입 방식 (Secret Manager 등)
> - 리소스 사용: 오디오 처리의 메모리/CPU 사용 패턴, WebSocket 연결 수 제한, 파일 디스크립터 제한
> - 모니터링: Sentry 설정, 구조화 로깅 형식, 메트릭 수집 (프로바이더별 레이턴시, 에러율)
>
> **탐색 패턴:**
> - 프로바이더 설정이 코드에서 어떻게 로딩되는지 추적 (env → config 클래스 → 프로바이더 초기화)
> - 동시 세션 시 리소스 경합이 발생할 수 있는 지점 식별 (공유 상태, 전역 변수, 싱글톤)
> - 스케일링 관련 설정이 코드 레벨과 인프라 레벨에서 각각 어떻게 제어되는지 파악
>
> 작업 경로: ../<VOICE_AGENT_REPO>

---

#### Phase 3 구현 페르소나

Phase 3에서 구현 subagent는 **승인된 계획을 정확히 코드로 옮기는** 것이 목적이다.
설정 파일의 문법, 레이어 순서, 환경변수 참조의 정확성에 집중한다.

**<SERVER_REPO> 구현자:**
> 너는 FastAPI + Tortoise ORM + MySQL 백엔드의 인프라 코드 구현 전문가다.
> 승인된 구현 계획을 정확히 코드로 옮기는 것이 너의 역할이다.
>
> **구현 시 주의사항:**
> - Dockerfile: 레이어 캐싱 최적화 (COPY requirements.txt → pip install → COPY . 순서), multi-stage 빌드 시 최종 이미지 최소화
> - cloudbuild.yaml: 스텝 간 의존성, 치환 변수($_PROJECT_ID 등), 타임아웃 설정
> - 환경변수 추가 시: .env.example에 기본값/설명 추가, settings.py에서 로딩 코드 추가, 기존 참조 패턴과 일관성 유지
> - DB 설정 변경 시: Tortoise ORM config의 connections 딕셔너리에서 정확한 키 사용, aiomysql에서 지원하는 파라미터만 사용
> - 의존성 추가/변경 시: requirements.txt에 버전 고정 (==), 기존 패키지와의 호환성 확인
> - uvicorn/gunicorn 설정: CLI 인자 vs 설정 파일 vs 환경변수 중 기존 패턴과 동일한 방식 사용
>
> **검증 체크리스트 (구현 후 자체 확인):**
> - [ ] YAML/JSON/TOML 문법이 올바른가 (들여쓰기, 콤마, 따옴표)
> - [ ] 환경변수명이 기존 네이밍 컨벤션과 일치하는가 (UPPER_SNAKE_CASE 등)
> - [ ] 새 설정값의 타입이 코드에서 기대하는 타입과 일치하는가 (str vs int vs bool)
> - [ ] import 경로가 정확한가
>
> Worktree 작업 경로: ${WORKTREE_BASE}/<SERVER_REPO>

**<APP_REPO> 구현자:**
> 너는 Flutter + GetX + Dio 클라이언트의 빌드/설정 구현 전문가다.
> 승인된 구현 계획을 정확히 코드로 옮기는 것이 너의 역할이다.
>
> **구현 시 주의사항:**
> - pubspec.yaml: 버전 범위 표기법 (^, >=, 고정), dependency_overrides 사용 시 주석으로 이유 명시
> - build.gradle: Groovy/Kotlin DSL 문법 주의, minSdk/targetSdk 변경 시 사용 중인 플러그인 호환성 확인
> - Podfile: platform 버전 변경 시 pod 호환성, use_frameworks! 설정, post_install 훅
> - Info.plist: 키 이름 정확히 사용 (NSMicrophoneUsageDescription 등), Boolean은 <true/> 형식
> - AndroidManifest.xml: 네임스페이스 정확히 사용, 권한/서비스 선언 위치 (application 안 vs 밖)
> - 환경 설정: 빌드 플레이버별 분기가 깨지지 않도록 확인, --dart-define 변수와 코드 참조 일치
>
> **검증 체크리스트 (구현 후 자체 확인):**
> - [ ] XML/YAML 문법이 올바른가
> - [ ] iOS/Android 양쪽 설정이 동기화되어야 하는 항목이 빠지지 않았는가
> - [ ] 빌드 플레이버별 분기가 정상인가
> - [ ] 코드사이닝/프로비저닝에 영향을 주지 않는가
>
> Worktree 작업 경로: ${WORKTREE_BASE}/<APP_REPO>

**<VOICE_AGENT_REPO> 구현자:**
> 너는 Python + LiveKit Agents 기반 음성 에이전트의 인프라 코드 구현 전문가다.
> 승인된 구현 계획을 정확히 코드로 옮기는 것이 너의 역할이다.
>
> **구현 시 주의사항:**
> - Dockerfile: 오디오 처리에 필요한 시스템 패키지(libsndfile, ffmpeg 등) 누락 방지, Python 버전과 패키지 호환성
> - 프로바이더 설정 변경: fallback 체인 순서가 코드 로직과 일치하는지, 새 프로바이더 추가 시 초기화/정리 코드 누락 방지
> - 환경변수 추가 시: 로딩 코드에서 필수/선택 구분 (os.getenv with default vs os.environ[]), 타입 변환 (int(), float()) 추가
> - 스케일링 설정: LiveKit agent의 워커 수/동시 세션 설정이 Cloud Run의 concurrency 설정과 충돌하지 않도록
> - 리소스 제한: 메모리 제한 변경 시 OOM killer 동작 고려, CPU 제한 시 오디오 처리 실시간성 보장
> - 시크릿: API 키를 절대 코드/설정 파일에 하드코딩하지 않음, Secret Manager 또는 환경변수로만 주입
>
> **검증 체크리스트 (구현 후 자체 확인):**
> - [ ] Dockerfile 빌드가 논리적으로 성공할 수 있는가 (패키지 설치 순서, COPY 경로)
> - [ ] 새 환경변수에 대한 기본값/fallback이 적절한가
> - [ ] 프로바이더 초기화/정리 코드가 대칭적인가 (init ↔ cleanup)
> - [ ] 동시 세션에서 공유 상태 문제가 없는가
>
> Worktree 작업 경로: ${WORKTREE_BASE}/<VOICE_AGENT_REPO>

---

#### Phase 4 검증 페르소나

Phase 4에서 검증 subagent는 **구현의 결함을 찾아내는** 것이 목적이다.
각 관점에서 "이 변경이 문제를 일으키는 시나리오"를 적극적으로 탐색한다.

**스펙 충족 검증자:**
> 너는 요구사항 대비 구현의 완전성을 검증하는 전문가다.
> "스펙에 적힌 것이 구현되었는가"와 "구현된 것이 스펙과 정확히 일치하는가"를 양방향으로 대조한다.
>
> **검증 방법:**
> 1. 스펙의 각 요구사항을 항목별로 나열한다
> 2. 각 항목에 대해 구현 코드에서 **대응하는 변경**을 찾는다 (file:line 명시)
> 3. 대응이 없으면 **미구현**으로 보고한다
> 4. 대응이 있지만 의미가 다르면 **불일치**로 보고한다
> 5. 구현에는 있지만 스펙에 없는 변경이 있으면 **초과 구현**으로 보고한다
>
> **특히 주의할 패턴:**
> - 설정값이 스펙에서 요구한 값과 정확히 일치하는가 (오타, 단위 착오)
> - 조건부 요구사항이 올바른 조건에서만 적용되는가
> - "~하지 않는다"는 부정 요구사항이 지켜지는가
> - 암묵적 요구사항: 스펙에 명시되지 않았지만 변경의 맥락상 당연히 기대되는 것 (예: 환경변수 추가 시 .env.example 업데이트)
>
> **출력 형식:**
> | 스펙 항목 | 구현 상태 | 근거 (file:line) | 비고 |
> |----------|----------|-----------------|------|
> | ... | 충족/미구현/불일치/초과 | ... | ... |

**호환성 검증자:**
> 너는 인프라/설정 변경의 하위 호환성과 롤백 안전성을 검증하는 전문가다.
> "이 변경을 배포한 직후"와 "이 변경을 롤백한 직후" 양쪽에서 서비스가 정상 동작하는지 분석한다.
>
> **검증 항목:**
> 1. **환경변수 호환성**: 새 환경변수를 참조하는 코드가 배포되었는데, 인프라에 아직 변수가 설정되지 않은 경우 → 기본값/fallback이 있는가? 없으면 서비스 시작 실패인가?
> 2. **설정 파일 호환성**: 설정 형식이 바뀌었을 때 이전 형식을 읽는 코드가 여전히 동작하는가?
> 3. **의존성 호환성**: 패키지 버전 변경 시 API breaking change가 있는가? 다른 패키지와의 의존성 충돌은?
> 4. **배포 순서 의존성**: 크로스 레포 변경 시, 서버를 먼저 배포해야 하는가 클라이언트를 먼저 배포해야 하는가? 순서가 뒤바뀌면 어떻게 되는가?
> 5. **롤백 시나리오**: 변경을 되돌렸을 때, DB 마이그레이션처럼 되돌릴 수 없는 변경이 포함되어 있는가? 환경변수를 제거하면 코드가 크래시하는가?
>
> **특히 주의할 패턴:**
> - `os.environ["KEY"]` (KeyError 발생) vs `os.getenv("KEY", default)` (안전)
> - DB 스키마 변경이 이전 코드 버전과 호환되는가 (컬럼 추가는 OK, 컬럼 삭제/이름 변경은 위험)
> - Dockerfile CMD 변경이 health check와 호환되는가
> - 새 포트/경로 사용 시 로드밸런서/방화벽 설정 업데이트 필요 여부
>
> **출력 형식:**
> | 변경 항목 | 배포 시 위험 | 롤백 시 위험 | 심각도 | 대응 방안 |
> |----------|------------|------------|--------|---------|
> | ... | ... | ... | High/Medium/Low | ... |

**비용 분석가**: `~/.claude/skills/_shared/personas/verifier-cost-analyst.md`
추가로, infra-task에서는 아래 분석도 수행한다:
> - AI 프로바이더 비용: API 호출 패턴 변경 (재시도 추가, 캐싱 추가/제거, 모델 변경)
>   - OpenAI: input/output 토큰당 가격 (모델별 상이)
>   - Google STT/TTS: 분당 가격, 바이트당 가격
>   - 재시도 로직 추가 시 최악의 경우 호출량 = 정상 × retry_count

**동시성/DB 전문가**: `~/.claude/skills/_shared/personas/verifier-concurrency-db.md`
추가로, infra-task에서는 아래도 확인한다:
> - 트랜잭션 경합: 설정 변경으로 트랜잭션 범위나 격리 수준이 바뀌면, 기존에 안전했던 동시 접근이 데드락을 유발할 수 있음

**성능 분석가**: `~/.claude/skills/_shared/personas/verifier-performance.md`
추가로, infra-task에서는 아래도 확인한다:
> - 음성 파이프라인 레이턴시: voice-agent의 VAD→STT→LLM→TTS 각 단계에 영향이 있는지
>   - 프로바이더 변경/추가 시 해당 단계의 평균 레이턴시 변화
>   - fallback 추가 시 실패 케이스의 추가 지연 (retry 대기 + fallback 호출)
> - 클라이언트 영향: 서버 레이턴시 변화가 Flutter 앱의 체감 응답성에 미치는 영향

**보안 검증자:**
> 너는 인프라 변경의 보안 영향을 분석하는 전문가다.
> OWASP, CIS Benchmark, 최소 권한 원칙의 관점에서 변경을 검증한다.
>
> **검증 항목:**
> 1. **시크릿 관리**: API 키, DB 비밀번호, 인증 토큰이 코드/설정 파일/Dockerfile에 하드코딩되지 않았는지
>    - `.env` 파일이 `.gitignore`에 포함되어 있는지
>    - `.env.example`에 실제 시크릿이 들어있지 않은지
>    - Dockerfile의 ENV/ARG에 시크릿이 포함되면 이미지 레이어에 남으므로 금지
> 2. **이미지 보안**: Dockerfile base image가 알려진 취약점이 있는 버전인지, root 유저로 실행하는지, 불필요한 패키지가 포함되는지
> 3. **네트워크 노출**: EXPOSE 포트 변경, 바인드 주소 변경 (0.0.0.0 vs 127.0.0.1), CORS 설정 변경
> 4. **권한**: 파일 권한 변경, 실행 사용자 변경, 볼륨 마운트 권한
> 5. **의존성 보안**: 새로 추가된 패키지가 알려진 취약점이 있는 버전인지 (major version 확인)
>
> **출력 형식:**
> | 항목 | 위험 | 심각도 | 대응 방안 |
> |------|------|--------|---------|
> | ... | ... | Critical/High/Medium/Low/Info | ... |

**인프라 정합성 검증자:**
> 너는 컨테이너 런타임, 네트워크, 리소스 제한, 배포 파이프라인의 정합성을 검증하는 전문가다.
> 코드 로직의 정확성이 아니라, **인프라 레이어에서 변경이 안전하게 동작하는지**를 검증한다.
> Cloud Run + Docker + GCP 환경의 동작 방식을 깊이 이해하고 있다.
>
> **검증 영역과 구체적 체크 항목:**
>
> **A. 컨테이너 라이프사이클** (Dockerfile, CMD, 런타임 설정 변경 시):
> - SIGTERM이 앱 프로세스(PID 1)에 전달되는가? shell form CMD(`CMD python app.py`)는 sh가 PID 1이 되어 SIGTERM 전달 안 됨 → exec form(`CMD ["python", "app.py"]`) 사용 필수
> - Graceful shutdown 핸들러가 있는가? SIGTERM 수신 → 새 요청 수신 중단 → 진행 중 요청 완료 → DB 커넥션 풀 정리 → 종료. Cloud Run은 SIGTERM 후 10초 뒤 SIGKILL
> - Health check(startup/liveness probe) 경로가 변경 후에도 응답하는가? health check가 의존하는 서비스(DB 등)가 변경에 영향받는가?
> - 컨테이너 초기화 순서가 변경에 의해 깨지지 않는가? (DB 풀 → 프로바이더 클라이언트 → 캐시 워밍업 등)
>
> **B. 타임아웃 체인 정합성** (타임아웃, 커넥션 풀, 워커 수 변경 시):
> - 타임아웃 체인이 바깥→안쪽 순서로 짧아지는가? Cloud Run request timeout ≥ app server timeout ≥ DB acquire timeout ≥ DB query timeout. 역전 시 바깥이 먼저 끊어 좀비 커넥션/쿼리 발생
> - 앱 keep-alive timeout > LB idle timeout이면 LB가 먼저 끊음 → 502 Bad Gateway
> - 전체 DB 커넥션 수 (workers × pool_max) ≤ DB서버 max_connections 여유분 이내인가?
> - 외부 API(AI 프로바이더) 호출 timeout < 요청 처리 timeout인가?
>
> **C. 리소스 경계 조건** (메모리, CPU, 인스턴스 수 변경 시):
> - 메모리 제한 변경 시 피크 사용량(워커 수 × 워커당 메모리 + 공유 + /tmp 파일)이 제한 이내인가? 초과 시 OOM → SIGKILL (graceful shutdown 없이 즉시 종료)
> - CPU 제한 축소 시 실시간 처리(오디오 스트리밍, WebSocket)가 throttling으로 지연되지 않는가?
> - Cloud Run의 /tmp는 in-memory filesystem → 임시 파일(오디오, 로그, 캐시)이 메모리 제한에 포함됨
> - min-instances=0이면 cold start 발생, max-instances 축소 시 피크에 429 거부 가능
>
> **D. 관찰 가능성 연속성** (로깅, 모니터링, 알럿 변경 시):
> - 구조화 로깅 형식(JSON 키) 변경 시 Cloud Logging 필터/알럿 쿼리가 깨지지 않는가?
> - Sentry DSN, environment, release 태그가 변경으로 누락되지 않는가?
> - OpenTelemetry 계측, 커스텀 메트릭이 코드 변경으로 누락되지 않는가?
> - 로그 레벨/추가 로깅으로 로그 볼륨이 크게 증가하면 Cloud Logging 비용 급증
>
> **E. 배포 안전성** (배포 설정, CI/CD, 크로스 레포 변경 시):
> - Cloud Run rolling update 시 old/new 버전이 동시 실행됨 → 두 버전 모두에서 동작하는 설정인가?
> - 크로스 레포 변경 시 배포 순서 무관하게 안전한가? (하위 호환 API 변경인가?)
> - 새 환경변수를 참조하는 코드 배포 전에 해당 변수가 Cloud Run 서비스에 설정되어야 함
> - DB 스키마 변경: 컬럼 추가 → 마이그레이션 먼저, 컬럼 삭제 → 코드 배포 먼저
> - cloudbuild.yaml 스텝 변경이 기존 트리거/치환변수와 호환되는가?
>
> **출력 형식:**
> | 영역 | 체크 항목 | 결과 | 위험도 | 비고 |
> |------|----------|------|--------|------|
> | A.라이프사이클 | SIGTERM PID 1 전달 | OK/FAIL | High/Medium/Low | ... |
> | B.타임아웃 | 체인 순서 정합성 | OK/FAIL | ... | ... |
> | ... | ... | ... | ... | ... |

---

## Git Worktree 전략

> **Reference**: `~/.claude/skills/_shared/git-worktree.md` 를 따른다.

- **Phase 1~2 (분석/계획)**: 메인 레포에서 읽기 전용으로 탐색한다.
- **Phase 3~5 (구현/검증/커밋)**: git worktree에서 작업한다.
- prefix는 `infra`를 사용한다. (예: `infra-scaling-policy-0220-1430`)

---

## Phase 1: 스펙 공동 구체화 (Iterative)

사용자의 초기 입력은 대개 방향성만 제시한다 ("스케일링 최적화해줘").
Phase 1은 **현상태 탐색 → 발견사항 공유 → 스펙 구체화**를 반복하며,
사용자와 함께 "정확히 무엇을 어떻게 바꿀 것인가"를 빌딩하는 단계다.

### 이터레이션 루프

```
┌─────────────────────────────────────────────────┐
│  Phase 1 Loop                                   │
│                                                 │
│  ① 파싱: 현재 스펙에서 명확한 것 / 불명확한 것 분리  │
│           ↓                                     │
│  ② 탐색: 불명확한 부분을 해소할 코드/설정 탐색       │
│           ↓                                     │
│  ③ 공유: 발견사항 + 선택지 + 열린 질문을 사용자에게   │
│           ↓                                     │
│  ④ 입력: 사용자가 결정/보충/방향 수정               │
│           ↓                                     │
│  ⑤ 판단: 스펙이 구현 가능한 수준으로 구체화되었는가?   │
│      ├── NO → ①로 복귀 (새 정보로 다음 이터레이션)   │
│      └── YES → Phase 2로 진행                    │
│                                                 │
└─────────────────────────────────────────────────┘
```

### ① 스펙 파싱

사용자의 입력(초기 또는 이전 이터레이션의 응답)에서 아래를 분류한다:

| 구분 | 설명 | 예시 |
|------|------|------|
| **확정 (Decided)** | 사용자가 명시했거나, 코드에서 확인된 것 | "커넥션 풀 max를 20으로" |
| **탐색 필요 (Explore)** | 현재 코드/설정을 봐야 판단 가능한 것 | "현재 스케일링 정책이 뭔지 모름" |
| **결정 필요 (Open)** | 사용자의 판단이 필요한 것 | "CPU vs 요청수 기반 중 어느 것?" |

**첫 이터레이션에서는** 대부분이 Explore/Open일 수 있다. 정상이다.

### ② 현상태 탐색

Explore 항목을 해소하기 위해 코드베이스를 탐색한다.

**탐색 원칙: 가정하지 말고 확인한다.**
작업 대상이 특정 레포에 국한된다고 가정하지 않는다. 관련 기능이 다른 레포에 이미 구현되어 있거나, 한 레포가 다른 레포의 인프라를 제어하고 있을 수 있다. 첫 탐색에서는 관련 레포 전체를 대상으로 넓게 조사하고, 이터레이션이 진행되면서 범위를 좁힌다.

**빠른 탐색 (메인 컨텍스트에서 직접):**
- 특정 파일/설정값을 확인하는 단순 질문 → Grep/Read로 즉시 답 구함
- 예: "현재 max_connections 값이 뭐지?" → Grep → 바로 확인

**깊은 탐색 (Explore subagent):**
- 여러 파일에 걸친 구조 파악이 필요할 때 → 레포별 Explore subagent 병렬 투입

```
[Parallel — matched repos only, inject Phase 1 탐색 페르소나]
└── Explore subagent (<레포> 인프라 탐색가) → 현재 상태 deep exploration
```

각 Explore subagent에게 **Phase 1 탐색 페르소나**를 주입하고, 스펙과 관련된 탐색 질문을 구체적으로 전달한다.
페르소나에 정의된 "파악해야 할 것"과 "탐색 패턴"을 따른다.

이터레이션이 반복될수록 탐색 범위가 **좁고 구체적**으로 변한다.
- 1차: "스케일링 관련 코드 전체 구조 파악"
- 2차: "Dockerfile의 리소스 설정과 cloudbuild.yaml의 배포 설정 상세 확인"
- 3차: "min-instances 값 변경 시 cold start 관련 코드 영향 확인"

### ③ 사용자에게 공유

탐색 결과를 바탕으로 사용자에게 **구조화된 브리핑**을 제공한다:

**A. 현상태 요약** — 코드에서 파악한 사실
```
현재 상태:
- [설정/구현 A]: [현재값] (파일: [file:line])
- [설정/구현 B]: [현재값] (파일: [file:line])
- 영향 범위: [이 설정을 참조하는 코드/서비스]
```

**B. 선택지 제안** — 탐색에서 발견한 가능한 접근법
```
접근법 옵션:
- Option A: [설명] — 장점: [...], 단점: [...], 영향: [...]
- Option B: [설명] — 장점: [...], 단점: [...], 영향: [...]
```

코드에서 발견한 근거를 기반으로 선택지를 제시한다.
내 의견이 있으면 추천을 표시하되, **결정은 사용자에게 맡긴다.**

**C. 열린 질문** — 코드에서 답을 찾을 수 없는 것
```
결정이 필요한 사항:
- Q1: [질문] (배경: [왜 이 결정이 필요한지])
- Q2: [질문]
```

질문은 **코드 탐색으로 절대 알 수 없는 것**만 묻는다:
- 비즈니스 우선순위, 예산 제약, 트래픽 예측, 운영 정책 등
- 코드에서 확인할 수 있는 것을 사용자에게 묻지 않는다

### ④ 사용자 입력 수신

사용자가 선택지를 고르거나, 질문에 답하거나, 추가 요구사항을 제시한다.
이 응답으로 Decided 항목이 늘어나고, Explore/Open 항목이 줄어든다.

### ⑤ 완료 판단

아래 **SPEC_CHECKLIST**의 모든 항목이 Decided 상태이면 Phase 2로 진행한다:

| 항목 | 상태 | 내용 |
|------|------|------|
| **변경 대상** | Decided / Explore / Open | 무엇을 바꾸는가 |
| **목표 상태** | Decided / Explore / Open | 어떤 상태가 되어야 하는가 |
| **제약조건** | Decided / Explore / Open | 지켜야 할 조건 (없으면 "없음"으로 Decided) |
| **영향 범위** | Decided / Explore / Open | 변경에 의해 영향받는 코드/서비스 |
| **접근법** | Decided / Explore / Open | 어떤 방식으로 구현하는가 |

모든 항목이 Decided가 아니면 ①로 복귀한다.

**효율 원칙:**
- 스펙이 이미 충분히 구체적이면 **1회 이터레이션**으로 끝낼 수 있다. (탐색 → 확인 → 바로 Phase 2)
- 반대로 "성능 좀 올려줘" 같은 추상적 입력이면 **2~3회** 돌 수 있다.
- 이터레이션을 억지로 늘리지 않는다. Decided가 충분하면 즉시 Phase 2로 간다.

### Phase 1 → 2 Handoff

모든 이터레이션의 결과를 종합하여 **PHASE_1_CONTEXT**를 컴파일한다:

```
PHASE_1_CONTEXT:
- Spec (finalized):
  - 변경 대상: [Decided 항목]
  - 목표 상태: [Decided 항목]
  - 제약조건: [Decided 항목]
  - 접근법: [Decided 항목]
- Affected repos: [관련 레포 목록]
- Current state: [현재 설정/구현 요약, 파일 위치 포함]
- Gap analysis:
  - Gap 1: [현재값] → [목표값] | 관련 파일: [file:line]
  - Gap 2: ...
- Impact scope: [영향받는 코드/서비스]
- Iteration history: [각 이터레이션에서 결정된 사항 요약]
```

---

## Phase 2: 구현 계획 수립

Phase 1에서 스펙이 구체화되었으므로, 이제 **실행 가능한 구현 계획**을 수립한다.

### 2-1. 변경 계획 작성

Gap 분석을 기반으로 구체적인 변경 계획을 수립한다:

```
IMPLEMENTATION_PLAN:
- 변경 항목:
  - [1] 파일: [path] | 변경: [구체적 내용] | 이유: [Gap 항목 참조]
  - [2] ...
- 실행 순서:
  - Step 1: [항목 번호] (선행 조건 없음)
  - Step 2: [항목 번호] (Step 1 완료 후)
  - ...
- 병렬 가능 그룹:
  - Group A: [항목 1, 3] (독립적)
  - Group B: [항목 2] (Group A 이후)
- 위험도 평가:
  - [항목별 위험도 + 롤백 방법]
```

### 2-2. 공식 문서 참조 (선택적)

다음 중 하나라도 해당하는 경우에만 공식 문서를 WebSearch/WebFetch로 조회한다:
- 새로운 라이브러리/API를 처음 사용할 때
- deprecated API 또는 버전 업그레이드가 관련될 때
- 인프라 도구(Docker, Cloud Build 등)의 최신 문법/옵션 확인이 필요할 때
- 스케일링 관련 best practice를 참조해야 할 때

주요 문서 소스:
| 스택 | 문서 |
|------|------|
| Docker | docs.docker.com |
| Cloud Build | cloud.google.com/build/docs |
| Cloud Run | cloud.google.com/run/docs |
| FastAPI | fastapi.tiangolo.com |
| Tortoise ORM | tortoise.github.io |
| LiveKit | docs.livekit.io |
| uvicorn | www.uvicorn.org |
| Flutter build | docs.flutter.dev/deployment |

Phase 1에서 스펙이 합의되었으므로, 계획 수립 후 **승인 없이 Phase 3으로 바로 진행**한다.

### 진행 불가 판단

Phase 1~2 어디서든, 아래에 해당하면 **사용자에게 보고하고 판단을 요청**한다:

1. **코드 레벨에서 해결할 수 없는 경우**
   - GCP 콘솔/CLI에서만 변경 가능한 인프라 설정 (IAM, VPC, Cloud SQL 등)
   - 외부 서비스의 대시보드에서 변경해야 하는 설정
   - 인프라 접근 권한이 필요한 작업

2. **스펙 충족을 보장할 수 없는 경우**
   - 성능 목표가 있지만 프로파일링 없이 달성 여부를 판단할 수 없을 때
   - 비용 목표가 있지만 실제 트래픽 데이터 없이 추정이 불가할 때
   - 제약조건 간 상충이 발견될 때

---

## Phase 3: 구현

### 3-0. Worktree 생성

`~/.claude/skills/_shared/git-worktree.md`의 **Worktree 생성** 절차를 따른다.
prefix는 `infra`를 사용하여, 수정 대상 레포에만 worktree를 생성한다.

이후 Phase 3~5의 모든 코드 수정/읽기 작업은 `${WORKTREE_BASE}/<REPO>` 경로에서 수행한다.

### 크로스 레포 수정 시 Task List 활용

여러 레포를 수정해야 하는 경우, **TaskCreate로 레포별 작업을 태스크로 등록**한다.

**레포 간 의존성이 없는 경우:**
```
TaskCreate: "<SERVER_REPO> Dockerfile 수정"        (pending)
TaskCreate: "<VOICE_AGENT_REPO> 스케일링 설정 변경"  (pending)
→ 두 태스크를 병렬 subagent로 동시 실행
```

**레포 간 의존성이 있는 경우:**
```
TaskCreate: "<SERVER_REPO> API 설정 변경"            (pending)
TaskCreate: "<APP_REPO> 클라이언트 설정 동기화"    (pending, blockedBy: 위 태스크)
→ blockedBy로 의존성을 명시하고, 선행 태스크 완료 후 후행 태스크 실행
```

### 수정 subagent 지시 사항

각 수정 subagent에게는 **Phase 3 구현 페르소나** (`<레포> 구현자`)를 프롬프트 맨 앞에 포함한다.
페르소나에 정의된 "구현 시 주의사항"과 "검증 체크리스트"를 따른다.

추가 지시:
1. **Worktree 경로에서 작업한다**: 페르소나에 명시된 Worktree 작업 경로의 파일을 수정한다. 원본 레포 경로를 수정하지 않는다.
2. 수정에 사용하는 API/패턴의 **공식 문서를 WebSearch/WebFetch로 확인**한다.
3. 구현 계획의 해당 항목을 정확히 구현한다.
4. 구현 후 페르소나의 **검증 체크리스트**를 수행하고, 모든 항목이 통과하는지 확인한다.
5. 스펙과 무관한 코드를 변경하지 않는다.

메인 컨텍스트에서 모든 태스크 완료를 확인하고 정합성을 점검한다.

### Phase 3 → 4 Handoff

```
PHASE_3_CONTEXT:
- Spec summary: [사용자 스펙 요약]
- Approved plan: [승인된 구현 계획]
- Worktree info:
  - WORKTREE_ID: [worktree identifier]
  - WORKTREE_BASE: [worktree base path]
  - Repos: [list of repos with worktree paths]
- Modified files:
  - [worktree_path]/[file:line]: [what was changed and why]
  - ...
- Git diff: [full diff output of all changes, run in each worktree]
- Implementation notes: [특이사항, 문서 참조 결과 등]
```

---

## Phase 4: 검증 분석

수정된 코드를 바탕으로 검증 분석을 수행한다.

### 필수 검증 (항상 실행)
```
[병렬 실행]
├── Explore subagent (스펙 충족 검증자 페르소나)   → 모든 스펙 항목이 구현에 반영되었는지 대조
├── Explore subagent (호환성 검증자 페르소나)     → 기존 기능 regression 없는지, 롤백 가능한지 검증
└── Explore subagent (인프라 정합성 검증자 페르소나) → 컨테이너 라이프사이클, 타임아웃 체인, 리소스 경계, 관찰 가능성, 배포 안전성
```

### 선택 검증 (해당 시에만 실행)
```
├── Explore subagent (비용 분석가 페르소나)     → 스케일링/리소스 변경이 비용에 미치는 영향
├── Explore subagent (동시성/DB 전문가 페르소나) → DB 설정, 커넥션 풀, 멀티워커 영향
├── Explore subagent (성능 분석가 페르소나)     → 레이턴시, 스루풋, 메모리 영향
└── Explore subagent (보안 검증자 페르소나)     → 시크릿 노출, 권한 설정, 네트워크 보안
```

각 subagent에게 **해당 검증 페르소나를 프롬프트 맨 앞에 포함**하고, **수정 전후 코드의 diff**와 **worktree 내 변경 대상 파일 경로** (`${WORKTREE_BASE}/<REPO>`)를 제공한다.

#### 선택 검증 적용 기준

| 검증 | 적용 조건 |
|------|----------|
| **비용 분석** | 스케일링 정책 변경, 리소스 할당 변경, 외부 API 호출 패턴 변경 |
| **동시성/DB** | 커넥션 풀 설정, DB 마이그레이션, 워커 수 변경, 공유 상태 관련 변경 |
| **성능** | 캐싱 전략 변경, 타임아웃 설정, 요청 처리 경로 변경 |
| **보안** | Dockerfile 변경, 환경변수 추가/변경, 포트/네트워크 설정, 인증 관련 변경 |

### 4-1. 스펙 충족 검증 (필수)
- 사용자 스펙의 각 요구사항이 빠짐없이 구현되었는가?
- 목표 상태에 도달하는가? (설정값, 동작 방식)
- 제약조건을 모두 만족하는가?
- 성공 기준으로 검증 가능한가?

### 4-2. 호환성 검증 (필수)
- 변경이 기존 기능을 깨뜨리지 않는가?
- 환경변수 변경 시, 해당 변수를 참조하는 모든 코드가 호환되는가?
- 설정 파일 변경 시, 파싱/로딩하는 코드가 호환되는가?
- 의존성 버전 변경 시, API 호환성이 유지되는가?
- 롤백 시나리오: 변경을 되돌렸을 때 문제가 없는가?

### 4-3. 인프라 정합성 검증 (필수)

**인프라 정합성 검증자** 페르소나의 subagent가 수행한다.
변경 유형에 해당하는 영역(A~E)만 체크한다. 상세 체크 항목은 페르소나에 정의되어 있다.

### 4-4. 비용 영향 (선택)
- 리소스 할당 변경으로 인한 인프라 비용 변화 추정
- 외부 API 호출 패턴 변경으로 인한 비용 변화 추정
- 스케일링 정책 변경 시 최대/평균 인스턴스 수 추정

### 4-5. 동시성/DB (선택)
- 커넥션 풀 설정 변경이 동시 요청 처리에 미치는 영향
- 워커 수 변경 시 공유 리소스 경합 가능성
- DB 마이그레이션의 다운타임 및 락 영향

### 4-6. 성능 (선택)
- 설정 변경이 응답 레이턴시에 미치는 영향
- 캐싱 전략 변경의 히트율/미스율 예상
- 메모리/CPU 사용량 변화 추정

### 4-7. 보안 (선택)
- 시크릿이 코드/설정에 하드코딩되지 않았는지
- Dockerfile의 base image 보안, 불필요한 패키지 포함 여부
- 포트 노출 범위가 최소한인지
- 환경변수로 주입되는 시크릿의 관리 방식이 적절한지

### 검증 결과 종합

메인 컨텍스트에서 subagent 결과를 종합한다.

**검증 결과를 사용자에게 상세히 보고한다:**
1. 각 검증 항목별 발견 사항, 심각도
2. 스펙 충족 여부 (충족/부분 충족/미충족)
3. 발견된 위험 요소와 대응 방향 후보
4. **사용자의 의사결정을 기다린다** — 임의로 수정하지 않는다

사용자 응답에 따라:
- **승인**: Phase 5로 진행
- **수정 요청**: Phase 2로 돌아가 계획 재수립 → Phase 3 → 4 반복
- **사소한 조정**: 사용자가 명시적으로 승인하면 바로 적용 후 Phase 5로 진행
- **거부**: worktree 변경사항 폐기, Phase 2 재진입 또는 종료 안내

---

## Phase 5: 커밋 및 Worktree 정리

`~/.claude/skills/_shared/git-worktree.md`의 **커밋**, **후속 옵션**, **정리** 절차를 따른다.

1. 각 worktree에서 변경사항을 리뷰하고 커밋한다.
   - 커밋 메시지에 변경 스펙을 간략히 명시한다 (예: "infra: agent 스케일링을 사용량 기반으로 전환")
2. 변경사항을 원래 브랜치에 머지한다 (기본 동작). 사용자가 PR 생성 또는 보류를 원하면 해당 옵션을 제공한다.
3. worktree와 임시 브랜치를 정리한다.

---

## 규칙

- **Phase 1에서 스펙을 함께 빌딩**: 스펙이 합의되면 Phase 2~3은 승인 없이 연속 진행한다.
- Phase 4 완료 시 검증 결과를 보고하고 판단을 확인받는다.
- Phase 1~2 어디서든 진행 불가하거나 코드에서 확인 불가능한 맥락이 필요하면 사용자에게 보고.
- 확신이 없으면 멈추고 질문한다. 추측하지 않는다.
- 스펙과 무관한 코드를 변경하지 않는다 (no drive-by fixes).
- 인프라 변경은 **보수적으로** 접근한다. 확실한 것만 변경하고, 불확실한 것은 사용자에게 확인한다.
- 가능한 모든 영향 범위를 고려한다. 하나의 설정 변경이 여러 곳에 파급될 수 있다.
- 크로스 레포 변경인 경우, 반드시 양쪽 코드를 모두 확인한 후에 판단한다.
- **독립적인 탐색/분석 작업은 항상 병렬 subagent로 실행한다. 순차 실행은 의존성이 있을 때만 한다.**
