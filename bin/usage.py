#!/usr/bin/env python3
"""스킬·프로젝트 마지막 사용 시각을 모아 JSON 파일에 누적한다 (기존 값과 비교해 더 최근 것만 남김).

Claude Code 는 transcript 를 일정 기간 뒤 지우므로, 아카이브 판단에 쓸 사용 기록을 레포에 쌓아 둔다.

    usage.py OUT_JSON

출처
  - ~/.claude/history.jsonl       사용자가 친 /<스킬> 과 작업 경로(project)
  - ~/.claude/projects/*/*.jsonl  Skill 도구 호출, 슬래시 커맨드
  - ~/.claude/hooks/runs/<스킬>/   훅이 무인 실행한 스킬
결과: {"skills": {이름: ISO 시각}, "projects": {홈 기준 경로: ISO 시각}}
"""
import json, os, re, sys, glob
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
C = os.path.join(HOME, ".claude")
out_path = sys.argv[1]

usage = {"skills": {}, "projects": {}}
if os.path.exists(out_path):
    with open(out_path) as f:
        usage.update(json.load(f))


def bump(kind, key, ts):
    if not key or ts is None:
        return
    iso = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if usage[kind].get(key, "") < iso:
        usage[kind][key] = iso


def parse_iso(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def rel_project(p):
    if not p or not p.startswith(HOME):
        return None
    r = os.path.relpath(p, HOME)
    if r.startswith(".claude"):  # 훅 워커 등의 작업 폴더
        return None
    return "~" if r == "." else r


SLASH = re.compile(r"^/([A-Za-z0-9:_-]+)")

hist = os.path.join(C, "history.jsonl")
if os.path.exists(hist):
    with open(hist, errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            ts = e.get("timestamp", 0) / 1000
            bump("projects", rel_project(e.get("project")), ts)
            m = SLASH.match(e.get("display") or "")
            if m:
                bump("skills", m.group(1), ts)

SKILL_USE = re.compile(r'"name":"Skill","input":\{"skill":"([^"]+)"')
CMD = re.compile(r"<command-name>/?([A-Za-z0-9:_-]+)</command-name>")
TS = re.compile(r'"timestamp":"([^"]+)"')
CWD = re.compile(r'"cwd":"([^"]+)"')
for path in glob.glob(os.path.join(C, "projects", "*", "*.jsonl")):
    try:
        with open(path, errors="replace") as f:
            for line in f:
                if '"Skill"' not in line and "<command-name>" not in line and '"cwd"' not in line:
                    continue
                t = TS.search(line)
                ts = parse_iso(t.group(1)) if t else None
                for m in SKILL_USE.finditer(line):
                    bump("skills", m.group(1), ts)
                for m in CMD.finditer(line):
                    bump("skills", m.group(1), ts)
                c = CWD.search(line)
                if c:
                    bump("projects", rel_project(c.group(1)), ts)
    except OSError:
        pass

for run in glob.glob(os.path.join(C, "hooks", "runs", "*", "*")):
    bump("skills", os.path.basename(os.path.dirname(run)), os.path.getmtime(run))

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(usage, f, ensure_ascii=False, indent=1, sort_keys=True)
    f.write("\n")
