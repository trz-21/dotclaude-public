# Git Worktree 전략

여러 스킬 인스턴스가 동시에 실행되어도 충돌하지 않도록, **git worktree**로 메인 작업 디렉토리와 격리된 별도 작업 공간에서 코드를 수정한다.

## 원칙

- **읽기 전용 작업** (탐색, 분석): 메인 레포에서 수행한다. 충돌 없음.
- **쓰기 작업** (코드 수정, 검증, 커밋): git worktree에서 수행한다.
- 각 스킬 실행마다 **고유한 worktree**를 생성하여 완전히 격리한다.

## 디렉토리 구조

```
${REPOS_ROOT}/.worktrees/
  └── <WORKTREE_ID>/
      ├── repo-a/                 (git worktree)
      ├── repo-b/                 (git worktree)
      └── repo-c/                 (git worktree)
```

## WORKTREE_ID 생성 규칙

`<prefix>-<short-id>-<MMDD-HHMM>` 형식으로 생성한다.

### prefix
- 호출한 스킬에 따라 결정한다: `fix`, `refactor`, `feat` 등

### short-id
- **이슈 트래커 ID가 있으면**: 그 ID에서 추출 (예: `PROJ-123` → `proj-123`)
- **자연어 입력**: 핵심 키워드 2~3개 조합, 소문자+하이픈 (예: `login-timeout`)

### 타임스탬프
- `MMDD-HHMM` 형식으로 현재 시간 사용 (예: `0213-1430`)

### 예시
```
fix-proj-123-0213-1430
fix-login-timeout-0213-1432
```

## 변수 정의

스킬 내에서 아래 변수를 사용한다:

```
REPOS_ROOT    = 수정 대상 레포가 들어 있는 폴더 (git -C <레포> rev-parse --show-toplevel 의 상위 폴더. 보통 레포들을 모아 둔 작업 폴더 <WORKSPACE>)
WORKTREE_ID   = "<prefix>-<short-id>-<MMDD-HHMM>"
WORKTREE_BASE = "${REPOS_ROOT}/.worktrees/${WORKTREE_ID}"
WORKTREE_REPO = "${WORKTREE_BASE}/<REPO_NAME>"
```

## Worktree 생성

코드 수정 시작 전에 수행한다. 수정 대상 레포에만 worktree를 생성한다.

```bash
# 1. 베이스 디렉토리 생성
mkdir -p ${WORKTREE_BASE}

# 2. 수정 대상 레포별 worktree 생성 (병렬 실행 가능)
cd ${REPOS_ROOT}/<REPO> && \
  git worktree add ${WORKTREE_BASE}/<REPO> -b ${WORKTREE_ID}
```

- 브랜치명은 `WORKTREE_ID`와 동일하게 사용한다.
- 수정하지 않는 레포는 worktree를 생성하지 않는다.

## Worktree에서 커밋

```bash
cd ${WORKTREE_BASE}/<REPO>
git add <modified-files>
git commit -m "<commit message>"
```

- 여러 레포를 수정한 경우 각 worktree에서 별도 커밋한다.
- 커밋 메시지에 이슈 내용을 간결하게 참조한다.

## 후속 옵션

커밋 완료 후, 사용자에게 다음 옵션을 안내한다:

| 옵션 | 설명 | 명령어 |
|------|------|--------|
| **머지** | 원본 레포의 현재 브랜치로 머지 | `cd <원본레포> && git merge ${WORKTREE_ID}` |
| **PR 생성** | 브랜치를 push 후 PR | `cd <worktree> && git push -u origin ${WORKTREE_ID}` → `gh pr create` |
| **보류** | worktree를 유지하고 나중에 처리 | (별도 작업 불필요) |

## Worktree 정리

**머지 완료 시, 묻지 않고 즉시 정리한다.** 사용자가 머지를 지시한 시점에 정리 의도도 포함된 것으로 판단한다.

머지 직후 아래를 순서대로 실행한다:
```bash
# 1. 각 수정 레포의 worktree 제거
cd ${REPOS_ROOT}/<REPO>
git worktree remove ${WORKTREE_BASE}/<REPO>

# 2. 빈 디렉토리 정리
rmdir ${WORKTREE_BASE}

# 3. 임시 브랜치 삭제
cd ${REPOS_ROOT}/<REPO>
git branch -d ${WORKTREE_ID}
```

**보류 옵션을 선택한 경우에만** worktree를 유지한다.
