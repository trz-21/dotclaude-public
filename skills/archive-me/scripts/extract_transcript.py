#!/usr/bin/env python3
"""세션 transcript(JSONL)에서 사용자 발화와 어시스턴트 텍스트만 뽑아 출력한다.

사용법:
  extract_transcript.py <transcript.jsonl>          # 아직 처리 안 한 부분만 출력
  extract_transcript.py <transcript.jsonl> --all    # 처음부터 전부 출력
  extract_transcript.py <transcript.jsonl> --mark   # 현재 끝 줄까지 처리 완료로 기록
  --upto N                                          # 앞 N줄만 본다 (훅 워커가 추출한 지점까지만 mark 하려고)
"""
import json
import sys
from pathlib import Path

STATE = Path.home() / ".claude/me/.state.json"
ASSISTANT_MAX = 1000      # 어시스턴트 응답은 맥락용이므로 앞부분만
ASSISTANT_TURN_MAX = 4000  # 사용자 발화 직전·마지막 응답은 길게 (번호 답이 가리키는 질문 목록 등)


def load_state():
    try:
        return json.loads(STATE.read_text())
    except Exception:
        return {}


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if b.get("type") == "text")
    return ""


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1]).expanduser()
    flags = set(sys.argv[2:])
    lines = path.read_text().splitlines()
    if "--upto" in flags:
        lines = lines[:int(sys.argv[sys.argv.index("--upto") + 1])]
    state = load_state()
    key = path.stem

    if "--mark" in flags:
        state[key] = len(lines)
        STATE.write_text(json.dumps(state, indent=1))
        print(f"marked {key}: {len(lines)} lines")
        return

    start = 0 if "--all" in flags else state.get(key, 0)
    out = []
    for raw in lines[start:]:
        try:
            d = json.loads(raw)
        except Exception:
            continue
        if d.get("isMeta") or d.get("isSidechain"):
            continue
        t = d.get("type")
        msg = d.get("message") or {}
        if t == "user":
            if isinstance(msg.get("content"), list) and any(
                b.get("type") == "tool_result" for b in msg["content"]
            ):
                continue
            txt = text_of(msg.get("content")).strip()
            if not txt or txt.startswith(("<local-command", "<command-", "<system-reminder", "<task-notification")):
                continue
            out.append(("USER", txt))
        elif t == "assistant":
            txt = text_of(msg.get("content")).strip()
            if txt:
                out.append(("CLAUDE", txt))

    turn_end = [False] * len(out)  # 다음 사용자 발화 전(또는 맨 끝) 마지막 응답
    last = True
    for i in range(len(out) - 1, -1, -1):
        if out[i][0] == "USER":
            last = True
        else:
            turn_end[i], last = last, False
    for (kind, txt), long in zip(out, turn_end):
        if kind == "CLAUDE":
            limit = ASSISTANT_TURN_MAX if long else ASSISTANT_MAX
            txt = txt[:limit] + (" …" if len(txt) > limit else "")
        print(f"[{kind}] {txt}\n")


if __name__ == "__main__":
    main()
