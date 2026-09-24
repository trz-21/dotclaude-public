#!/usr/bin/env python3
"""세션 transcript(JSONL)에서 스킬 개선 분석에 필요한 것만 뽑는다.

출력:
  ## 사용된 스킬   이름, SKILL.md 위치, 호출 횟수
  ## 대화 흐름     [USER] 발화 전문, [SKILL ▶] 호출 지점, [CLAUDE] 응답 앞부분, [TOOL-ERR] 도구 에러

사용법:
  extract_skill_session.py <transcript.jsonl>                 전체
  extract_skill_session.py <transcript.jsonl> --state F       F에 기록된 지점 이후만 (훅용)
  extract_skill_session.py <transcript.jsonl> --state F --mark  현재 끝 줄까지 처리 완료로 기록
"""
import json
import re
import sys
from pathlib import Path

CLAUDE_MAX = 400
ERR_MAX = 300


def texts(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1]).expanduser()
    lines = path.read_text().splitlines()
    state_file = Path(sys.argv[sys.argv.index("--state") + 1]).expanduser() if "--state" in sys.argv else None
    state = json.loads(state_file.read_text()) if state_file and state_file.exists() else {}
    if "--mark" in sys.argv:
        state[path.stem] = len(lines)
        state_file.write_text(json.dumps(state, indent=1))
        return
    start = state.get(path.stem, 0)

    skills = {}  # name -> {"dir": str|None, "count": int}
    flow = []
    pending_name = None  # 직전 Skill 호출 이름 (본문 메시지와 짝지음)

    for raw in lines[start:]:
        try:
            d = json.loads(raw)
        except Exception:
            continue
        if d.get("isSidechain"):
            continue
        t, msg = d.get("type"), d.get("message") or {}
        content = msg.get("content")

        if t == "assistant" and isinstance(content, list):
            for b in content:
                if b.get("type") == "tool_use" and b.get("name") == "Skill":
                    name = b["input"].get("skill", "?")
                    args = b["input"].get("args") or ""
                    skills.setdefault(name, {"dir": None, "count": 0})["count"] += 1
                    pending_name = name
                    flow.append(f"[SKILL ▶ {name}] {args[:200]}")
            txt = texts(content).strip()
            if txt:
                flow.append(f"[CLAUDE] {txt[:CLAUDE_MAX]}{' …' if len(txt) > CLAUDE_MAX else ''}")
            continue

        if t != "user":
            continue
        if isinstance(content, list):
            for b in content:
                if b.get("type") == "tool_result" and b.get("is_error"):
                    e = texts(b.get("content")).strip() or str(b.get("content"))
                    flow.append(f"[TOOL-ERR] {e[:ERR_MAX]}")
        txt = texts(content).strip()
        if not txt:
            continue

        m = re.search(r"Base directory for this skill: (\S+)", txt)
        if m:  # 스킬 본문 주입 메시지: 위치만 기록하고 본문은 생략
            name = pending_name or Path(m.group(1)).name
            skills.setdefault(name, {"dir": None, "count": 0})["dir"] = m.group(1)
            if pending_name is None:  # 슬래시 커맨드로 호출된 경우
                skills[name]["count"] += 1
                flow.append(f"[SKILL ▶ {name}] (slash)")
            pending_name = None
            continue
        if d.get("isMeta"):
            continue

        m = re.search(r"<command-name>/?([^<]+)</command-name>", txt)
        if m:
            args = re.search(r"<command-args>(.*?)</command-args>", txt, re.S)
            flow.append(f"[USER] /{m.group(1)} {(args.group(1).strip() if args else '')}".rstrip())
            pending_name = None
            continue
        if txt.startswith(("<local-command", "<system-reminder", "<task-notification")):
            continue
        flow.append(f"[USER] {txt}")

    print("## 사용된 스킬")
    for name, info in skills.items():
        print(f"- {name} ×{info['count']} — {info['dir'] or '(위치 미확인: 번들/플러그인 스킬일 수 있음)'}")
    if not skills:
        print("- (없음)")
    print("\n## 대화 흐름")
    print("\n\n".join(flow))


if __name__ == "__main__":
    main()
