# GitHub 작업 흐름 (Issue → 작업 → PR → Wiki)

문서화는 로컬 `docs/` 대신 **GitHub Issue / PR / Wiki**를 적극 활용한다.
모든 작업 단위는 아래 4단계를 **순서대로** 따른다.

```
1. 이슈 등록   →   2. 작업(harness)   →   3. PR(Closes #N)   →   4. Wiki 업데이트
```

- 레포: `<GITHUB_ORG>/<REPO>`
- 도구: `gh` CLI (인증됨), Wiki는 `*.wiki.git` 클론

---

## 1단계: 이슈 등록 (기존 `docs/plans` 대체)

작업을 시작하기 **전에** GitHub Issue로 작업 단위를 등록한다.
`/task-with-harness`의 "구현 계획"이 곧 이슈 본문이 된다.

```bash
gh issue create \
  --title "<작업 제목>" \
  --body "$(cat <<'EOF'
## 목표
<무엇을, 왜>

## 작업 항목
- [ ] 서브태스크 1 (대상 파일)
- [ ] 서브태스크 2

## 영향 범위
- BE / FE / 문서

## 테스트 전략
- <harness 관점: 단위/통합 테스트, 커버리지>
EOF
)"
```

- 반환된 이슈 번호(`#N`)를 브랜치/PR에서 참조한다.
- 큰 작업은 서브태스크 체크박스로 분해해 진행 상황을 이슈에서 추적한다.

---

## 2단계: 작업 (브랜치 + harness)

이슈 기반 브랜치를 만들고 `/task-with-harness`로 구현한다.

```bash
git checkout -b feature/issue-<N>-<slug>
```

- 브랜치 네이밍: `feature/issue-<N>-<slug>` (fix는 `fix/issue-<N>-<slug>`)
- harness 검증(컴파일/테스트/커버리지)은 `.claude/dod.md` 기준 그대로 유지한다.
- 커밋 규칙은 `.claude/commit-rules.md`. 커밋 메시지 본문에 `Refs #N` 또는 `#N`을 남긴다.
- **루트 단일 레포**이므로 프로젝트 루트에서 커밋한다 (backend/frontend는 별도 레포 아님).

---

## 3단계: 이슈 기반 PR (기존 `docs/works` 대체)

작업이 DoD를 충족하면 PR을 올린다. **PR 본문이 작업 로그 역할**을 한다.

```bash
git push -u origin feature/issue-<N>-<slug>
gh pr create \
  --base main \
  --title "<type>: <작업 제목>" \
  --body "$(cat <<'EOF'
Closes #<N>

## 작업 요약
<무엇을 구현했는지>

## 변경 내용
- <파일/모듈별 요약>

## 검증
- [ ] cargo check / cargo test (BE)
- [ ] npm run type-check / npm test -- --run (FE)
- [ ] 커버리지 유지/상승

## 주요 결정과 이유
- <설계 판단>

## Wiki 반영 예정
- <업데이트할 Wiki 페이지>
EOF
)"
```

- 본문 첫 줄에 **`Closes #N`**(또는 `Fixes #N`)을 넣어 머지 시 이슈 자동 종료.
- 리뷰가 필요하면 `gh pr create` 후 리뷰어 지정. `git push`는 사용자가 명시 요청 시에만 (`.claude/commit-rules.md`).

---

## 4단계: Wiki 업데이트 (스펙 = 최종 현황, canonical)

기능/설계가 바뀌면 **GitHub Wiki**의 해당 페이지를 최신 현황으로 갱신한다.
Wiki는 별도 git 레포다.

```bash
# 최초 1회: 작업 디렉터리 밖에 클론
git clone https://github.com/<GITHUB_ORG>/<REPO>.wiki.git /tmp/srv-wiki
cd /tmp/srv-wiki

# 페이지 수정 후
git add -A && git commit -m "docs: <페이지> 현황 갱신 (refs #<N>)" && git push
```

### Wiki 페이지 구성

| 페이지 | 내용 | 원본 스냅샷 |
|--------|------|-------------|
| `Home` | 개요 + 네비게이션 + 작업 흐름 요약 | — |
| `Workflow` | 이 문서의 GitHub 작업 흐름 | `.claude/github-workflow.md` |
| `Service-Overview` | 서비스 스펙 | `specification/service/overview.md` |
| `Tech-Stack` | 기술 스택 | `specification/dev/tech-stack.md` |
| `API` | API 엔드포인트 | `specification/dev/api.md` |
| `Backend` | 백엔드 구조 | `specification/dev/backend.md` |
| `Frontend` | 프론트엔드 구조 | `specification/dev/frontend.md` |
| `Harness` | 테스트 하네스 | `specification/dev/harness.md` |

- 페이지 파일명은 `<Page-Name>.md` (공백은 `-`).
- 페이지 간 링크는 `[[Page-Name]]` 또는 `[텍스트](Page-Name)`.

---

## 요약 체크리스트

- [ ] 작업 전 **이슈** 등록했는가? (`#N` 확보)
- [ ] `feature/issue-<N>-<slug>` 브랜치에서 작업했는가?
- [ ] harness(DoD) 검증을 통과했는가?
- [ ] **PR** 본문에 `Closes #N` + 작업 요약을 넣었는가?
- [ ] 스펙 변경분을 **Wiki**에 반영했는가?
