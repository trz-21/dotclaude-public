---
name: archive-me
description: 세션에서 드러난 사용자 본인에 대한 유의미한 정보(성격, 습관, 생애, 경력, 목표, 취향 등)를 ~/.claude/me/ 아카이브에 분류·저장하고 CLAUDE.md 인덱스를 갱신한다. "/archive-me", "나에 대해 기억해", "내 정보 저장", "아카이빙" 요청 시, 또는 훅이 --hook 인자와 함께 호출할 때 사용.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(python3 *)
---

# Archive Me

사용자에 대한 정보를 `~/.claude/me/`에 분류 저장하는 스킬이다. 분류 체계와 파일 형식은
[taxonomy.md](taxonomy.md)에 있다. **시작하면 반드시 taxonomy.md부터 읽는다.**

- 아카이브 루트: `~/.claude/me/`
- 인덱스: `~/.claude/CLAUDE.md`의 `<!-- ME-ARCHIVE:START -->` ~ `END` 블록 (스크립트가 자동 생성, 손으로 고치지 않음)
- 스크립트: `~/.claude/skills/archive-me/scripts/`

## 모드

| 모드 | 언제 | 입력 소스 | 사용자 확인 |
|------|------|-----------|-------------|
| **대화형** | 사용자가 `/archive-me` 호출, 인자 없음 또는 자유 텍스트 | 현재 세션 대화 (인자로 준 텍스트가 있으면 그것 우선) | 민감 정보·기존 정보와 충돌하는 경우만 확인 |
| **transcript** | 인자가 `.jsonl` 경로 (사용자가 지난 세션을 수동 처리) | 해당 transcript | 묻지 않음. 보수적으로 저장 |
| **hook** | 인자가 `--hook <추출본.txt>` (훅 워커 `~/.claude/hooks/session-close.sh`가 하루 한 번 호출) | 워커가 미리 뽑아둔 발화 텍스트 (여러 세션) | 묻지 않음. 보수적으로 저장. **Bash 없음** |

hook 모드는 파일 도구만 있는 세션에서 돈다. 추출·인덱스 갱신·`--mark`는 워커가 앞뒤로 처리하므로
Step 1의 스크립트 실행과 Step 5의 명령은 건너뛰고, 판단과 파일 쓰기(`_log.md` 포함)만 한다.
아래 규칙에서 "transcript 모드"는 hook 모드에도 똑같이 적용된다.

## Step 1: 소스 수집

**대화형**: 현재 세션에서 사용자가 한 말을 훑는다. 도구 출력이나 코드 내용이 아니라 *사용자 발화*와
사용자가 보여준 행동(반복된 선택, 거절, 선호)이 대상이다.
`~/.claude/me/_inbox.md`에 확인 대기 항목이 있으면 이번에 같이 물어보고, 답을 받은 항목은 반영한 뒤 inbox에서 지운다.
inbox는 hook 모드가 애매한 충돌을 미뤄두는 곳이라, 대화형 때 비워주지 않으면 계속 쌓인다.

**transcript 모드**:
```bash
python3 ~/.claude/skills/archive-me/scripts/extract_transcript.py <transcript.jsonl>
```
이미 처리한 줄 이후만 출력된다 (compact 후 /clear처럼 같은 세션이 두 번 들어와도 중복 처리 안 됨).
출력이 비어 있으면 Step 5의 `--mark`만 하고 종료한다.

**hook 모드**: 인자로 받은 추출본 파일을 Read로 읽는다. 워커가 그동안 쌓인 세션들을 모아 한 번에 넘기므로
`===== 세션 <session-id> (_log.md 에는 hook:<앞 8자>) =====` 헤더로 나뉜 여러 세션이 들어올 수 있다.
헤더 아래 형식은 transcript 모드 출력과 같다. 후보는 세션마다 따로 뽑고 판단한다 (다른 세션 발화를 근거로 섞지 않는다).
같은 파일에 쓸 후보가 여러 세션에서 나오면 파일은 한 번만 읽고 모아서 쓴다.
사용자 발화가 1개 이하이거나 아주 짧은 세션은 워커가 미리 빼고 처리 완료로 표시한다.

## Step 2: 후보 추출

소스에서 **사람에 대한 사실**을 뽑는다. 각 후보마다 판단한다:

저장한다:
- 사용자가 자기 자신에 대해 직접 말한 것 (경력, 학업, 상황, 계획, 취향, 가치관)
- 여러 번 반복해 드러난 행동 패턴 (같은 방식으로 여러 번 요청, 일관된 거절 이유)
- 날짜가 있는 인생 이벤트, 기한이 있는 목표

저장하지 않는다:
- 이번 작업에만 해당하는 내용 (버그 내용, 코드 구조, 일회성 요청)
- 한 번 보인 행동에서 추측한 성격
- Claude에게 하는 작업 규칙 자체 (→ auto memory `feedback` 소관. taxonomy.md 참고)
- 비밀정보·식별정보, 타인의 사적인 사정 (taxonomy.md 민감 정보 규칙)
- 이미 아카이브에 같은 내용이 있는 것

transcript 모드에서는 `직접` 출처만 저장한다. `관찰`은 대화형에서만, 근거가 2회 이상일 때 저장한다.

후보가 하나도 없으면 "저장할 새 정보 없음"으로 보고하고 (transcript 모드는 `--mark` 후) 종료한다.

## Step 3: 분류와 기존 내용 대조

1. 각 후보를 taxonomy.md 트리의 파일에 배정한다.
2. 배정된 파일이 있으면 **먼저 Read로 전부 읽는다.** 같은 내용이 있으면 버린다. 날짜만 새로우면 날짜만 갱신하지 않는다 (의미 있는 변화가 아니면 그대로 둔다).
3. 기존 내용과 **충돌**하면 (예: 직장이 바뀜, 목표가 달라짐):
   - 대화형: 사용자에게 한 줄로 확인한다. "예전엔 X로 기록돼 있는데 Y로 바뀐 거 맞나요?"
   - transcript 모드: 사용자가 명시적으로 바뀌었다고 말한 경우만 갱신하고, 애매하면 `~/.claude/me/_inbox.md`에 적어두고 넘어간다.

## Step 4: 쓰기

- taxonomy.md의 파일 형식을 따른다. 새 파일이면 frontmatter(`summary`, `updated`)와 `## 현재` 섹션으로 만든다.
- 바뀐 정보는 기존 줄을 `## 지난 기록`으로 옮긴다. 지우지 않는다.
- 쓴 뒤 frontmatter의 `updated`를 오늘 날짜로 바꾼다. Step 3에서 Read한 값이 이미 오늘이면 Edit하지 않는다
  (같은 문자열로 Edit하면 "No changes to make" 도구 에러가 나서 훅 실행이 문제 있는 실행으로 잡힌다). `summary`는 Step 5 체크에서 다시 본다.
- 인생 이벤트면 `life/timeline.md`에도 한 줄 추가한다.
- 새 파일이나 새 카테고리를 만들었으면 taxonomy.md 트리에 한 줄 반영한다.
- 대화형에서 민감 정보(taxonomy.md 참고)는 쓰기 전에 사용자에게 저장 여부를 묻는다.

## Step 5: 인덱스 갱신과 마무리

**summary 체크 (모든 모드 필수)**: 이번에 수정한 파일마다 frontmatter `summary`를 다시 읽고, 새로 넣거나
지난 기록으로 옮긴 내용이 반영됐는지 확인해서 고친다. CLAUDE.md 인덱스에는 이 한 줄만 노출되므로,
본문만 바꾸고 summary를 두면 다른 세션은 옛 정보를 보게 된다 (hook 모드에서 실제로 빠뜨린 적 있음).

```bash
python3 ~/.claude/skills/archive-me/scripts/build_index.py
# transcript 모드일 때만 (hook 모드는 워커가 대신 실행):
python3 ~/.claude/skills/archive-me/scripts/extract_transcript.py <transcript.jsonl> --mark
```

`~/.claude/me/_log.md` 맨 아래에 한 줄 남긴다:
```
- YYYY-MM-DD [대화형|transcript:<session-id 앞 8자>|hook:<session-id 앞 8자>] <파일>: <무엇을 추가/변경> ...
```
저장한 게 없어도 `(변경 없음): <세션 한 줄 요약>`으로 남긴다.
hook 모드는 입력에 든 **세션마다 한 줄**(`hook:<그 세션 id 앞 8자>`)을 남기고, 여러 줄을 Edit 한 번으로 덧붙인다.
Edit로 덧붙일 때는 파일의 **마지막 줄 전체**를 `old_string`으로 쓴다. 줄 끝 일부만 쓰면
"저장할 사용자 정보 없음" 같은 반복 문구가 여러 줄에 걸려 매칭이 실패한다 (hook 모드에서 연속으로 겪음).
마지막 줄은 `_log.md`를 Read로 통째로 읽어 확인한다. Grep `offset`은 음수(끝에서부터)를 받지 않아 에러가 난다.

## Step 6: 보고

대화형에서는 짧게 보고한다:
```
아카이브 갱신:
- identity/profile.md: 추가 — ...
- life/career/current.md: 변경 — A → B
건너뜀: (있으면 이유와 함께)
```
transcript·hook 모드에서는 `_log.md` 기록으로 보고를 대신한다.
