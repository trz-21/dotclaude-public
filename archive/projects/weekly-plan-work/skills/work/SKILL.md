---
name: work
description: 주차 단위 작업 진입점. plan.md 가 없으면 spec/weekN/ 을 흡수해 plan 초안을 먼저 작성하고 사용자 동의 후 commit. 그 후 plan.md 의 모든 미완 항목을 wave 단위 병렬로 끝까지 자동 진행하며 항목당 단일 commit 을 만든다 (한 호출 = plan + N 항목 = N+1 commit). 인자로 항목 번호 N 을 주면 그 항목만 단독 처리. weekN 으로 주차 지정. `plan` 키워드로 강제 plan 모드. commit message 의 placeholder 는 사용자가 /commit-review 로 채운다.
---

# /work [N | plan | plan-only] [weekN]

plan.md 가 없으면 plan 작성 + 모든 미완 항목 자동 진행. plan.md 가 있으면 모든 미완 항목 자동 진행. 한 항목만 처리하려면 N 인자.

## 호출 형식

| 호출 | 동작 |
|---|---|
| `/work` | 자동: plan.md 없으면 **plan + 모든 미완 항목 wave 단위 자동 진행**, 있으면 모든 미완 항목 wave 단위 자동 진행 |
| `/work 3` | 항목 모드, **#3 만 단독 처리** (자동 wave 진행 안 함) |
| `/work 3 week2` | week2 의 #3 만 단독 처리 |
| `/work plan` | 강제 plan 모드 (이미 있어도 갱신) → plan commit 후 모든 항목 wave 자동 진행 |
| `/work plan-only` | plan 모드만, 항목 진행 안 함 |
| `/work plan week2` | week2 의 plan + 모든 항목 자동 진행 |

## 모드 결정

### 1. 주차 결정
- 인자에 `weekN` 있으면 그것
- 아니면 `works/week*/plan.md` 중 `Status: in-progress` 인 디렉터리. 둘 이상이면 사용자에게 묻는다.
- works/ 에 일치 디렉터리가 없으면 `spec/week*/` 중 가장 큰 N (사용자가 새 스펙을 둔 주차로 추정).

### 2. 모드 결정
- `works/<주차>/plan.md` 없음 → **plan 모드** → 이어서 자동 항목 모드 (모든 미완)
- 인자가 `plan` → plan 모드 (강제, 기존 plan.md 갱신) → 이어서 자동 항목 모드
- 인자가 `plan-only` → plan 모드만, 항목 진행 보류
- 인자가 N (정수) → 항목 모드, **그 N 만 단독**
- 그 외 → 항목 모드, **모든 미완 항목 wave 단위 자동 진행**

---

## Plan 모드

### P1. 스펙 흡수
- `spec/<주차>/` 내 모든 파일(PDF/MD/TXT 등) 읽기
- 사용자가 별도로 보내준 메모/스펙이 있으면 함께 참고
- 이전 주차들의 plan.md (있으면) 도 일관성 점검을 위해 빠르게 훑는다 (스택·결정 사항 연속성)

### P2. 초안 작성
`works/<주차>/plan.md` 초안을 다음 섹션 그대로 작성:

```markdown
# Week <N> — <짧은 제목>

- Status: in-progress
- Spec: `spec/week<N>/`
- Started: <YYYY-MM-DD>
- Completed: —

## 목표
1~2 문단으로 이번 주차에서 만드는 것.

## 결정 사항
이 주차에서 새로 정한 스택/아키텍처와 근거. 이전 주차에서 이미 정한 것은 다시 적지 않는다 (CLAUDE.md 도 마찬가지).

## 작업 체크리스트
- [ ] **1. <항목 제목>** — 짧은 설명.
- [ ] **2. ...**
...

## 의존관계

| # | 항목 | 선행 | 수정 파일 |
|---|---|---|---|
| 1 | ... | (없음) | `path/a.ts`, `path/b.css` |
| 2 | ... | 1 | `path/c.ts` |
...

> "수정 파일" 컬럼 = 그 항목이 만들거나 수정할 주요 파일. 같은 wave 의 두 항목이 같은 파일을 수정해야 하면 wave 분할 필요 (병렬 spawn 시 충돌). plan 단계에서 미리 충돌을 발견해 wave 정의에 반영.

## 병렬 그룹 (subagent wave)
- **Wave 0**: `[1]`
- **Wave 1**: `[2, 3]`
...

## 검증
- 완료 판정 기준 (시각적 합치, 동작, 테스트 등)

## 회고
(완료 후 작성)
```

체크리스트 항목은 **한 commit 단위**가 되도록 쪼갠다. 너무 크면 쪼개고, 너무 작으면 합친다. 각 번호가 곧 commit message 의 #N. 수정 파일 컬럼은 의존관계 표 작성과 동시에 채워, 그 정보로 병렬 그룹(wave) 을 짠다.

### P3. 사용자 확인
- 초안을 보여주고 AskUserQuestion: "이 plan 으로 진행할까? 수정할 항목 있으면 알려줘."
- 수정 요청 받으면 반영하고 다시 보여줌. 합의될 때까지 반복.

### P4. 디렉터리 + 리뷰 골격
- `works/<주차>/` 가 없으면 만들기
- `works/<주차>/review/` 빈 디렉터리 만들기 (.gitkeep 또는 그대로 비워두고 첫 commit<N>.md 가 들어올 때 git 이 인식)

### P5. plan commit
명시 경로로 stage → commit:

```
chore: <주차> 작업 계획 초안

<짧은 본문 — 어떤 스펙을 흡수해 어떤 체크리스트를 도출했는지>

- 확인내용: (리뷰 시 작성)
- 이해 안 됐던 부분: (리뷰 시 작성)
```

`#N` 은 plan commit 에 붙이지 않는다 (체크리스트 항목이 아니므로).

### P6. 항목 모드로 진입
- 호출이 `plan-only` 였으면 여기서 종료. "plan 작성 완료. `/work` 또는 `/work N` 으로 항목 진행" 안내.
- 그 외(`/work`, `/work plan`)에서는 plan commit 직후 **항목 모드로 진입해 모든 미완 항목을 wave 단위 자동 진행**.
- 즉 한 호출 = plan commit (1개) + 모든 항목 commit (N개) = **N+1 commit**.

> P3 사용자 확인 단계에서 plan 자체가 거절되거나 큰 수정이 필요하면 항목 진입은 보류된다 (plan 합의가 우선).

---

## 항목 모드

### 1. 처리 대상 결정
- 인자 N 있으면 → **그 N 항목만 단독 처리** (절차 3~7 한 번 수행 후 종료)
- 인자 N 없으면 → **모든 미완 항목 자동 진행**:
  - plan.md 의 모든 `- [ ]` 항목을 plan.md "## 병렬 그룹" 의 wave 순서대로 처리
  - 항목 제목 추출 정규식: `^\s*-\s*\[[ x]\]\s*\*\*(\d+)\.\s*([^*]+)\*\*`
  - "## 병렬 그룹" 섹션이 없으면 항목 N 오름차순 (모두 단독 wave 로 간주)

### 2. Wave 루프 (자동 진행 모드만)
미완 항목들이 속한 wave 들을 순서대로:

a. **의존성 체크** — 그 wave 안 항목들의 선행이 모두 `[x]` 인지 (이전 wave 가 끝났으면 자동 만족, 단 안전 확인). 깨진 게 있으면 중단 + 보고.
b. **파일 충돌 체크** — wave 안 두 항목 이상이 plan.md "수정 파일" 컬럼에서 겹치면 spawn 거부 → 사용자에게 알리고 wave 분할 요청 후 종료. (또는 그 wave 만 직렬 처리로 fallback)
c. **wave 안 항목이 1개면** → 메인이 직접 절차 3~7 수행.
d. **wave 안 항목이 2개 이상이면** → 항목당 subagent 한 개 병렬 spawn:
   - 각 subagent 는 절차 3~5 (설계 · 구현 · `commit<N>.md` 작성) 까지만 수행
   - 메인은 모든 subagent 종료 대기
   - 종료 후 메인이 절차 6~7 (체크박스 갱신 + commit) 을 항목 N 오름차순으로 직렬 수행 (git index lock + 의존관계 보존)
e. 다음 wave 로.

모든 wave 끝나면 절차 8 (결과 보고). 도중에 한 항목이라도 실패 (build/test/lint, pre-commit 훅 실패 등) 하면 즉시 중단하고 사용자에게 보고 — 자동으로 다음 wave 진행하지 않는다.

단독 모드 (인자 N) 는 b~e 생략, 그냥 N 하나에 대해 절차 3~7 수행.

### 3. 설계
- plan.md 의 항목 설명을 펼쳐 무엇을 / 어떻게 / 어디에 만들지 결정
- 필요 시 인터페이스/타입을 먼저 박는다
- 한두 줄 설계 요약을 보여주고 바로 다음 단계

### 4. 구현
- `src/` 하위에 코드 작성. 다른 곳을 건드리지 않음.
- CLAUDE.md 의 영구 규칙(디자인 토큰, accent 두 곳, 1px/#D2DAE0, 그림자/그라디언트 금지, 모션, a11y)을 따름
- spec/<주차>/ 의 픽셀 치수와 토큰을 그대로 따름

### 5. commit\<N\>.md 작성
`works/<주차>/review/commit<N>.md`:

```markdown
# Commit <N> — feat: #<N> <항목 제목>

- Feature: #<N> <항목 제목>
- Type: feat

## 점검 결과

### 스펙 합치
spec/<주차>/ 의 PDF 와 비교 — 어떤 토큰/치수/동작을 어떻게 매칭했는지.

### CLAUDE.md 규칙
컬러/선/그림자/타이포/모션/a11y 규칙을 어기지 않았는지 항목별로.

### 회귀
인접 컴포넌트나 기존 동작에 미치는 영향. 없으면 "없음".

### 테스트
이 변경이 테스트로 보호되는지. 없으면 "다음 wave 의 #N 에서 다룸" 등.

### 불필요한 추상화
한 곳에서만 쓰는데 컴포넌트/훅으로 빼지 않았는지. 없으면 "없음".

### 기타 메모
(필요 시)
```

각 섹션은 짧게라도 채울 것 — "확인됨" / "해당 없음" 등.

### 6. plan.md 체크박스 갱신
`works/<주차>/plan.md` 의 해당 줄에서 `- [ ] **N.` → `- [x] **N.` 정확히 한 글자 치환.

### 7. 단일 commit
명시 경로 stage → commit:

```bash
git add <변경된 src 파일들> works/<주차>/review/commit<N>.md works/<주차>/plan.md
```

```
feat: #<N> <항목 제목>

<짧은 본문 — 무엇을 어떻게 구현했는지 1~3 줄>

- 확인내용: (리뷰 시 작성)
- 이해 안 됐던 부분: (리뷰 시 작성)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

amend 하지 않는다. pre-commit 훅 실패 시 원인 수정 후 새 commit (--no-verify 금지).

### 8. 결과 보고
- 처리한 항목 수, 각 commit short hash + 변경 파일 요약 (테이블)
- 실패하거나 건너뛴 항목 있으면 명시
- 사용자가 `/commit-review <N>` 로 placeholder 채울 차례임을 환기 (N 개라면 N 번 호출)

---

## 비목표

- /commit-review 영역(placeholder 채우기) 침범 금지
- amend / force-push 금지
- chore/refactor/docs 등 #N 없는 셋업 작업은 이 스킬 범위 밖 (예외: plan 모드의 plan commit)
- 새 주차 `spec/weekN/` 디렉터리 생성·PDF 배치는 사용자가 한다 (스킬은 그것을 읽기만)
