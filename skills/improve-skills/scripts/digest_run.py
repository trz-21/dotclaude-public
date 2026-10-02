#!/usr/bin/env python3
"""훅이 띄운 무인 스킬 실행 기록(~/.claude/hooks/runs/<skill>/<id>/)을 요약한다.

사용법:
  digest_run.py <run_dir>           요약 출력
  digest_run.py <run_dir> --check   문제가 있으면 exit 1, 환경 실패면 exit 2, 없으면 exit 0 (출력 없음)

문제로 보는 것: 비정상 종료, 권한 거부, 도구 에러, 스스로 보고한 ISSUES.
문제로 안 보는 것 (스킬을 고칠 근거가 아니다):
  - 없는 파일 Read, 같은 대상에 대한 이후 호출이 성공한 도구 에러 (모델이 스스로 복구함)
  - "판단에 지장 없음"류로 끝나는 ISSUES 자기보고
  - 로그인·인증·네트워크 같은 환경 실패 → exit 2. 실패 알림은 hook-digest 가 따로 한다
"""
import json
import re
import sys
from pathlib import Path

BENIGN = re.compile(r"does not exist|No such file|not found", re.I)
# 자기보고의 마지막 문장이 이런 말이면 막혔다는 보고가 아니라 참고 사항이다
HARMLESS = re.compile(r"(영향|지장)[은이을가]?\s*(없|주지 않)|문제[는가]?\s*없|판단에 필요한 .*(남아|있었)"
                      r"|no (real )?impact|did not affect|didn't affect", re.I)
ENV_FAIL = re.compile(r"Not logged in|/login|authenticat|invalid api key|credit balance|ECONN|ENOTFOUND|ETIMEDOUT"
                      r"|network|fetch failed|overloaded|rate.?limit", re.I)


def target_of(inp):
    return inp.get("file_path") or inp.get("path") or inp.get("pattern") or inp.get("skill") or ""


def load(run):
    meta = json.loads((run / "meta.json").read_text()) if (run / "meta.json").exists() else {}
    uses, results, result = {}, [], {}  # results: (tool_use_id, is_error, text) 순서대로
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
                uses[b["id"]] = (b["name"], target_of(b.get("input", {})))
            elif b.get("type") == "tool_result":
                c = b.get("content")
                results.append((b.get("tool_use_id"), bool(b.get("is_error")),
                                c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)))
    errors, recovered = [], []
    for i, (uid, is_err, text) in enumerate(results):
        if not is_err:
            continue
        name, target = uses.get(uid, ("?", ""))
        if name == "Read" and BENIGN.search(text):
            continue
        # 같은 대상(파일·경로)을 다룬 이후 호출이 성공했으면 복구된 에러
        ok_later = target and any(not e and uses.get(u, ("", ""))[1] == target for u, e, _ in results[i + 1:])
        (recovered if ok_later else errors).append(f"{name} {target}".strip() + f" → {text[:200]}")
    text = result.get("result") or ""
    m = re.search(r"^ISSUES:\s*(.+)$", text, re.M)
    issues = m.group(1).strip() if m else "(보고 없음)"
    calls = [f"{n} {t}".strip() for n, t in uses.values()]
    return meta, calls, errors, recovered, result, text, issues


def env_failure(meta, result, run):
    if meta.get("rc", 0) == 0 and not result.get("is_error"):
        return False
    err = (run / "stderr.txt").read_text(errors="replace") if (run / "stderr.txt").exists() else ""
    return bool(ENV_FAIL.search((result.get("result") or "") + "\n" + err))


def harmless_issue(issues):
    last = [x for x in re.split(r"(?<=[.!?。])\s+",issues.strip()) if x.strip()]
    return bool(last) and bool(HARMLESS.search(last[-1]))


def has_problem(meta, errors, result, issues):
    return bool(
        meta.get("rc", 0) != 0
        or result.get("is_error")
        or result.get("permission_denials")
        or errors
        or (issues.lower() not in ("none", "(보고 없음)") and not harmless_issue(issues))
    )


def main():
    run = Path(sys.argv[1]).expanduser()
    meta, uses, errors, recovered, result, text, issues = load(run)
    if "--check" in sys.argv:
        sys.exit(2 if env_failure(meta, result, run) else 1 if has_problem(meta, errors, result, issues) else 0)
    sessions = meta.get("sessions")
    print(f"### run `{run}`")
    print(f"- skill: {meta.get('skill')} ({meta.get('skill_dir')})")
    print(f"- trigger: {meta.get('trigger')} / 원 세션: {', '.join(sessions) if sessions else meta.get('source_session')}")
    print(f"- exit: {meta.get('rc')} / cost: ${result.get('total_cost_usd', 0):.2f}")
    print(f"- ISSUES(자기보고): {issues}")
    for d in result.get("permission_denials") or []:
        print(f"- 권한 거부: {d.get('tool_name')} {json.dumps(d.get('tool_input'), ensure_ascii=False)[:150]}")
    for e in errors:
        print(f"- 도구 에러: {e}")
    for e in recovered:
        print(f"- 도구 에러(이후 복구됨): {e}")
    print(f"- 도구 호출 순서: {' / '.join(uses) or '(없음)'}")
    print("- 최종 응답:")
    print("  > " + text.strip().replace("\n", "\n  > ")[:1500])


if __name__ == "__main__":
    main()
