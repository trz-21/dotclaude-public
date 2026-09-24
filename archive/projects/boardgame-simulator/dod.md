# 작업 완료 기준 (Definition of Done)

코드 수정이 포함된 모든 작업은 아래가 **모두** 충족돼야 "완료"다.

## 체크리스트

- [ ] **컴파일/타입**: `cargo check` (BE) / `npm run type-check` (FE) 통과
- [ ] **테스트**: `cargo test` (BE) / `npm test` (FE) 전체 통과
- [ ] **작업 로그**: `docs/works/YYYYMMDD-[작업명].md` 작성
- [ ] **스펙 동기화**: 기능/설계 변경 시 `specification/` 해당 파일 업데이트
- [ ] **커밋**: 작업 단위로 git commit (`.claude/commit-rules.md` 참조)

## 검증 명령어

```bash
# 백엔드
cd boardgame-simulator-backend
cargo check
cargo test

# 프론트엔드
cd boardgame-simulator-frontend
npm run type-check
npm test
```

## 테스트 안전망 4단계

상세 내용: `specification/dev/harness.md`

```
Level 4: E2E 픽스처 테스트        ← 결정론적 시나리오 검증
Level 3: 통합 테스트 (API+DB+Mock) ← 컴포넌트 간 연동
Level 2: 단위 테스트              ← 개별 로직
Level 1: Rust 컴파일타임          ← 타입/trait/Result 계약
```

## Hook 강제

- `PostToolUse`: 소스 수정 시 즉시 `cargo check` / `npm run type-check` 실행
- `PostToolUse`: `application/`, `adapters/` 수정 시 `#[cfg(test)]` 존재 확인
- `PostToolUse`: `src/features/` 수정 시 `.test.ts` 파일 존재 확인
- `Stop`: `docs/works/` 로그 없이 소스 변경 시 응답 완료 차단

## 게임 엔진 작업 추가 조건

`GameEngine` trait 또는 구현체 (`TurnBasedEngine` 등) 수정/추가 시:

- [ ] `tests/fixtures/games/` 에 해당 시나리오 픽스처 최소 1개 추가 또는 기존 픽스처 업데이트
- [ ] `cargo test` 실행 시 픽스처 테스트 통과 확인

> 게임 엔진 로직 변경은 픽스처 없이 완료 처리 불가.

## 서브에이전트 주의사항

훅은 메인 Claude에만 적용된다. 서브에이전트에게 작업을 위임할 경우,
메인이 서브에이전트 완료 후 직접 검증해야 한다:

1. 해당 명령어 실행 (cargo check, npm run type-check, cargo test, npm test)
2. `docs/works/YYYYMMDD-*.md` 오늘 날짜 파일 존재 확인
3. 모두 통과 시에만 작업 완료 처리
