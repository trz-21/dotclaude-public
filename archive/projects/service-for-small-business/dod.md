# 작업 완료 기준 (Definition of Done)

코드 수정이 포함된 모든 작업은 아래가 **모두** 충족돼야 "완료"다.

## 체크리스트

- [ ] **이슈**: 작업 단위가 GitHub Issue로 등록돼 있다 (`#N`) — `.claude/github-workflow.md`
- [ ] **컴파일/타입**: `cargo check` (BE) / `npm run type-check` (FE) 통과
- [ ] **테스트**: `cargo test` (BE) / `npm test -- --run` (FE) 전체 통과
- [ ] **작업 로그**: **PR 본문**에 `Closes #N` + 작업 요약 (기존 `docs/works` 대체)
- [ ] **스펙 동기화**: 기능/설계 변경 시 **GitHub Wiki** 해당 페이지 업데이트
- [ ] **커밋**: 작업 단위로 git commit (`.claude/commit-rules.md` 참조)

## 검증 명령어

```bash
# 백엔드
cd backend
cargo check
cargo test

# 프론트엔드
cd frontend
npm run type-check
npm test -- --run
```

## 서브에이전트 주의사항

훅은 메인 Claude에만 적용된다. 서브에이전트에게 작업을 위임할 경우,
메인이 서브에이전트 완료 후 직접 검증해야 한다:

1. 해당 명령어 실행 (cargo check, npm run type-check, cargo test, npm test -- --run)
2. 작업이 GitHub Issue(`#N`)에 연결돼 있고, 완료 시 PR(`Closes #N`)로 기록되는지 확인
3. 모두 통과 시에만 작업 완료 처리
