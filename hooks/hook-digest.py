#!/usr/bin/env python3
"""session-close 훅이 남긴 결과를 사용자에게 보여 주기 위한 요약.

  hook-digest.py           SessionStart 훅용. 마지막 확인 이후 새로 생긴 게 있으면 systemMessage 한 줄을 낸다
  hook-digest.py --report  hook-review 스킬용 전체 리포트 (markdown). --all 이면 확인 여부와 상관없이 전부
  hook-digest.py --mark    지금까지를 확인한 것으로 기록

읽는 것: ~/.claude/hooks/hook.log, ~/.claude/skills/.history/{CHANGELOG,PENDING}.md,
        비용은 ~/.claude/hooks/runs/*/*/{meta.json,stream.jsonl}, ~/.claude/dotclaude-runs/*/cost.json
상태:    ~/.claude/hooks/state/hook-review.json  {"seen_at": "YYYY-MM-DD HH:MM:SS", "pending": [제목, ...]}
"""
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
HOOKS = f"{HOME}/.claude/hooks"
LOG = f"{HOOKS}/hook.log"
STATE = f"{HOOKS}/state/hook-review.json"
HIST = f"{HOME}/.claude/skills/.history"
CHANGELOG = f"{HIST}/CHANGELOG.md"
PENDING = f"{HIST}/PENDING.md"
RUNS = f"{HOOKS}/runs"
OTHER_RUNS = f"{HOME}/.claude/dotclaude-runs"
SCRIPT = "~/.claude/hooks/session-close.sh"

PRIORITY_EVIDENCE = 3   # 근거가 이만큼 쌓인 확인 대기 항목은 우선 검토로 표시
REMIND_DAYS = 7         # 새 소식이 없어도 확인 대기가 남아 있으면 이 기간마다 다시 알린다
COST_DAYS = 7
COST_ALERT_USD = 10     # 최근 COST_DAYS일 무인 실행 비용이 이걸 넘으면 새 소식이 없어도 알린다
DIFF_MAX_LINES = 120

TS = r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)"


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def load_state():
    try:
        return json.loads(read(STATE))
    except ValueError:
        return {}


def run_transcripts(run):
    """일괄 실행 폴더의 transcripts.txt (옛 세션별 실행에는 없다 → None)"""
    if not run or not os.path.exists(f"{run}/transcripts.txt"):
        return None
    return [t for t in read(f"{run}/transcripts.txt").splitlines() if t.strip()]


def parse_log():
    """hook.log → 스킬 수정 목록, 해결되지 않은 실패 목록

    로그의 [xxxxxxxx] 는 옛 실행이면 세션 id 앞 8자, 일괄 실행이면 배치 id(MMDDHHMM)다."""
    runs, transcripts, mods, fails, done = {}, {}, [], [], {}
    for line in read(LOG).splitlines():
        m = re.match(TS + r" (.*)$", line)
        if not m:
            continue
        at, msg = m.groups()
        if t := re.match(r"trigger \S+ (\S+)\.jsonl", msg):
            transcripts[t.group(1)[:8]] = t.group(1)
        elif r := re.match(r"\[(\w{8})\] (archive-me|improve-skills) 실행 → (\S+)", msg):
            runs[(r.group(1), r.group(2))] = r.group(3)
        elif c := re.match(r"\[(\w{8})\] (archive-me|improve-skills) 완료", msg):
            key = (c.group(1), c.group(2))
            done.setdefault(key[1], []).append({"at": at, "id": key[0], "transcripts": run_transcripts(runs.get(key))})
        elif f := re.match(r"\[(\w{8})\] (archive-me|improve-skills) 실패", msg):
            key = (f.group(1), f.group(2))
            fails.append({"at": at, "sid8": key[0], "skill": key[1], "run": runs.get(key)})
        elif f := re.match(r"\[(\w{8})\] lock 획득 실패", msg):
            fails.append({"at": at, "sid8": f.group(1), "skill": "(잠금)", "run": None})
        elif s := re.match(r"\[(\w{8})\] 스킬 수정됨: (\S+) \(백업 (\S+)\)(?: 위치 (.+))?", msg):
            mods.append({"at": at, "sid8": s.group(1), "skill": s.group(2), "backup": s.group(3), "dir": s.group(4)})
    for x in fails:
        x["transcripts"] = run_transcripts(x["run"])
        x["legacy"] = x["transcripts"] is None and x["skill"] != "(잠금)"
        if x["legacy"]:  # 옛 세션별 실행
            t = find_transcript(transcripts.get(x["sid8"], x["sid8"]))
            x["transcripts"] = [t] if t else []
    fails = [x for x in fails if not resolved(x, done.get(x["skill"], []))]
    return mods, fails


def resolved(fail, done):
    """나중에 같은 스킬이 완료됐고, 실패에 들어 있던 세션이 그 완료 실행들에 다 들어 있으면 해결된 실패로 본다"""
    later = [d for d in done if d["at"] > fail["at"]]
    if fail.get("legacy"):  # 옛 로그: 같은 세션이 다시 돌아 완료 (배치 id 는 같은 분이면 겹치므로 옛 실행에만)
        return any(d["id"] == fail["sid8"] for d in later)
    if fail["run"] and not fail["transcripts"]:  # 세션 없이 훅 실행 기록만 검토한 improve-skills
        return bool(later)
    covered = {t for d in later for t in (d["transcripts"] or [])}
    return bool(fail["transcripts"]) and set(fail["transcripts"]) <= covered


def find_transcript(sid):
    hits = glob.glob(f"{HOME}/.claude/projects/*/{sid}*.jsonl")
    return hits[0] if hits else None


def run_cost(run):
    """meta.json 의 cost_usd, 없으면(옛 실행) stream.jsonl 의 마지막 result"""
    try:
        meta = json.loads(read(f"{run}/meta.json"))
    except ValueError:
        return None, None
    if "cost_usd" in meta:
        return meta.get("finished_at"), meta["cost_usd"] or 0
    cost = 0
    for line in reversed(read(f"{run}/stream.jsonl").splitlines()):
        if '"type":"result"' in line.replace(" ", ""):
            try:
                cost = json.loads(line).get("total_cost_usd") or 0
            except ValueError:
                pass
            break
    return meta.get("finished_at"), cost


def costs(days=COST_DAYS):
    """최근 days일 무인 실행 비용 → {종류: [횟수, 달러]}"""
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    out = {}
    for run in glob.glob(f"{RUNS}/*/*/"):
        at, usd = run_cost(run.rstrip("/"))
        if at and at >= since:
            kind = os.path.basename(os.path.dirname(run.rstrip("/")))
            c = out.setdefault(kind, [0, 0.0])
            c[0] += 1
            c[1] += usd
    for f in glob.glob(f"{OTHER_RUNS}/*/cost.json"):
        try:
            d = json.loads(read(f))
        except ValueError:
            continue
        if d.get("at", "") >= since:
            c = out.setdefault(d.get("kind") or "기타", [0, 0.0])
            c[0] += 1
            c[1] += d.get("usd") or 0
    return out


def parse_pending():
    items = []
    for block in re.split(r"(?m)^## ", read(PENDING))[1:]:
        title, _, body = block.partition("\n")
        evidence = 1 + body.count("추가 근거")
        items.append({"title": title.strip(), "evidence": evidence, "priority": evidence >= PRIORITY_EVIDENCE})
    return items


def collect(all_items=False):
    state = load_state()
    seen_at = "" if all_items else state.get("seen_at", "")
    seen_pending = set() if all_items else set(state.get("pending", []))
    mods, fails = parse_log()
    pending = parse_pending()
    for p in pending:
        p["new"] = p["title"] not in seen_pending
    return {
        "seen_at": state.get("seen_at"),
        "mods": [m for m in mods if m["at"] > seen_at],
        "fails": [f for f in fails if f["at"] > seen_at],
        "pending": pending,
    }


# ---------------------------------------------------------------- SessionStart
def hook():
    if os.environ.get("CLAUDE_HOOK_CHILD"):
        return
    d = collect()
    new_pending = [p for p in d["pending"] if p["new"]]
    stale = d["pending"] and (
        not d["seen_at"]
        or datetime.strptime(d["seen_at"], "%Y-%m-%d %H:%M:%S") < datetime.now() - timedelta(days=REMIND_DAYS)
    )
    week = sum(usd for _, usd in costs().values())
    if not (d["mods"] or d["fails"] or new_pending or stale or week > COST_ALERT_USD):
        return
    parts = []
    if d["mods"]:
        parts.append(f"스킬 자동 수정 {len(d['mods'])}건")
    if d["fails"]:
        parts.append(f"실패 {len(d['fails'])}건")
    if d["pending"]:
        extra = []
        if new_pending:
            extra.append(f"새 {len(new_pending)}")
        if n := sum(p["priority"] for p in d["pending"]):
            extra.append(f"⚠️우선 {n}")
        parts.append(f"확인 대기 {len(d['pending'])}건" + (f"({', '.join(extra)})" if extra else ""))
    if week > COST_ALERT_USD:
        parts.append(f"무인 실행 {COST_DAYS}일 ${week:.2f}")
    print(json.dumps({"systemMessage": "🔧 훅 리포트: " + " · ".join(parts) + " → /hook-review"}, ensure_ascii=False))


# ---------------------------------------------------------------- 리포트
def skill_dir(m):
    if m["dir"]:
        return m["dir"]
    p = f"{HOME}/.claude/skills/{m['skill']}"
    if os.path.isdir(p):
        return p
    # 옛 로그에는 위치가 없다. CHANGELOG 의 "위치:" 에서 찾는다
    for loc in re.findall(r"위치: (\S+)", read(CHANGELOG)):
        if loc.rstrip("/").endswith("/" + m["skill"]) and os.path.isdir(loc):
            return loc
    return None


def compare_target(m):
    """백업과 비교할 대상: 수정 직후 스냅샷(<ts>-after) 또는 같은 스킬의 다음 백업, 없으면 현재 스킬"""
    base = os.path.dirname(m["backup"])
    snaps = sorted(os.listdir(base)) if os.path.isdir(base) else []
    later = [s for s in snaps if s > os.path.basename(m["backup"])]
    return os.path.join(base, later[0]) if later else skill_dir(m)


def changelog_entry(m):
    ts = os.path.basename(m["backup"])
    for block in re.split(r"(?m)^(?=## )", read(CHANGELOG)):
        head = block.split("\n", 1)[0]
        if m["skill"] in head and (ts in head or ts[:-2] in head):
            return block.strip()
    return None


def diff(a, b):
    if not (a and b and os.path.isdir(a) and os.path.isdir(b)):
        return "(비교할 폴더가 없음)"
    out = subprocess.run(["diff", "-ru", "-x", ".DS_Store", "-x", "__pycache__", a, b],
                         capture_output=True, text=True).stdout.splitlines()
    if len(out) > DIFF_MAX_LINES:
        out = out[:DIFF_MAX_LINES] + [f"... ({len(out) - DIFF_MAX_LINES}줄 생략)"]
    return "\n".join(out) or "(차이 없음)"


def fail_reason(run):
    if not run:
        return "알 수 없음"
    for line in reversed(read(f"{run}/stream.jsonl").splitlines()):
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "result":
            return (ev.get("result") or ev.get("subtype") or "").strip()[:200]
    err = read(f"{run}/stderr.txt").strip().splitlines()
    return err[-1][:200] if err else "알 수 없음"


def report(all_items):
    d = collect(all_items)
    out = [f"# 훅 리포트 (마지막 확인: {d['seen_at'] or '없음'}{', 전체 보기' if all_items else ''})", ""]

    out.append(f"## 1. 스킬 자동 수정 ({len(d['mods'])}건)")
    for i, m in enumerate(d["mods"], 1):
        target = compare_target(m)
        note = "" if target and target.startswith(HIST) else " (현재 스킬 — 훅 이후 수동 수정도 섞여 있을 수 있으니 CHANGELOG 항목과 대조)"
        out += ["", f"### 1-{i}. {m['skill']} — {m['at']} (세션 {m['sid8']})",
                f"- 스킬 위치: `{skill_dir(m) or '찾지 못함'}`",
                f"- 수정 전 백업: `{m['backup']}`",
                f"- 비교 대상: `{target}`{note}", "",
                changelog_entry(m) or "(CHANGELOG 항목 없음)", "",
                "```diff", diff(m["backup"], target), "```"]

    out += ["", f"## 2. 실패 ({len(d['fails'])}건, 나중에 다시 돌아 완료된 것은 뺌)"]
    for f in d["fails"]:
        ts = [t for t in f["transcripts"] or [] if os.path.exists(t)]
        out += [f"- {f['at']} {f['skill']} ({f['sid8']}, 세션 {len(f['transcripts'] or [])}개) — 원인: {fail_reason(f['run'])}",
                f"  - 실행 기록: `{f['run']}`"]
        if ts:
            out.append(f"  - 다시 돌리기: `{SCRIPT} --run {' '.join(ts)}` (실패한 세션은 대기열에 남아 다음 일괄 실행 때도 다시 돈다)")
        elif f["transcripts"]:
            out.append("  - 원 세션 transcript를 찾지 못해 다시 돌릴 수 없음")
        else:
            out.append(f"  - 다시 돌리기: `{SCRIPT} --flush` (대기열과 검토 대기 훅 실행 기록을 지금 처리)")

    out += ["", f"## 3. 확인 대기 수정안 ({len(d['pending'])}건, 전문은 `{PENDING}`)"]
    for i, p in enumerate(d["pending"], 1):
        tags = (["새"] if p["new"] else []) + (["⚠️우선"] if p["priority"] else [])
        out.append(f"{i}. {p['title']} — 근거 {p['evidence']}회" + (f" [{', '.join(tags)}]" if tags else ""))

    c = costs()
    total = sum(usd for _, usd in c.values())
    out += ["", f"## 4. 최근 {COST_DAYS}일 무인 실행 비용 (${total:.2f}, 알림 기준 ${COST_ALERT_USD})"]
    for kind, (n, usd) in sorted(c.items(), key=lambda x: -x[1][1]):
        out.append(f"- {kind}: {n}회 ${usd:.2f}")
    if not c:
        out.append("- (없음)")
    print("\n".join(out))


def mark():
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    state = {"seen_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
             "pending": [p["title"] for p in parse_pending()]}
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=1)
    print(f"확인 시점 기록: {state['seen_at']} (확인 대기 {len(state['pending'])}건)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--report" in args:
        report("--all" in args)
    elif "--mark" in args:
        mark()
    else:
        try:
            hook()
        except Exception as e:  # 세션 시작을 방해하지 않는다
            print(json.dumps({"systemMessage": f"🔧 hook-digest 오류: {e}"}, ensure_ascii=False))
