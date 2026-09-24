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

```
[ ] 1. domain/ports/ 에 필요한 trait 정의 (없으면 추가)
[ ] 2. adapters/ 에 구현체 작성
[ ] 3. application/ 에 서비스 로직 작성
[ ] 4. http/handlers/ 에 핸들러 작성 (매크로 패턴 사용, 아래 참조)
[ ] 5. http/router.rs 의 route_table() 에 한 줄 추가
[ ] 6. 통합 테스트 작성 (TestApp + Mock 주입)
[ ] 7. cargo check && cargo test 통과
[ ] 8. specification/dev/api.md 업데이트
```

### 핸들러 작성 규칙

**표준 케이스 → 매크로 사용 (backend/src/http/macros.rs)**

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

```
[ ] 1. src/features/{domain}/types.ts 에 {Action}Request / {Action}Response 인터페이스 추가
[ ] 2. src/features/{domain}/api/index.ts 에 함수 추가:
        export async function actionName(req: ActionRequest): Promise<ActionResponse>
[ ] 3. npm run type-check && npm test 통과
```

### 타입 네이밍 규칙

| 종류 | 패턴 | 예시 |
|------|------|------|
| 요청 body | `{Action}Request` | `CreateItemRequest` |
| 응답 | `{Action}Response` | `CreateItemResponse` |
| 도메인 모델 | 명사형 | `Item`, `User` |

- `{Action}Request`, `{Action}Response` → `src/features/{domain}/types.ts` (예외 파일이므로 테스트 불필요)
- BE `XxxResponse` 구조체와 1:1 대응 유지

## 파일별 단위 테스트 요구사항

- `backend/src/application/`, `backend/src/adapters/` 하위 .rs 파일: `#[cfg(test)] mod tests` 필수
- `frontend/src/features/` 하위 .ts/.tsx 파일: 동일 경로 `.test.ts` 파일 필수
- 예외: `mod.rs`, `main.rs`, `lib.rs`, `config.rs`, `error.rs`, `index.ts`, `types.ts`
