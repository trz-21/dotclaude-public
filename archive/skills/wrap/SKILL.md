---
name: wrap
description: 세션 마무리 + 사용된 스킬 자동 업데이트. "wrap up session", "end session", "/wrap", "세션 마무리" 시 사용.
allowed-tools: Bash(git *), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
---

# Session Wrap + Skill Update

기존 session-wrap 워크플로우를 수행한 뒤, 세션에서 사용된 스킬을 분석하여 업데이트한다.

## Step 1: Git 상태 확인

```bash
git status --short
git diff --stat HEAD~3 2>/dev/null || git diff --stat
```

## Step 2: Compile Session Context from User Inputs

Before launching analysis agents, compile a **SESSION_CONTEXT** block by examining
user messages and git changes — NOT the full session execution details (tool calls, subagent results, etc.).
This reduces context passed to subagents significantly.

1. Extract all **user messages** from the session (requests, confirmations, rejections, feedback)
2. Run `git diff --stat` and `git diff` to get actual changes
3. Note which skills were invoked (check for `/fix-issue`, `/wrap`, etc. in user messages or Skill tool calls)

```
SESSION_CONTEXT:
- User requests (chronological):
  1. [first user message/request]
  2. [second user message/request]
  ...
- User decisions: [confirmations, rejections, feedback given by user]
- Skills used: [list of skills invoked]
- Git changes: [git diff --stat output]
- Modified files: [list with brief description of each change]
- Repos touched: [which repos were modified]
```

## Step 3: Session Analysis (Phase 1 — Parallel)

Pass the SESSION_CONTEXT block to each analysis agent as the prompt.
Agents analyze based on user inputs and code changes, not intermediate execution details.

Check if skills were used in the session.

**When skills were used:**
```
[Parallel — single message with 5 Task calls]
├── Task(subagent_type="session-wrap:doc-updater", prompt="SESSION_CONTEXT:\n...")
├── Task(subagent_type="session-wrap:automation-scout", prompt="SESSION_CONTEXT:\n...")
├── Task(subagent_type="session-wrap:learning-extractor", prompt="SESSION_CONTEXT:\n...")
├── Task(subagent_type="session-wrap:followup-suggester", prompt="SESSION_CONTEXT:\n...")
└── Task(subagent_type="Explore", prompt="[skill improvement analysis — see below]")
```

**When skills were NOT used:**
```
[Parallel — single message with 4 Task calls]
├── Task(subagent_type="session-wrap:doc-updater", prompt="SESSION_CONTEXT:\n...")
├── Task(subagent_type="session-wrap:automation-scout", prompt="SESSION_CONTEXT:\n...")
├── Task(subagent_type="session-wrap:learning-extractor", prompt="SESSION_CONTEXT:\n...")
└── Task(subagent_type="session-wrap:followup-suggester", prompt="SESSION_CONTEXT:\n...")
```

### Skill Improvement Analysis Agent (Explore)

Provide this agent with the SESSION_CONTEXT plus the following instructions:

> **SESSION_CONTEXT**: [compiled context from Step 2]
>
> Skills used in this session: [skill list]
>
> Read each used skill's SKILL.md and compare against the SESSION_CONTEXT (user requests, decisions, and changes) to analyze:
>
> 1. **Workflow gaps**: Where the skill's defined phases differed from what user interactions suggest happened
>    - Steps the user had to override or correct
>    - Scenarios the user encountered that the skill didn't handle
> 2. **Missing scenarios**: Cases encountered but not defined in the skill
> 3. **Unnecessary steps**: Steps that were skipped or provided no value
> 4. **Persona mismatches**: Subagent personas that didn't fit the actual work
> 5. **New patterns**: Repeatable patterns worth adding to the skill
>
> Skill file paths:
> - ~/.claude/skills/fix-issue/SKILL.md
> - ~/.claude/skills/fix-issue-teams/SKILL.md
> - ~/.claude/skills/wrap/SKILL.md
> - Other SKILL.md files under ~/.claude/skills/
>
> For each finding, provide a **specific edit suggestion** specifying which section to change and how.

## Step 4: 검증 (Phase 2 — 순차)

Phase 1 결과를 종합하여 duplicate-checker를 실행한다.

```
Task(
    subagent_type="session-wrap:duplicate-checker",
    prompt="""
    ## doc-updater 결과:
    [doc-updater results]

    ## automation-scout 결과:
    [automation-scout results]

    ## 스킬 개선점 분석 결과:
    [skill improvement results]

    중복 확인:
    1. 문서 업데이트 제안이 기존 내용과 중복되는가?
    2. 자동화 제안이 기존 스킬/커맨드와 중복되는가?
    3. 스킬 개선 제안이 이미 반영된 내용인가?
    """
)
```

## Step 5: 결과 통합

```markdown
## Wrap Analysis Results

### Documentation Updates
[doc-updater 요약]
- Duplicate check: [duplicate-checker 피드백]

### Automation Suggestions
[automation-scout 요약]
- Duplicate check: [duplicate-checker 피드백]

### Learning Points
[learning-extractor 요약]

### Follow-up Tasks
[followup-suggester 요약]

### Skill Updates (스킬 사용 시에만 표시)
[스킬별 개선 제안 요약]
- 각 스킬의 변경 사항 1줄 요약
- Duplicate check: [duplicate-checker 피드백]
```

## Step 6: 액션 선택

```
AskUserQuestion(
    questions=[{
        "question": "어떤 액션을 수행할까요?",
        "header": "Wrap Options",
        "multiSelect": true,
        "options": [
            {"label": "커밋 생성 (권장)", "description": "변경사항을 커밋한다"},
            {"label": "CLAUDE.md 업데이트", "description": "새로운 지식/워크플로우를 문서화한다"},
            {"label": "자동화 생성", "description": "새 스킬/커맨드/에이전트를 만든다"},
            {"label": "스킬 업데이트 (스킬 사용 시에만 표시)", "description": "세션에서 발견된 개선점을 스킬에 반영한다"},
            {"label": "스킵", "description": "액션 없이 종료한다"}
        ]
    }]
)
```

## Step 7: 선택된 액션 실행

사용자가 선택한 액션만 실행한다.

### 스킬 업데이트 실행 시

1. 각 스킬의 SKILL.md를 Read로 읽는다.
2. 개선 제안을 바탕으로 Edit로 수정한다.
3. 수정 전후 diff를 사용자에게 보여준다.
4. 변경 사항이 기존 워크플로우를 깨뜨리지 않는지 확인한다:
   - Phase 순서가 논리적으로 유효한가
   - 사용자 체크포인트가 유지되는가
   - 페르소나 정의가 일관적인가

---

## 스킬 사용 감지 방법

세션에서 사용된 스킬을 감지하기 위해:
1. 세션 컨텍스트에서 `/fix-issue`, `/fix-issue-teams`, `/wrap` 등 슬래시 커맨드 호출을 찾는다.
2. `Skill` 도구 호출 기록을 확인한다.
3. 스킬이 사용되지 않은 세션이면 스킬 업데이트 단계를 건너뛴다.

---

## Quick Reference

### When to Use
- 작업 세션 종료 시
- 다른 프로젝트로 전환 전
- 기능 구현 또는 버그 수정 완료 후

### When to Skip
- 매우 짧은 세션 (탐색/질문만 한 경우)
- 코드 변경 없이 읽기만 한 경우
