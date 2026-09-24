---
name: task-with-harness
description: 하나의 기능 단위를 받아 서브에이전트로 구현하고, 메인이 직접 harness를 검증한 뒤 커밋까지 완료하는 워크플로우. 서브에이전트에 훅이 적용되지 않는 문제를 메인의 명시적 검증으로 보완한다.
argument-hint: [구현할 기능 설명]
---

# Task with Harness Workflow

## 전제 조건

스킬 실행 전 프로젝트 루트에서 아래 파일들을 읽는다:

| 파일 | 역할 |
|------|------|
| `CLAUDE.md` | 프로젝트 전체 맥락 |
| `.claude/dod.md` | 작업 완료 기준 + 검증 명령어 |
| `.claude/code-rules.md` | 코드 수정 규칙 + 체크리스트 |
| `.claude/commit-rules.md` | 커밋 타이밍/형식 |
| `specification/dev/harness.md` | 테스트 안전망 4단계 |

---

## Phase 1: 컨텍스트 로드

**메인이 직접 수행한다.**

1. 위 파일들을 순서대로 읽는다
2. 인자로 받은 기능 설명을 기반으로 관련 스펙 파일 읽기
   - `specification/dev/` 해당 영역 파일 확인
   - 구현 대상 코드 파일 확인 (현재 상태 파악)

---

## Phase 2: 구현 계획

**메인이 직접 수행한다.**

인자로 받은 기능 하나를 구현하기 위한 서브태스크를 분해한다.

### 설계 원칙: 교체 가능성 우선

구현 계획을 세우기 전에 아래를 먼저 판단한다.

**"이 로직은 나중에 다른 구현으로 바꿔낄 가능성이 있는가?"**

있다면 → **trait 기반 패키지 단위**로 설계한다:

```
domain/ports/{name}.rs       ← Context 구조체 + Outcome 구조체 + trait 정의
application/{name}/standard_{name}.rs  ← 기본 구현체 (Standard*)
호출부 (engine/service)       ← Arc<dyn Trait> 보유, with_{name}() 빌더로 주입
```

**이 프로젝트에서 적용된 예시:**

| 패턴 | trait | 기본 구현 | 교체 목적 |
|------|-------|-----------|-----------|
| 백그라운드 태스크 | `BackgroundTask` | `SimulationTask` | 다른 종류의 태스크 |
| 이터레이션 실행 | `TurnExecutor` | `StandardTurnExecutor` | 게임별 다른 턴 로직 |

**판단 기준:**
- 게임 타입마다 달라질 수 있는가 → trait
- 테스트에서 mock으로 교체해야 하는가 → trait
- 지금은 하나뿐이지만 분명히 여러 구현이 생길 것 같은가 → trait
- 현재도 미래에도 딱 하나만 있을 것 같은가 → 그냥 구현

**trait 기반 모듈을 새로 추가할 때 → 반드시 아래를 함께 수행:**

1. 해당 모듈의 결정론적 동작을 검증할 픽스처 또는 단위 테스트 추가
2. `.claude/dod.md` 에 해당 모듈 작업 시 테스트 조건 명시

> 설계 시점에 테스트 전략을 결정하지 않으면, 구현 완료 후엔 추가되지 않는다.

---

### 설계 원칙: FE 분리 기준

FE 구현 계획 시 아래 두 가지를 먼저 판단한다.

**1. Custom Hook 분리 기준**

비동기 데이터 패턴(폴링, SSE, WebSocket)이 페이지 컴포넌트에 직접 들어가면 → `src/features/{domain}/hooks/` 로 추출한다.

```
폴링  → usePolling(fetchFn, interval, stopCondition)
SSE   → useSimulationStream (이미 존재)
공통  → src/features/{domain}/hooks/use{Pattern}.ts
```

판단 기준:
- `useEffect + setInterval / EventSource` 조합이 페이지에 직접 있는가 → hook으로 분리
- 같은 패턴이 2개 이상의 페이지/컴포넌트에서 쓰이는가 → hook으로 분리
- 페이지 컴포넌트가 150줄 초과인가 → 로직 추출 검토

**2. 재사용 컴포넌트 분리 기준**

독립적인 UI 블록이 100줄 이상이거나 여러 곳에서 재사용된다면 → 컴포넌트로 추출한다.

```
같은 feature 내 재사용  → src/features/{domain}/components/
여러 feature 간 공유    → src/shared/components/
```

판단 기준:
- 차트, 배지, 카드 등 독립적인 UI 단위인가 → 컴포넌트 분리
- 페이지와 무관하게 props만으로 동작 가능한가 → 컴포넌트 분리

---

### 분해 기준

하나의 기능이라도 내부적으로 독립적인 작업이 있으면 분리한다:
- **BE 작업**: Rust 코드 변경 (다른 파일과 독립적이면 병렬 가능)
- **FE 작업**: TypeScript 코드 변경 (BE 결과물이 필요하면 직렬)
- **문서 작업**: spec 업데이트 (코드와 독립적이면 병렬 가능)

### TaskCreate

각 서브태스크를 `TaskCreate`로 등록한다. description에 반드시 포함:
- 작업 대상 파일 절대 경로
- 구체적인 구현 내용 (무엇을 추가/수정할지)
- 프로젝트 루트 경로

의존관계가 있으면 `TaskUpdate(addBlockedBy)`로 설정한다.

### 사용자에게 공유

작업 시작 전, 아래 계획을 **대화로** 정리해 사용자에게 보여준다 (로컬에 파일로 남기지 않는다):

- 목표 (기능 설명)
- 서브태스크 목록 (작업 / 대상 파일 / 병렬 가능 여부)
- 영향 파일
- 테스트 전략

확인 후 Phase 3으로 넘어간다.

---

## Phase 3: 실행

**메인이 서브에이전트를 조율한다.**

### 병렬 실행 원칙

- `blockedBy` 없는 서브태스크 → **단일 메시지에 여러 Agent 호출**로 동시 실행
- `blockedBy` 있는 서브태스크 → 선행 태스크 Phase 4 통과 후 시작

### 서브에이전트 프롬프트 필수 포함 사항

```
## 프로젝트 루트
<절대 경로>

## 작업 내용
<구체적인 구현 내용>

## 완료 조건
- [ ] 파일 수정 전 반드시 현재 내용 읽기
- [ ] BE 수정 시: cargo check 통과
- [ ] BE 수정 시: cargo test 통과
- [ ] FE 수정 시: npm run type-check 통과
- [ ] FE 수정 시: npm test -- --run 통과 (type-check만으로 완료 불가)
- [ ] FE API 함수 추가 시: types.ts에 {Action}Request/{Action}Response 타입 정의 후 사용
- [ ] application/, adapters/ .rs 파일 수정 시: #[cfg(test)] mod tests 블록 포함
- [ ] src/features/ .ts 파일 수정 시: 대응 .test.ts 파일 존재

## 주의
훅이 적용되지 않으므로 위 조건을 직접 확인하고 완료해야 한다.
```

> 오늘 날짜는 항상 현재 날짜(YYYY-MM-DD)로 채워 넣는다.

### TaskUpdate 타이밍

- 서브에이전트 시작 전: `TaskUpdate(status: in_progress)`
- Phase 4 통과 후: `TaskUpdate(status: completed)`

---

## Phase 4: 검증 (메인이 직접)

**서브에이전트 완료 후 메인이 직접 수행. TaskUpdate(completed) 전에 반드시 실행.**
**4-1 ~ 4-2 모두 통과해야 한다. 하나라도 실패하면 4-4로 간다.**

### 4-1. 컴파일/타입 ← 반드시 실행

```bash
# BE 변경이 있었던 경우
cd <프로젝트루트>/backend && cargo check

# FE 변경이 있었던 경우
cd <프로젝트루트>/frontend && npm run type-check
```

### 4-2. 테스트 ← 반드시 실행 (type-check만으로 완료 처리 금지)

```bash
# BE
cd <프로젝트루트>/backend && cargo test

# FE (-- --run 플래그로 watch 모드 방지)
cd <프로젝트루트>/frontend && npm test -- --run
```

### 4-2-1. 커버리지 확인 ← BE 변경이 있었던 경우 실행

```bash
# BE: 커버리지 측정 (tarpaulin 설치 필요)
cd <프로젝트루트>/backend && cargo tarpaulin --out Stdout

# FE: 커버리지는 Stop hook이 자동 실행함 (별도 실행 불필요)
```

커버리지가 이전 대비 **하락**했다면 테스트 보강 후 재실행.

### 4-4. 실패 시

`SendMessage`로 해당 서브에이전트에게 실패 내용 전달 → 수정 완료 후 Phase 4 재실행.

---

## Phase 5: 완료

**모든 서브태스크 Phase 4 통과 후 수행.**

### 5-1. TaskUpdate(completed)

검증 통과한 서브태스크만 완료 처리.

### 5-2. 커밋

`.claude/commit-rules.md` 기준:

```bash
# 루트가 단일 git 레포다. backend/ frontend/ 는 폴더일 뿐 별도 레포가 아니다.
# 따라서 프로젝트 루트에서 한 번만 커밋한다.
cd <프로젝트루트>
git add backend frontend specification
git commit -m "$(cat <<'EOF'
<type>: <subject>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- BE / FE / 문서가 하나의 기능을 위한 변경이면 한 커밋으로 묶는다
- **루트 단일 레포이므로 프로젝트 루트에서 한 번만 커밋한다** (backend/frontend는 별도 레포가 아니다)

### 5-3. 결과 보고

작업 결과는 **대화로** 보고한다 (로컬에 로그 파일을 만들지 않는다):

```
구현한 기능
변경된 파일 목록
통과한 검증 항목
커밋 ID (루트 단일 커밋)
```
