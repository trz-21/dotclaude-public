---
name: init-project
description: 새 프로젝트를 처음부터 자동으로 세팅하는 워크플로우. "/init-project", "새 프로젝트 시작", "프로젝트 초기화" 요청 시 사용.
argument-hint: [서비스-설명]
---

# /init-project

## 트리거

사용자가 다음 중 하나를 요청할 때:
- `/init-project`
- "새 프로젝트 시작", "프로젝트 초기화"
- "새 프로젝트 만들어줘" 등의 자연어 요청

## 입력

자연어로 서비스에 대한 대략적인 설명.

예시:
- "할 일 관리 앱이야. 사용자가 할일을 추가하고 완료 체크할 수 있어"
- "음악 스트리밍 서비스. 사용자가 플레이리스트를 만들고 음악을 들을 수 있어"

입력에서 추출해야 하는 정보:
- **서비스 이름**: 프로젝트 디렉토리명 및 패키지명에 사용 (kebab-case, 예: `todo-app`)
- **서비스 설명**: 핵심 기능과 가치 제안
- **핵심 도메인**: 주요 엔티티와 사용자 흐름

---

## 사전 확인

작업 시작 전 사용자에게 확인:

```
1. 프로젝트 루트 경로: [기본값: <WORKSPACE>/{project-name}]
2. 프로젝트 이름 (kebab-case): [서비스 설명에서 추출한 이름]
3. 위 설정으로 진행할까요?
```

확인 받은 후 아래 단계를 순차 실행한다.

---

## 워크플로우

### Step 1: 디렉토리 구조 생성

```bash
PROJECT_ROOT="{확인된 경로}/{project-name}"
PROJECT_NAME="{project-name}"

mkdir -p ${PROJECT_ROOT}
mkdir -p ${PROJECT_ROOT}/${PROJECT_NAME}-backend
mkdir -p ${PROJECT_ROOT}/${PROJECT_NAME}-frontend
mkdir -p ${PROJECT_ROOT}/specification/service
mkdir -p ${PROJECT_ROOT}/specification/dev
mkdir -p ${PROJECT_ROOT}/.claude/hooks
```

생성 결과:
```
{project-root}/
├── {project}-backend/
├── {project}-frontend/
├── specification/
│   ├── service/
│   └── dev/
├── .claude/
│   └── hooks/
└── CLAUDE.md
```

---

### Step 2: 스펙 문서 초안 작성

서비스 설명을 바탕으로 아래 6개 파일을 작성한다. 추측이 필요한 부분은 `[TODO: 확인 필요]`로 표시하고 진행한다.

#### `specification/service/overview.md`

포함 내용:
- 서비스 개념과 핵심 가치 (1-2문장)
- 타겟 사용자
- 핵심 사용자 흐름 (step-by-step)
- v1 기능 목록 (MVP 범위)
- 명시적으로 v1 제외 항목

#### `specification/dev/tech-stack.md`

기본 스택으로 초안 작성:
- 백엔드: Rust + Axum + Tokio + sqlx + PostgreSQL
- 프론트엔드: Next.js 14 (TypeScript) + Tailwind + Zustand + TanStack Query
- 테스트: cargo test + TestApp + Vitest + Playwright + GitHub Actions CI
- 각 선택의 이유 포함

#### `specification/dev/api.md`

서비스 설명에서 유추한 엔티티 기반으로:
- 인증 엔드포인트 (POST /auth/register, POST /auth/login)
- 핵심 도메인 CRUD 엔드포인트
- 요청/응답 스키마 초안

#### `specification/dev/backend.md`

포함 내용:
- 아키텍처 패턴: Hexagonal Architecture (Ports & Adapters)
- 디렉토리 구조 (`src/domain/ports/`, `src/application/`, `src/adapters/`, `src/http/`)
- 주요 레이어 역할
  - `domain/`: Zero external deps. trait(port) 정의
  - `application/`: 비즈니스 로직, domain port 사용
  - `adapters/`: 외부 의존성 구현체 (postgres 등)
  - `http/`: Axum 핸들러, AppState, 라우터
- AppState 패턴: Arc<dyn Trait>로 서비스 보관, 앱 시작 시 한 번 초기화
- 에러 처리 패턴 (AppError + IntoResponse)
- DB 연결 및 마이그레이션 전략
- 테스트: testcontainers로 격리 DB 자동 관리, `cargo test`만으로 실행

#### `specification/dev/frontend.md`

포함 내용:
- 디렉토리 구조 (app/, components/, lib/, hooks/, store/, types/)
- 페이지 구성 초안
- 상태 관리 전략 (Zustand store 분리 방식)
- API 통신 패턴 (TanStack Query)

#### `specification/dev/harness.md`

포함 내용:
- 테스트 계층 구조 (컴파일타임 → 단위 → 통합 → E2E)
- TestApp 패턴 설명
  - testcontainers로 `cargo test` 실행 시 자동 PostgreSQL 컨테이너 관리
  - 프로세스당 컨테이너 1개 공유 (OnceLock), 각 TestApp은 격리된 test_<uuid> DB
  - 로컬 PostgreSQL 설치 불필요
- 로컬 개발 환경
  - `make test`: cargo test만 실행 (testcontainers 자동 처리)
  - `make run`: docker-compose DB 시작 + migrate + cargo run
- AI Agent 코드 수정 규칙 (5개 원칙)
- CI 파이프라인 단계

---

### Step 3: CLAUDE.md 작성

`{project-root}/CLAUDE.md` 파일을 아래 구조로 작성한다:

```markdown
# {프로젝트명} - 프로젝트 가이드

## 프로젝트 개요

{서비스 설명 1-2문장}

---

## 작업 시작 전 반드시 읽을 것

새 세션 또는 서브에이전트 시작 시 순서대로 읽어라:

1. 이 파일 (`CLAUDE.md`) — 전체 맥락
2. `specification/service/` — 현재 서비스 스펙
3. `specification/dev/` 해당 영역 — 기술 구현 스펙

---

## 문서 구조

\`\`\`
{project-root}/
│
├── specification/              # 살아있는 스펙 (항상 최신 상태)
│   ├── service/                # 서비스 스펙 (사용자/기능 관점)
│   │   └── overview.md
│   └── dev/                    # 개발 스펙 (기술 구현)
│       ├── tech-stack.md
│       ├── api.md
│       ├── backend.md
│       ├── frontend.md
│       └── harness.md
│
├── {project}-backend/          # Rust 백엔드 코드
├── {project}-frontend/         # Next.js 프론트엔드 코드
└── CLAUDE.md                   # 이 파일
\`\`\`

### 문서 작성 규칙

| 문서 종류 | 위치 | 언제 작성 |
|-----------|------|-----------|
| 스펙 변경 | `specification/` | 기능/설계가 바뀔 때마다 업데이트 |

**스펙은 항상 최신 상태로 업데이트한다.** 작업 로그·플랜·세션 기록을 로컬에 파일로 남기지 않는다 (진행 상황은 대화로 보고).

---

## 기술 스택

| 영역 | 스택 |
|------|------|
| 백엔드 | Rust + Axum + Tokio + sqlx + PostgreSQL |
| 프론트엔드 | Next.js 14 (TypeScript) + Tailwind + Zustand + TanStack Query |
| 테스트 | cargo test + testcontainers + Vitest + Playwright + GitHub Actions CI |

→ 결정 이유: `specification/dev/tech-stack.md`

---

## 워크플로우 규칙

상세 내용은 아래 파일 참조:

| 규칙 | 파일 |
|------|------|
| 코드 수정 규칙 | `.claude/code-rules.md` |
| 작업 완료 기준 (DoD) | `.claude/dod.md` |
| 커밋 규칙 | `.claude/commit-rules.md` |
| 테스트 안전망 | `specification/dev/harness.md` |

---

## 세션 마무리

세션 마무리 시:
- 변경된 스펙 문서(`specification/`) 업데이트
- CLAUDE.md 업데이트
```

---

### Step 3.5: `.claude/` 운영 파일 생성

프로젝트 루트(`{project-root}`)에 AI Agent 워크플로우 규칙 파일을 생성한다.

**`.claude/code-rules.md`** — 코드 수정 규칙

```markdown
# AI Agent 코드 수정 규칙

코드를 수정할 때 반드시 준수한다.

## 일반 규칙

1. **컴파일 먼저**: `cargo check` 통과 없이 작업 완료 불가
2. **테스트 통과**: `cargo test` 전체 통과 필수
3. **API 계약 유지**: 기존 API 응답 필드 제거/타입 변경 금지 (추가만 허용)
4. **트레이트 계약**: Port trait 변경 시 모든 구현체 동시 수정
5. **테스트 동반**: 새 엔드포인트/기능 추가 시 테스트 필수
6. **스펙 동기화**: 기능/설계 변경 시 `specification/` 업데이트 필수

## 백엔드 새 API 엔드포인트 추가 순서

\`\`\`
[ ] 1. domain/ports/ 에 필요한 trait 정의 (없으면 추가)
[ ] 2. adapters/ 에 구현체 작성
[ ] 3. application/ 에 서비스 로직 작성
[ ] 4. http/handlers/ 에 핸들러 작성 (매크로 패턴 사용, 아래 참조)
[ ] 5. http/router.rs 의 route_table() 에 한 줄 추가
[ ] 6. 통합 테스트 작성 (TestApp + Mock 주입)
[ ] 7. cargo check && cargo test 통과
[ ] 8. specification/dev/api.md 업데이트
\`\`\`

### 핸들러 작성 규칙

**표준 케이스 → 매크로 사용 (src/http/macros.rs)**

| 패턴 | 매크로 |
|------|--------|
| POST + JSON body | `post_endpoint!` |
| GET + /:id | `get_endpoint_with_id!` |
| POST + /:id (body 없음) | `post_endpoint_with_id!` |

매크로는 Request/Response 구조체와 핸들러 함수를 함께 생성한다.
잘못된 타입 또는 서비스 메서드 시그니처는 컴파일 에러로 즉시 검출된다.

**비표준 케이스 → 수동 작성** (OptionalUser, Query 파라미터, SSE)

수동 작성 시 반드시 `impl IntoResponse` 대신 `Result<Json<XxxResponse>, AppError>` 를 명시한다.
XxxResponse는 `#[derive(Serialize)]` 구조체여야 한다 (`json!({...})` 매크로 금지).

## 프론트엔드 새 API 함수 추가 패턴

**모든 API 함수는 명명된 타입을 사용한다. 인라인 타입(`Promise<{ field: Type }>`) 금지.**

\`\`\`
[ ] 1. src/features/{domain}/types.ts 에 {Action}Request / {Action}Response 인터페이스 추가
[ ] 2. src/features/{domain}/api/index.ts 에 함수 추가:
        export async function actionName(req: ActionRequest): Promise<ActionResponse>
[ ] 3. npm run type-check && npm test 통과
\`\`\`

### 타입 네이밍 규칙

| 종류 | 패턴 | 예시 |
|------|------|------|
| 요청 body | `{Action}Request` | `CreateItemRequest` |
| 응답 | `{Action}Response` | `CreateItemResponse` |
| 도메인 모델 | 명사형 | `Item`, `User` |

- `{Action}Request`, `{Action}Response` → `src/features/{domain}/types.ts` (예외 파일이므로 테스트 불필요)
- BE `XxxResponse` 구조체와 1:1 대응 유지

## 파일별 단위 테스트 요구사항

- `src/application/`, `src/adapters/` 하위 .rs 파일: `#[cfg(test)] mod tests` 필수
- `src/features/` 하위 .ts/.tsx 파일: 동일 경로 `.test.ts` 파일 필수
- 예외: `mod.rs`, `main.rs`, `lib.rs`, `config.rs`, `error.rs`, `index.ts`, `types.ts`
```

**`.claude/dod.md`** — 작업 완료 기준

```markdown
# 작업 완료 기준 (Definition of Done)

코드 수정이 포함된 모든 작업은 아래가 **모두** 충족돼야 "완료"다.

## 체크리스트

- [ ] **컴파일/타입**: `cargo check` (BE) / `npm run type-check` (FE) 통과
- [ ] **테스트**: `cargo test` (BE) / `npm test -- --run` (FE) 전체 통과
- [ ] **스펙 동기화**: 기능/설계 변경 시 `specification/` 해당 파일 업데이트
- [ ] **커밋**: 작업 단위로 git commit (`.claude/commit-rules.md` 참조)

## 검증 명령어

\`\`\`bash
# 백엔드
cd {project}-backend
cargo check
cargo test

# 프론트엔드
cd {project}-frontend
npm run type-check
npm test -- --run
\`\`\`

## 서브에이전트 주의사항

훅은 메인 Claude에만 적용된다. 서브에이전트에게 작업을 위임할 경우,
메인이 서브에이전트 완료 후 직접 검증해야 한다:

1. 해당 명령어 실행 (cargo check, npm run type-check, cargo test, npm test -- --run)
2. 모두 통과 시에만 작업 완료 처리
```

**`.claude/commit-rules.md`** — 커밋 규칙

```markdown
# 커밋 규칙

## 타이밍

- DoD (`.claude/dod.md`) 전체 충족 시점에 커밋
- 논리적으로 완결된 단계마다 커밋 (한 작업을 여러 단계로 나눌 때)
- WIP 상태 (컴파일/테스트 실패) 는 커밋하지 않는다

## 메시지 형식

\`\`\`
<type>: <subject>

[optional body]

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
\`\`\`

## Type 목록

| type | 사용 상황 |
|------|-----------|
| `feat` | 새 기능 추가 |
| `fix` | 버그 수정 |
| `refactor` | 기능 변경 없는 코드 개선 |
| `test` | 테스트 추가/수정 |
| `docs` | 문서만 변경 |
| `infra` | 인프라/배포 설정 변경 |
| `chore` | 의존성, 설정, 빌드 스크립트 |

## 범위

- 백엔드 + 프론트엔드 + 문서가 하나의 기능을 위한 변경이면 **한 커밋**
- 서로 독립적인 변경은 **별도 커밋**
- `.env`, `.env.prod`, 시크릿 파일은 **절대 커밋 금지**

## 푸시

사용자가 명시적으로 요청할 때만 푸시한다.
```

---

### Step 4: 백엔드 초기화 (Rust + Axum)

`{project-root}/{project}-backend/` 에서 실행한다.

#### 4-1. git init + cargo init

```bash
cd {project-root}/{project}-backend

git init
cargo init --name {project-name}-backend
```

#### 4-2. Cargo.toml 의존성 세팅

`Cargo.toml` 전체 내용을 아래로 교체한다:

```toml
[package]
name = "{project-name}-backend"
version = "0.1.0"
edition = "2021"

[lib]
name = "{project_name}_backend"   # kebab → snake
path = "src/lib.rs"

[[bin]]
name = "{project-name}-backend"
path = "src/main.rs"

[dependencies]
axum = { version = "0.7", features = ["macros"] }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sqlx = { version = "0.7", features = ["runtime-tokio", "postgres", "uuid", "chrono", "migrate"] }
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
jsonwebtoken = "9"
argon2 = "0.5"
dotenvy = "0.15"
thiserror = "1"
anyhow = "1"
async-trait = "0.1"
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

[dev-dependencies]
reqwest = { version = "0.11", features = ["json"] }
tokio = { version = "1", features = ["full"] }
dotenvy = "0.15"
testcontainers-modules = { version = "0.11", features = ["postgres"] }
```

#### 4-3. 디렉토리 구조 및 소스 파일 생성

Hexagonal Architecture 기반으로 구성한다:

```bash
mkdir -p src/domain/ports
mkdir -p src/application
mkdir -p src/adapters/postgres
mkdir -p src/http/handlers
mkdir -p tests/helpers
mkdir -p migrations
mkdir -p .github/workflows
```

최종 디렉토리 구조:
```
src/
├── lib.rs
├── config.rs
├── error.rs
│
├── domain/                    # Zero external deps
│   ├── mod.rs
│   └── ports/                 # trait (port) 정의
│       └── mod.rs
│
├── application/               # 비즈니스 로직
│   └── mod.rs
│
├── adapters/                  # 외부 의존성 구현체
│   ├── mod.rs
│   └── postgres/
│       └── mod.rs
│
└── http/                      # Axum 진입점
    ├── mod.rs
    ├── macros.rs              # 엔드포인트 매크로 (컴파일타임 강제)
    ├── state.rs               # AppState with Arc<dyn Trait>
    ├── router.rs              # route_table() 패턴
    └── handlers/
        └── mod.rs
```

#### 새 기능 추가 시 순서 (Port 패턴)

새 기능 = 새 모듈 원칙:
1. `domain/ports/`에 trait 추가
2. `adapters/`에 구현체 추가
3. `application/`에 서비스 추가
4. `http/handlers/`에 핸들러 추가
5. `http/state.rs`에 필드 추가
6. `http/router.rs`에 라우트 추가

---

생성할 파일 목록과 초기 내용:

**`src/lib.rs`** — 모듈 선언
```rust
pub mod application;
pub mod adapters;
pub mod config;
pub mod domain;
pub mod error;
pub mod http;
```

**`src/main.rs`** — 서버 진입점
```rust
use anyhow::Result;
use dotenvy::dotenv;
use {crate_name}_backend::{http::{router::build_router, state::AppState}, config::Config};
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "info".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = Config::from_env()?;
    let port = config.server_port;

    let db_pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await?;

    sqlx::migrate!("./migrations").run(&db_pool).await?;

    let state = AppState::new(db_pool, config);
    let app = build_router(state);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    tracing::info!("Server listening on port {}", port);
    axum::serve(listener, app).await?;

    Ok(())
}
```

**`src/config.rs`** — 환경변수 로딩
```rust
use anyhow::Result;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_expires_in: u64,
    pub server_port: u16,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            database_url: std::env::var("DATABASE_URL")?,
            jwt_secret: std::env::var("JWT_SECRET")?,
            jwt_expires_in: std::env::var("JWT_EXPIRES_IN")
                .unwrap_or_else(|_| "86400".to_string())
                .parse()?,
            server_port: std::env::var("SERVER_PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()?,
        })
    }
}
```

**`src/error.rs`** — 공통 에러 타입
```rust
use axum::{http::StatusCode, response::{IntoResponse, Response}, Json};
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Not found")]
    NotFound,
    #[error("Unauthorized")]
    Unauthorized,
    #[error("Bad request: {0}")]
    BadRequest(String),
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    #[error("Internal server error")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::NotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::Database(_) | AppError::Internal(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
        };
        (status, Json(json!({"error": message}))).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;
```

**`src/http/state.rs`** — AppState (Arc로 공유)
```rust
use crate::config::Config;
use sqlx::PgPool;

/// 앱 시작 시 한 번 초기화, Arc로 매 요청에 Clone.
/// 서비스는 Arc<dyn Trait>로 보관해 testability 확보.
#[derive(Clone)]
pub struct AppState {
    pub db_pool: PgPool,
    pub config: Config,
    // 새 서비스 추가 시 여기에 Arc<dyn XxxService> 필드 추가
}

impl AppState {
    pub fn new(db_pool: PgPool, config: Config) -> Self {
        Self { db_pool, config }
    }
}
```

**`src/http/router.rs`** — route_table() 패턴

새 엔드포인트 추가 = `route_table()`에 한 줄 추가. 핸들러 미존재/시그니처 불일치는 컴파일 에러로 즉시 검출된다.

```rust
use axum::{
    routing::{get, post, MethodRouter},
    Router,
};
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::http::handlers::health;
use crate::http::state::AppState;

/// 전체 API 라우트 테이블.
///
/// 새 엔드포인트 추가 = 이 목록에 한 줄 추가.
/// 핸들러 함수가 존재하지 않거나 Axum Handler trait 시그니처가 맞지 않으면
/// 이 함수의 컴파일 시점에 에러가 발생한다.
fn route_table() -> Vec<(&'static str, MethodRouter<AppState>)> {
    vec![
        ("/health", get(health::health_check)),
        // 새 엔드포인트는 여기에 추가:
        // ("/api/v1/items", get(item::list_items).post(item::create_item)),
        // ("/api/v1/items/:id", get(item::get_item)),
    ]
}

pub fn build_router(state: AppState) -> Router {
    route_table()
        .into_iter()
        .fold(Router::new(), |router, (path, handler)| {
            router.route(path, handler)
        })
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state)
}
```

**`src/http/macros.rs`** — 엔드포인트 매크로 (컴파일타임 강제)

Request/Response 구조체 + 핸들러 함수를 한 번에 생성. 반환 타입이 `Json<XxxResponse>`로 고정되어 `impl IntoResponse` 남용 불가.

> **hygiene 주의**: `$state:ident`, `$req:ident`, `$id:ident`를 metavariable로 캡처해야 `$body` 블록에서 사용 가능. 리터럴 식별자는 hygiene으로 body에서 보이지 않는다.

```rust
/// POST + JSON body → typed Response
///
/// ```rust,ignore
/// post_endpoint! {
///     fn create_item(state, req: CreateItemRequest {
///         name: String,
///     }) -> CreateItemResponse {
///         id: uuid::Uuid,
///         name: String,
///     }
///     {
///         let item = state.item_service.create(&req.name).await?;
///         Ok(Json(CreateItemResponse { id: item.id, name: item.name }))
///     }
/// }
/// ```
#[macro_export]
macro_rules! post_endpoint {
    (
        fn $handler:ident($state:ident, $req:ident: $req_name:ident {
            $( $req_field:ident : $req_ty:ty ),* $(,)?
        }) -> $resp_name:ident {
            $( $resp_field:ident : $resp_ty:ty ),* $(,)?
        }
        $body:block
    ) => {
        #[derive(Debug, serde::Deserialize)]
        pub struct $req_name { $( pub $req_field: $req_ty, )* }

        #[derive(Debug, serde::Serialize)]
        pub struct $resp_name { $( pub $resp_field: $resp_ty, )* }

        pub async fn $handler(
            axum::extract::State($state): axum::extract::State<$crate::http::state::AppState>,
            axum::Json($req): axum::Json<$req_name>,
        ) -> ::std::result::Result<axum::Json<$resp_name>, $crate::error::AppError>
        $body
    };
}

/// GET /:id → typed Response
///
/// ```rust,ignore
/// get_endpoint_with_id! {
///     fn get_item(state, id) -> GetItemResponse {
///         id: uuid::Uuid,
///         name: String,
///     }
///     {
///         let item = state.item_service.get(id).await?;
///         Ok(Json(GetItemResponse { id: item.id, name: item.name }))
///     }
/// }
/// ```
#[macro_export]
macro_rules! get_endpoint_with_id {
    (
        fn $handler:ident($state:ident, $id:ident) -> $resp_name:ident {
            $( $resp_field:ident : $resp_ty:ty ),* $(,)?
        }
        $body:block
    ) => {
        #[derive(Debug, serde::Serialize)]
        pub struct $resp_name { $( pub $resp_field: $resp_ty, )* }

        pub async fn $handler(
            axum::extract::State($state): axum::extract::State<$crate::http::state::AppState>,
            axum::extract::Path($id): axum::extract::Path<uuid::Uuid>,
        ) -> ::std::result::Result<axum::Json<$resp_name>, $crate::error::AppError>
        $body
    };
}

/// POST /:id (body 없음) → typed Response
#[macro_export]
macro_rules! post_endpoint_with_id {
    (
        fn $handler:ident($state:ident, $id:ident) -> $resp_name:ident {
            $( $resp_field:ident : $resp_ty:ty ),* $(,)?
        }
        $body:block
    ) => {
        #[derive(Debug, serde::Serialize)]
        pub struct $resp_name { $( pub $resp_field: $resp_ty, )* }

        pub async fn $handler(
            axum::extract::State($state): axum::extract::State<$crate::http::state::AppState>,
            axum::extract::Path($id): axum::extract::Path<uuid::Uuid>,
        ) -> ::std::result::Result<axum::Json<$resp_name>, $crate::error::AppError>
        $body
    };
}
```

**`src/http/mod.rs`**
```rust
pub mod handlers;
pub mod macros;
pub mod router;
pub mod state;
```

**`src/http/handlers/mod.rs`**, **`src/domain/mod.rs`**, **`src/domain/ports/mod.rs`**, **`src/application/mod.rs`**, **`src/adapters/mod.rs`**, **`src/adapters/postgres/mod.rs`** — 빈 모듈 파일

#### 4-4. tests/helpers/app.rs — TestApp 패턴 (testcontainers 기반)

testcontainers를 사용해 `cargo test` 실행 시 자동으로 격리된 PostgreSQL 컨테이너를 띄운다. 로컬 PostgreSQL 없이도 동작하며, 프로세스당 컨테이너 1개를 공유해 성능을 최적화한다.

> **주의**: `std::mem::forget(container)` 패턴은 사용하지 않는다. Drop이 호출되지 않아 testcontainers가 컨테이너를 정리하지 못한다. 대신 `OnceCell<(ContainerAsync<Postgres>, u16)>`에 핸들을 보관한다.

```rust
use {crate_name}_backend::config::Config;
use {crate_name}_backend::http::{router::build_router, state::AppState};
use sqlx::{postgres::PgPoolOptions, Connection, Executor, PgConnection, PgPool};
use std::net::SocketAddr;
use testcontainers_modules::{
    postgres::Postgres,
    testcontainers::{runners::AsyncRunner, ContainerAsync},
};
use tokio::sync::OnceCell;
use uuid::Uuid;

/// 프로세스당 컨테이너를 공유한다.
/// 핸들을 OnceCell에 보관하여 프로세스 종료 시까지 컨테이너가 살아있도록 한다.
/// Ryuk(testcontainers 자동정리 데몬)가 프로세스 종료 후 컨테이너를 제거한다.
static SHARED_CONTAINER: OnceCell<(ContainerAsync<Postgres>, u16)> = OnceCell::const_new();

async fn shared_postgres_port() -> u16 {
    SHARED_CONTAINER
        .get_or_init(|| async {
            let container: ContainerAsync<Postgres> =
                Postgres::default().start().await.expect("Failed to start PostgreSQL container");
            let port = container
                .get_host_port_ipv4(5432)
                .await
                .expect("Failed to get container port");
            (container, port)
        })
        .await
        .1
}

/// 통합 테스트 하네스.
/// 각 인스턴스는 격리된 test_<uuid> DB + 랜덤 포트 Axum 서버를 스핀업한다.
pub struct TestApp {
    pub address: String,
    #[allow(dead_code)]
    pub db_pool: PgPool,
    db_name: String,
    admin_db_url: String,
}

impl TestApp {
    pub async fn spawn() -> Self {
        let port = shared_postgres_port().await;
        let admin_db_url = format!("postgres://postgres:postgres@localhost:{}/postgres", port);
        let db_name = format!("test_{}", Uuid::new_v4().to_string().replace('-', "_"));

        create_test_database(&admin_db_url, &db_name).await;

        let test_db_url = format!(
            "postgres://postgres:password@localhost:{}/{}",
            port, db_name
        );
        let db_pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&test_db_url)
            .await
            .expect("Failed to connect to test database");

        sqlx::migrate!("./migrations")
            .run(&db_pool)
            .await
            .expect("Failed to run migrations");

        let config = Config {
            database_url: test_db_url,
            jwt_secret: "test-secret-key".to_string(),
            jwt_expires_in: 86400,
            server_port: 0,
        };

        let state = AppState::new(db_pool.clone(), config);
        let app = build_router(state);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("Failed to bind");
        let addr: SocketAddr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        TestApp {
            address: format!("http://{}", addr),
            db_pool,
            db_name,
            admin_db_url,
        }
    }
}

impl Drop for TestApp {
    fn drop(&mut self) {
        let admin_url = self.admin_db_url.clone();
        let db_name = self.db_name.clone();

        std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("Failed to build cleanup runtime");
            rt.block_on(drop_test_database(&admin_url, &db_name));
        });
    }
}

async fn create_test_database(admin_url: &str, db_name: &str) {
    let mut conn = PgConnection::connect(admin_url)
        .await
        .expect("Failed to connect to admin DB");
    conn.execute(format!("CREATE DATABASE \"{}\"", db_name).as_str())
        .await
        .expect("Failed to create test database");
}

async fn drop_test_database(admin_url: &str, db_name: &str) {
    let mut conn = match PgConnection::connect(admin_url).await {
        Ok(c) => c,
        Err(_) => return,
    };
    // 활성 연결 강제 종료 후 DB 삭제
    let _ = conn
        .execute(
            format!(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
                 WHERE datname = '{}' AND pid <> pg_backend_pid()",
                db_name
            )
            .as_str(),
        )
        .await;
    let _ = conn
        .execute(format!("DROP DATABASE IF EXISTS \"{}\"", db_name).as_str())
        .await;
}
```

**`tests/helpers/mod.rs`**:
```rust
pub mod app;
pub use app::TestApp;
```

#### 4-5. .github/workflows/ci.yml

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

env:
  CARGO_TERM_COLOR: always
  DATABASE_URL: postgres://postgres:password@localhost:5432/{project_db}
  JWT_SECRET: ci-test-secret-key
  JWT_EXPIRES_IN: 86400
  SERVER_PORT: 8080

jobs:
  test:
    name: Check, Lint & Test
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: password
          POSTGRES_DB: {project_db}
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Rust stable toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt

      - name: Cache cargo registry and build artifacts
        uses: Swatinem/rust-cache@v2

      - name: cargo check
        run: cargo check --all-targets

      - name: cargo fmt --check
        run: cargo fmt --check

      - name: cargo clippy
        run: cargo clippy --all-targets -- -D warnings

      - name: cargo test
        run: cargo test --all-targets
```

#### 4-6. docker-compose.yml — 로컬 개발 DB

로컬 `make run` 용 PostgreSQL. `cargo test`는 testcontainers가 자동 처리하므로 이 컨테이너 불필요.

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: {project_db}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

#### 4-7. Makefile

```makefile
.PHONY: run test db-up db-down migrate

db-up:
	docker compose up -d

db-down:
	docker compose down

migrate:
	sqlx migrate run

run: db-up migrate
	cargo run

test:
	cargo test
```

#### 4-8. migrations/00001_init.sql

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- testcontainers 호환성 필수

-- 첫 번째 마이그레이션: 기본 테이블 정의
-- 예시:
-- CREATE TABLE users (
--     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     email TEXT NOT NULL UNIQUE,
--     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- );
```

> **주의**: `CREATE EXTENSION IF NOT EXISTS pgcrypto;`는 testcontainers가 사용하는 PostgreSQL 이미지에서 `gen_random_uuid()` 등의 함수를 사용할 때 필요하다. 반드시 첫 마이그레이션에 포함한다.

#### 4-9. .env.example

```
DATABASE_URL=postgres://postgres:password@localhost:5432/{project_db}
JWT_SECRET=your-secret-key-here
JWT_EXPIRES_IN=86400
SERVER_PORT=8080
```

#### 4-10. .gitignore

```
/target
.env
*.pem
```

#### 4-12. 검증 및 초기 커밋

```bash
cd {project-root}/{project}-backend
cargo check          # 반드시 통과
cargo fmt
cargo clippy --all-targets -- -D warnings

git add .
git commit -m "chore: initialize Rust/Axum backend with hexagonal architecture and testcontainers"
```

---

### Step 5: 프론트엔드 초기화 (Next.js 14 + TypeScript)

`{project-root}/{project}-frontend/` 에서 실행한다.

#### 5-1. git init + create-next-app

```bash
cd {project-root}/{project}-frontend

git init

npx create-next-app@latest . \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --no-src-dir \
  --import-alias "@/*"
```

#### 5-2. 추가 패키지 설치

```bash
# 상태 관리 + 서버 상태
npm install zustand @tanstack/react-query

# UI 컴포넌트 (shadcn/ui 초기화)
npx shadcn@latest init

# 테스트 도구
npm install -D vitest @vitest/coverage-v8 @testing-library/react @testing-library/jest-dom \
  @vitejs/plugin-react jsdom \
  @playwright/test

# Playwright 브라우저 설치
npx playwright install --with-deps chromium
```

#### 5-3. 디렉토리 구조 생성

create-next-app이 생성하는 `src/` 없는 구조 대신, `src/` 기반 도메인 분리 구조로 정리한다.

```bash
mkdir -p src/app
mkdir -p src/features           # 도메인별 분리 (API + 타입 + 상태)
mkdir -p src/shared/api         # API 클라이언트 등 공통 유틸
mkdir -p src/components/ui
mkdir -p tests/unit
mkdir -p tests/e2e
mkdir -p .github/workflows
```

최종 디렉토리 구조:
```
src/
├── app/                        # Next.js App Router
│   ├── layout.tsx
│   ├── page.tsx
│   └── (domain)/               # 도메인별 라우트
│
├── features/                   # 도메인별 모듈
│   └── {domain}/
│       ├── types.ts            # {Action}Request / {Action}Response 인터페이스
│       ├── api/
│       │   └── index.ts        # export async function actionName(req): Promise<Response>
│       └── store.ts            # Zustand store (필요 시)
│
└── shared/
    └── api/
        └── client.ts           # apiClient (fetch 래퍼)
```

#### 5-4. src/shared/api/client.ts — API 클라이언트

```typescript
const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...init?.headers },
    ...init,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error ?? res.statusText);
  }
  return res.json() as Promise<T>;
}

export const apiClient = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(body) }),
};
```

#### 5-5. features/{domain} 패턴 예시

새 도메인 추가 시 이 구조를 복사한다.

**`src/features/{domain}/types.ts`**
```typescript
// ── Domain models ─────────────────────────────────────────────────────────────
export interface Item {
  id: string;
  name: string;
  created_at: string;
}

// ── Request types ─────────────────────────────────────────────────────────────
export interface CreateItemRequest {
  name: string;
}

// ── Response types (BE response structs의 FE 대응) ─────────────────────────────
// 새 엔드포인트 추가 시: 여기에 {Action}Response 타입 추가 후 api/index.ts에서 사용
export interface CreateItemResponse extends Item {}

export interface ListItemsResponse {
  items: Item[];
  total: number;
}
```

**`src/features/{domain}/api/index.ts`**
```typescript
import { apiClient } from '@/shared/api/client';
import type {
  CreateItemRequest,
  CreateItemResponse,
  Item,
  ListItemsResponse,
} from '../types';

// 모든 API 함수는 명명된 타입 사용. 인라인 타입(Promise<{ field: Type }>) 금지.
export async function createItem(req: CreateItemRequest): Promise<CreateItemResponse> {
  return apiClient.post('/api/v1/items', req);
}

export async function getItem(itemId: string): Promise<Item> {
  return apiClient.get(`/api/v1/items/${itemId}`);
}

export async function listItems(): Promise<ListItemsResponse> {
  return apiClient.get('/api/v1/items');
}
```

#### 5-6. vitest.config.ts

```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/setup.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/features/**/*.{ts,tsx}'],
      exclude: ['src/features/**/*.test.{ts,tsx}', 'src/features/**/types.ts', 'src/features/**/index.ts'],
      reporter: ['text', 'json-summary'],
      // 초기 세팅 시 threshold 없이 시작 → 테스트 작성 후 측정값으로 설정
      // thresholds: { statements: 95, branches: 90, functions: 90, lines: 95 },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
})
```

#### 5-7. tests/setup.ts

```typescript
import '@testing-library/jest-dom'
```

#### 5-8. playwright.config.ts

```typescript
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  use: {
    baseURL: 'http://localhost:3000',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
})
```

#### 5-9. .github/workflows/ci.yml

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    name: Type-check, Lint & Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Type check
        run: npx tsc --noEmit

      - name: Lint
        run: npm run lint

      - name: Unit & Integration tests
        run: npx vitest run

      - name: Coverage
        run: npx vitest run --coverage
        # vitest.config.ts에 thresholds 설정 시 미달이면 자동 실패

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: E2E tests
        run: npx playwright test
```

#### 5-10. .env.example

```
NEXT_PUBLIC_API_URL=http://localhost:8080
```

#### 5-11. 초기 커밋

```bash
cd {project-root}/{project}-frontend
git add .
git commit -m "chore: initialize Next.js 14 frontend with Zustand, TanStack Query, Playwright"
```

---

### Step 6: Hook 설정

프로젝트 루트(`{project-root}`)에서 실행한다. 아래의 모든 스크립트에서 `{PROJECT_ROOT}`를 실제 프로젝트 절대 경로로 교체한다.

#### 6-1. cargo-nextest 설치 (BE 개발 전 1회)

```bash
cargo install cargo-nextest --locked
```

#### 6-2. Hook 스크립트 생성 (11개)

---

**`.claude/hooks/block-git-push.sh`** — PreToolUse(Bash): git push 자동 차단

```bash
#!/bin/bash
COMMAND=$(jq -r '.tool_input.command // ""' 2>/dev/null)
if echo "$COMMAND" | grep -qE '^\s*git push'; then
  echo '{"continue": false, "stopReason": "git push는 사용자가 명시적으로 요청할 때만 실행합니다."}'
  exit 0
fi
```

---

**`.claude/hooks/mark-pending.sh`** — PostToolUse(Write|Edit): 마커 관리

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

RUST_MARKER="{PROJECT_ROOT}/.claude/.pending-rust-check"
SPEC_MARKER="{PROJECT_ROOT}/.claude/.pending-spec-check"

# specification/ 작성 시 마커 제거
if echo "$FILE_PATH" | grep -qE 'specification/'; then
  rm -f "$RUST_MARKER" "$SPEC_MARKER"
  exit 0
fi

# .claude/code-rules.md 작성 시 spec 마커만 제거
if echo "$FILE_PATH" | grep -qE '\.claude/code-rules\.md$'; then
  rm -f "$SPEC_MARKER"
  exit 0
fi

# .rs 변경 시 rust-check 마커 생성
if echo "$FILE_PATH" | grep -qE '{PROJECT_NAME}-backend/.*\.rs$'; then
  touch "$RUST_MARKER"
fi

# 구조적 BE 파일 변경 시 spec-check 마커 생성
if echo "$FILE_PATH" | grep -qE '{PROJECT_NAME}-backend/src/(http/(mod|macros|router|state)\.rs|http/background/|domain/ports/)'; then
  touch "$SPEC_MARKER"
fi
```

---

**`.claude/hooks/cargo-check-on-edit.sh`** — PostToolUse(Write|Edit): cargo check + 모듈 단위 테스트

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q '{PROJECT_NAME}-backend'; then exit 0; fi

BACKEND_DIR="{PROJECT_ROOT}/{PROJECT_NAME}-backend"
cd "$BACKEND_DIR" || exit 0

CHECK_OUTPUT=$(cargo check 2>&1)
if [ $? -ne 0 ]; then echo "$CHECK_OUTPUT" >&2; exit 2; fi

BASENAME=$(basename "$FILE_PATH")

# mod.rs, lib.rs → 전체 단위 테스트
if echo "$BASENAME" | grep -qE '^(mod|lib|main)\.rs$'; then
  cargo nextest run --lib 2>&1; exit $?
fi

# tests/ 하위 → 해당 integration test만
if echo "$FILE_PATH" | grep -qE '{PROJECT_NAME}-backend/tests/[^/]+\.rs$'; then
  TEST_NAME=$(basename "$FILE_PATH" .rs)
  cargo nextest run --test "$TEST_NAME" 2>&1; exit $?
fi

# src/ 하위 → 모듈 경로로 변환하여 단위 테스트 필터
if echo "$FILE_PATH" | grep -qE '{PROJECT_NAME}-backend/src/'; then
  MODULE=$(echo "$FILE_PATH" | sed 's|.*/{PROJECT_NAME}-backend/src/||' | sed 's|\.rs$||' | sed 's|/|::|g')
  cargo nextest run --lib --filter-expr "test(~$MODULE)" 2>&1; exit $?
fi
```

---

**`.claude/hooks/unit-test-check-rust.sh`** — PostToolUse(Write|Edit): #[cfg(test)] 존재 확인

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.rs$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -qE '{PROJECT_NAME}-backend/src/(application|adapters)/'; then exit 0; fi

BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(mod|main|lib|config|error)\.rs$'; then exit 0; fi
if [ ! -f "$FILE_PATH" ]; then exit 0; fi

if ! grep -q '#\[cfg(test)\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $BASENAME — #[cfg(test)] mod tests 블록이 필요합니다" >&2
  exit 2
fi
if ! grep -q '#\[test\]' "$FILE_PATH"; then
  echo "단위 테스트 없음: $BASENAME — #[test] 함수가 최소 1개 필요합니다" >&2
  exit 2
fi
```

---

**`.claude/hooks/tsc-check-on-edit.sh`** — PostToolUse(Write|Edit): TypeScript 타입 체크

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q '{PROJECT_NAME}-frontend'; then exit 0; fi

cd "{PROJECT_ROOT}/{PROJECT_NAME}-frontend" || exit 0
TSC_OUTPUT=$(npm run type-check 2>&1)
if [ $? -ne 0 ]; then echo "$TSC_OUTPUT" >&2; exit 2; fi
```

---

**`.claude/hooks/unit-test-check-ts.sh`** — PostToolUse(Write|Edit): .test.ts 파일 존재 확인

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then exit 0; fi
if ! echo "$FILE_PATH" | grep -q '{PROJECT_NAME}-frontend/src/features/'; then exit 0; fi

BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^(index|types)\.(ts|tsx)$'; then exit 0; fi
if echo "$FILE_PATH" | grep -q '\.test\.'; then exit 0; fi

DIRNAME=$(dirname "$FILE_PATH")
NAMEBASE="${BASENAME%.*}"
EXT="${BASENAME##*.}"
TEST_FILE="$DIRNAME/${NAMEBASE}.test.${EXT}"

if [ ! -f "$TEST_FILE" ]; then
  echo "테스트 파일 없음: $TEST_FILE" >&2
  exit 2
fi
```

---

**`.claude/hooks/docker-cleanup-after-test.sh`** — PostToolUse(Bash): 테스트 후 Docker 컨테이너 정리

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if ! echo "$COMMAND" | grep -qE 'cargo (test|nextest)'; then exit 0; fi
if ! docker info > /dev/null 2>&1; then exit 0; fi

TC_CONTAINERS=$(docker ps -aq --filter "label=org.testcontainers.managed-by=testcontainers" 2>/dev/null)
if [ -n "$TC_CONTAINERS" ]; then
  docker stop $TC_CONTAINERS > /dev/null 2>&1
  docker rm $TC_CONTAINERS > /dev/null 2>&1
fi
docker system prune -f > /dev/null 2>&1
```

---

**`.claude/hooks/check-compile-on-stop.sh`** — Stop: 컴파일/스펙 마커 있으면 응답 차단

```bash
#!/bin/bash
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi

RUST_MARKER="{PROJECT_ROOT}/.claude/.pending-rust-check"
SPEC_MARKER="{PROJECT_ROOT}/.claude/.pending-spec-check"

if [ -f "$RUST_MARKER" ]; then
  BACKEND_DIR="{PROJECT_ROOT}/{PROJECT_NAME}-backend"
  CHECK_OUTPUT=$(cd "$BACKEND_DIR" && cargo check 2>&1)
  if [ $? -ne 0 ]; then
    echo "{\"decision\": \"block\", \"reason\": \"cargo check 실패. 컴파일 오류를 수정한 후 완료하세요.\"}"
    exit 0
  fi
fi

if [ -f "$SPEC_MARKER" ]; then
  echo "{\"decision\": \"block\", \"reason\": \"구조적 BE 파일이 변경됐는데 specification/ 업데이트가 없습니다.\"}"
  exit 0
fi
```

---

**`.claude/hooks/spec-sync-check.sh`** — Stop: 스펙 동기화 경고 (차단 아님)

```bash
#!/bin/bash
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then exit 0; fi

cd "{PROJECT_ROOT}" || exit 0
git rev-parse --git-dir &>/dev/null || exit 0

CHANGED=$(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)
CHANGED=$(echo "$CHANGED" | sort -u)
[ -z "$CHANGED" ] && exit 0

MISSING_SPECS=()
check_spec() {
  local spec_file="$1"
  echo "$CHANGED" | grep -q "^${spec_file}$" && return
  MISSING_SPECS+=("$spec_file")
}

echo "$CHANGED" | grep -qE "^{PROJECT_NAME}-backend/src/(application|domain|adapters)/" && check_spec "specification/dev/backend.md"
echo "$CHANGED" | grep -qE "^{PROJECT_NAME}-backend/src/http/(handlers/|router\.rs)" && check_spec "specification/dev/api.md"
echo "$CHANGED" | grep -qE "^{PROJECT_NAME}-frontend/src/features/" && check_spec "specification/dev/frontend.md"

[ ${#MISSING_SPECS[@]} -eq 0 ] && exit 0

echo "⚠️  스펙 동기화 확인 필요:" >&2
printf "  - %s\n" "${MISSING_SPECS[@]}" >&2
```

---

**`.claude/hooks/coverage-check-fe.sh`** — Stop: FE 커버리지 측정

```bash
#!/bin/bash
FE_DIR="{PROJECT_ROOT}/{PROJECT_NAME}-frontend"
[ ! -d "$FE_DIR" ] && exit 0
[ ! -d "$FE_DIR/node_modules" ] && exit 0

cd "$FE_DIR" || exit 0
npm test -- --run --coverage --silent 2>&1 | grep -E "^(All files|src/|Coverage|Threshold)" >&2
exit ${PIPESTATUS[0]}
```

---

**`.claude/hooks/clear-marker-on-start.sh`** — SessionStart: 마커 초기화

```bash
#!/bin/bash
rm -f "{PROJECT_ROOT}/.claude/.pending-rust-check"
rm -f "{PROJECT_ROOT}/.claude/.pending-spec-check"
```

---

#### 6-3. 실행 권한 부여

```bash
chmod +x {project-root}/.claude/hooks/*.sh
```

#### 6-4. `.claude/settings.json` 생성

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/block-git-push.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/clear-marker-on-start.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/docker-cleanup-after-test.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/mark-pending.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/cargo-check-on-edit.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/tsc-check-on-edit.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/unit-test-check-rust.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/unit-test-check-ts.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/check-compile-on-stop.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/coverage-check-fe.sh"
          },
          {
            "type": "command",
            "command": "{PROJECT_ROOT}/.claude/hooks/spec-sync-check.sh"
          }
        ]
      }
    ]
  }
}
```

#### 6-5. `.gitignore`에 마커 파일 추가

```
.claude/.pending-rust-check
.claude/.pending-spec-check
```

#### 6-6. 최종 Hook 구조

```
{project-root}/
├── .claude/
│   ├── settings.json
│   └── hooks/
│       ├── PreToolUse
│       │   └── block-git-push.sh        ← git push 자동 차단
│       ├── PostToolUse(Write|Edit)
│       │   ├── mark-pending.sh          ← 마커 관리 (rust/spec)
│       │   ├── cargo-check-on-edit.sh   ← cargo check + nextest 모듈 단위
│       │   ├── tsc-check-on-edit.sh     ← TypeScript 타입 체크
│       │   ├── unit-test-check-rust.sh  ← #[cfg(test)] 존재 확인
│       │   └── unit-test-check-ts.sh    ← .test.ts 파일 존재 확인
│       ├── PostToolUse(Bash)
│       │   └── docker-cleanup-after-test.sh ← testcontainers 컨테이너 정리
│       ├── SessionStart
│       │   └── clear-marker-on-start.sh ← 마커 초기화
│       └── Stop
│           ├── check-compile-on-stop.sh ← 컴파일/스펙 검증 (차단)
│           ├── coverage-check-fe.sh     ← FE 커버리지 측정
│           └── spec-sync-check.sh       ← 스펙 동기화 경고
```

---

## 완료 보고 형식

모든 단계 완료 후 사용자에게 보고:

```
## 프로젝트 초기화 완료

**프로젝트**: {project-name}
**경로**: {project-root}

### 생성된 구조
{디렉토리 트리}

### 스펙 문서
- [TODO 항목 목록] — 사용자가 채워야 할 미결 항목

### Hook 시스템 (11개)
- `PreToolUse`: git push 차단
- `PostToolUse(Write|Edit)`: 마커 관리, cargo check + nextest, tsc, 단위 테스트 존재 확인
- `PostToolUse(Bash)`: cargo test/nextest 후 Docker 컨테이너 자동 정리
- `SessionStart`: 마커 초기화
- `Stop`: 컴파일/스펙 검증, FE 커버리지, 스펙 동기화 경고

### 다음 단계
1. .env 파일 생성: `cp {project}-backend/.env.example {project}-backend/.env`
2. DB 연결 확인: `cd {project}-backend && cargo test`
3. 첫 번째 도메인 설계: specification/dev/api.md 검토 후 마이그레이션 작성
```

---

## 규칙

- **추측하지 않는다**: 서비스 이름, 핵심 엔티티가 불분명하면 작업 시작 전 확인한다.
- **TODO 표시**: 서비스 설명만으로 확정할 수 없는 내용은 `[TODO: 확인 필요]`로 표시하고 진행한다.
- **cargo check 필수**: 백엔드 초기화 후 반드시 `cargo check`를 실행하고 통과를 확인한다.
- **단계별 순차 실행**: 각 단계는 순서대로 실행한다 (스펙 문서 → 백엔드 → 프론트엔드 → Hook 설정).
- **파일 덮어쓰기 금지**: 이미 존재하는 파일이 있으면 사용자에게 확인 후 진행한다.
