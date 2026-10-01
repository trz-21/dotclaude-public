---
name: hook-review
description: 세션 종료 훅(session-close.sh)이 무인으로 한 일 — 스킬 자동 수정, 실패한 실행, 확인 대기 수정안(PENDING.md) — 을 사용자와 함께 확인하고 처리한다. "/hook-review", "훅 리포트", "훅이 뭐 고쳤어", 세션 시작 때 "🔧 훅 리포트" 메시지를 보고 확인하려 할 때 사용.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(python3 *), Bash(diff *), Bash(cp *), Bash(mkdir *), Bash(~/.claude/hooks/session-close.sh *), AskUserQuestion
---

# Hook Review

`session-close.sh`(세션 종료·compact 때 archive-me → improve-skills)는 사람 없이 돈다.
이 스킬은 그 결과를 사용자가 확인하는 자리다. 세션 시작 때 `hook-digest.py`가 새 소식이 있으면 한 줄로 알려 준다.

- 리포트: `python3 ~/.claude/hooks/hook-digest.py --report` (`--all`이면 이미 확인한 것까지)
- 확인 기록: `python3 ~/.claude/hooks/hook-digest.py --mark`
- 변경 기록·확인 대기: `~/.claude/skills/.history/CHANGELOG.md`, `PENDING.md`
- 수정 전 백업 `<skill>/<ts>/`, 훅이 고친 직후 `<skill>/<ts>-after/` (`~/.claude/skills/.history/` 아래)

인자 `all`을 받으면 리포트에 `--all`을 붙인다.

## Step 1: 리포트 읽고 요약

리포트를 실행해 읽고, 사용자에게 아래 순서로 짧게 보여 준다. diff 전문을 붙여 넣지 말고 무엇이 바뀌었는지를 한두 줄로 말한다.

1. **스킬 자동 수정**: 스킬별로 "무엇을 바꿨나 — 근거(사용자 지적 등)". CHANGELOG 항목이 기준이고, diff는 실제로 그렇게 바뀌었는지 대조하는 데 쓴다.
   비교 대상이 "현재 스킬"로 표시된 건 훅 이후 수동 수정이 섞였을 수 있으니 CHANGELOG에 적힌 부분만 훅 변경으로 말한다.
2. **실패**: 시각, 스킬, 원인 한 줄.
3. **확인 대기**: 번호, 대상 스킬, 바꿀 내용 한 줄, 근거 횟수. ⚠️우선 항목을 먼저.

아무것도 없으면 "새로 확인할 것 없음"이라고 말하고 Step 5로 간다.

## Step 2: 자동 수정 확인

한 번에 AskUserQuestion(multiSelect)으로 "되돌릴 수정이 있나"를 묻는다. 기본은 유지다.
되돌리기로 한 것은:
- 해당 스킬 파일을 Read하고, 그 수정이 추가·변경한 부분만 Edit로 되돌린다. 백업 폴더를 통째로 덮어쓰지 않는다 — 그 뒤의 다른 수정까지 사라진다.
- CHANGELOG 맨 아래에 `## YYYY-MM-DD <skill> (되돌림)` + `- <무엇을 되돌렸나> — 사유: <사용자 말>`을 남긴다.

## Step 3: 실패 처리

원인을 보고 판단한다.
- 일시적인 원인(로그인 풀림, 네트워크, 잠금 대기 초과)이고 리포트에 "다시 돌리기" 명령이 있으면, 다시 돌릴지 묻고 원하면 그 명령을 실행한다.
  워커가 claude를 두 번 띄워 몇 분 걸리므로 Bash의 `run_in_background`로 실행하고, 끝나면 `~/.claude/hooks/hook.log` 끝부분으로 결과를 확인해 알린다.
- 같은 원인이 반복되거나 스킬·스크립트 문제로 보이면 원인을 설명하고, 고치는 건 사용자와 정한다.

## Step 4: 확인 대기 수정안 처리

`PENDING.md`를 Read로 전부 읽고, 항목마다 AskUserQuestion으로 묻는다 (한 번에 최대 4개씩).
선택지: **반영** / **기각** / **보류**. 질문에는 바꿀 내용과 근거를 한두 줄로 넣고, 근거가 3회 이상 쌓인 항목은 반영을 추천한다.

- **반영**: improve-skills 스킬의 Step 3(수정안 작성 원칙)과 Step 4(백업 → Edit → CHANGELOG → 사후 확인)를 그대로 따른다.
  CHANGELOG에는 `[B→승인]`으로 적는다. 스크립트 수정이면 고친 뒤 실제로 한 번 실행해 확인한다.
  대상 스킬이 git 레포 안(dotclaude 원본 레포 제외)이면 improve-skills Step 1 표대로 수정안만 보여 준다.
- **기각**: 반영하지 않는다. CHANGELOG에 `- [기각] <항목 제목> — 사유: <사용자 말>` 한 줄을 남긴다 (같은 수정안이 다시 올라오는 걸 막는 근거가 된다).
- 반영·기각한 항목은 `PENDING.md`에서 지운다. **보류**는 그대로 둔다.

## Step 5: 확인 기록

`hook-digest.py --mark`를 실행한다. 다음 세션부터는 이후에 생긴 것만 알린다
(보류한 확인 대기는 새 소식이 없어도 7일마다 다시 알린다).

마지막으로 처리 결과를 짧게 보고한다:
```
훅 리뷰:
- 자동 수정 6건 확인 (되돌림 1: example-skill Step 5 규칙)
- 실패 2건 재실행 → 완료
- 확인 대기: 반영 2 · 기각 1 · 보류 2
```
