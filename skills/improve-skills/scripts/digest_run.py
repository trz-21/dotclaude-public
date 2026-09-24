#!/usr/bin/env python3
"""훅이 띄운 무인 스킬 실행 기록(~/.claude/hooks/runs/<skill>/<id>/)을 요약한다.

사용법:
  digest_run.py <run_dir>           요약 출력
  digest_run.py <run_dir> --check   문제가 있으면 exit 1, 없으면 exit 0 (출력 없음)

문제로 보는 것: 비정상 종료, 권한 거부, 도구 에러(없는 파일 Read는 제외), 스스로 보고한 ISSUES.
"""
import json
import re
import sys
from pathlib import Path

BENIGN = re.compile(r"does not exist|No such file|not found", re.I)


def load(run):
    meta = json.loads((run / "meta.json").read_text()) if (run / "meta.json").exists() else {}
    uses, errors, result = {}, [], {}
    stream = run / "stream.jsonl"
    for line in stream.read_text().splitlines() if stream.exists() else []:
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") == "result":
            result = d
        msg = d.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list):
            continue
        for b in content:
            if b.get("type") == "tool_use":
                inp = b.get("input", {})
                target = inp.get("file_path") or inp.get("pattern") or inp.get("skill") or ""
                uses[b["id"]] = f"{b['name']} {target}".strip()
            elif b.get("type") == "tool_result" and b.get("is_error"):
                c = b.get("content")
                text = c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)
                call = uses.get(b.get("tool_use_id"), "?")
                if call.startswith("Read") and BENIGN.search(text):
                    continue
                errors.append(f"{call} → {text[:200]}")
    text = result.get("result") or ""
    m = re.search(r"^ISSUES:\s*(.+)$", text, re.M)
    issues = m.group(1).strip() if m else "(보고 없음)"
    return meta, list(uses.values()), errors, result, text, issues


def has_problem(meta, errors, result, issues):
    return bool(
        meta.get("rc", 0) != 0
        or result.get("is_error")
        or result.get("permission_denials")
        or errors
        or issues.lower() not in ("none", "(보고 없음)")
    )


def main():
    run = Path(sys.argv[1]).expanduser()
    meta, uses, errors, result, text, issues = load(run)
    if "--check" in sys.argv:
        sys.exit(1 if has_problem(meta, errors, result, issues) else 0)
    print(f"### run `{run}`")
    print(f"- skill: {meta.get('skill')} ({meta.get('skill_dir')})")
    print(f"- trigger: {meta.get('trigger')} / 원 세션: {meta.get('source_session')}")
    print(f"- exit: {meta.get('rc')} / cost: ${result.get('total_cost_usd', 0):.2f}")
    print(f"- ISSUES(자기보고): {issues}")
    for d in result.get("permission_denials") or []:
        print(f"- 권한 거부: {d.get('tool_name')} {json.dumps(d.get('tool_input'), ensure_ascii=False)[:150]}")
    for e in errors:
        print(f"- 도구 에러: {e}")
    print(f"- 도구 호출 순서: {' / '.join(uses) or '(없음)'}")
    print("- 최종 응답:")
    print("  > " + text.strip().replace("\n", "\n  > ")[:1500])


if __name__ == "__main__":
    main()
