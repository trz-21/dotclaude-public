#!/usr/bin/env python3
"""주간 아카이브 검토. sync.sh 가 7일마다 부른다.

1) 후보 추리기   오래 안 쓴 스킬·에이전트·커맨드, 활동 없는 프로젝트 미러와 메모리
2) 판단         Claude(무인 실행)가 후보를 읽고 아카이브할 것을 decisions.json 으로 고른다
3) 적용         원본 레포 안에서 git mv 로 archive/ 에 옮기고 archive/README.md 에 사유를 남긴다.
                프로젝트는 mirror-ignore.txt 에 추가하고, 원본이 git 밖에 있으면 원본 .claude 도 지운다
공개 사본에 어떻게 보일지는 export.py 가 따로 정한다.

    archive-review.py [--dry-run]
"""
import json, os, re, shutil, subprocess, sys, time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
REG = os.path.join(HOME, ".claude", "dotclaude")
SRC = os.path.realpath(os.path.join(REG, "source"))
PRI = SRC
PROMPTS = os.path.join(SRC, "prompts")
IDLE_DAYS = 60
DRY = "--dry-run" in sys.argv
NOW = time.time()
TODAY = datetime.now().strftime("%Y-%m-%d")
RUN = os.path.join(HOME, ".claude", "dotclaude-runs", datetime.now().strftime("archive-%Y%m%d-%H%M%S"))


def log(*a):
    print(datetime.now().strftime("%F %T"), "[archive-review]", *a, flush=True)


def sh(*cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True).stdout


def iso_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")


def enc(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


# ---------------------------------------------------------------- 사용 기록 (모든 호스트 합산)
usage = {"skills": {}, "projects": {}}
udir = os.path.join(PRI, "state", "usage")
for fn in os.listdir(udir) if os.path.isdir(udir) else []:
    u = load_json(os.path.join(udir, fn), {})
    for kind in usage:
        for k, v in u.get(kind, {}).items():
            if usage[kind].get(k, "") < v:
                usage[kind][k] = v


def added_at(repo, rel):
    out = sh("git", "log", "--diff-filter=A", "--format=%at", "--", rel, cwd=repo, check=False).split()
    return int(out[-1]) if out else NOW


def project_last(rel):
    """rel 또는 그 하위 경로에서의 마지막 작업 시각"""
    best = 0
    for k, v in usage["projects"].items():
        if k == rel or k.startswith(rel + "/"):
            best = max(best, iso_ts(v))
    return best


def newest_mtime(path):
    best = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                best = max(best, os.path.getmtime(os.path.join(root, f)))
            except OSError:
                pass
    return best


def description(path):
    md = os.path.join(path, "SKILL.md") if os.path.isdir(path) else path
    try:
        with open(md) as f:
            m = re.search(r"^description:\s*(.+)$", f.read(4000), re.M)
            return m.group(1).strip()[:300] if m else ""
    except OSError:
        return ""


# ---------------------------------------------------------------- 1) 후보
def archive_candidates():
    cands = []
    for repo in (SRC,):
        for kind in ("skills", "agents", "commands"):
            base = os.path.join(repo, kind)
            for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
                if name.startswith(("_", ".")):
                    continue
                rel = f"{kind}/{name}"
                # 사용 기록이 있으면 그것을, 없으면 레포에 들어온 날을 기준으로 (새 스킬 유예)
                last = iso_ts(usage["skills"].get(name, "")) or added_at(repo, rel)
                idle = (NOW - last) / 86400
                if idle >= IDLE_DAYS:
                    cands.append({"id": rel, "kind": kind[:-1], "idle_days": int(idle),
                                  "last_used": usage["skills"].get(name), "description": description(os.path.join(repo, rel))})
    # 프로젝트 미러: projects/<홈 기준 경로>/.mirror-source 가 있는 곳
    base = os.path.join(PRI, "projects")
    for root, dirs, files in os.walk(base):
        if ".mirror-source" not in files:
            continue
        dirs[:] = []
        rel = os.path.relpath(root, base)
        src = os.path.join(HOME, rel, ".claude")
        last = max(project_last(rel), newest_mtime(src) if os.path.isdir(src) else 0) or added_at(PRI, f"projects/{rel}")
        idle = (NOW - last) / 86400
        if idle >= IDLE_DAYS or not os.path.isdir(src):
            cands.append({"id": f"projects/{rel}", "kind": "project", "idle_days": int(idle),
                          "source_exists": os.path.isdir(src), "last_used": project_last(rel) or None})
    # 메모리: memory/HOME<인코딩 나머지>
    base = os.path.join(PRI, "memory")
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        rest = name[len("HOME"):]
        match = [k for k in usage["projects"] if (k == "~" and rest == "") or (k != "~" and "-" + enc(k) == rest)]
        last = max([iso_ts(usage["projects"][k]) for k in match] + [newest_mtime(os.path.join(base, name))]) or added_at(PRI, f"memory/{name}")
        idle = (NOW - last) / 86400
        if idle >= IDLE_DAYS:
            cands.append({"id": f"memory/{name}", "kind": "memory", "idle_days": int(idle), "project": match[0] if match else None})
    return cands


# ---------------------------------------------------------------- Claude 무인 실행
def claude(prompt_file, extra, model="opus"):
    with open(os.path.join(PROMPTS, prompt_file)) as f:
        prompt = f.read() + "\n\n" + extra
    exe = shutil.which("claude") or os.path.join(HOME, ".local", "bin", "claude")
    env = dict(os.environ, CLAUDE_HOOK_CHILD="1")
    try:
        r = subprocess.run([exe, "-p", prompt, "--model", model, "--no-session-persistence", "--strict-mcp-config",
                            "--permission-mode", "bypassPermissions", "--tools", "Read", "Write", "Edit", "Glob", "Grep",
                            "--add-dir", SRC],
                           cwd=RUN, env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=3600)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"claude 시간 초과 ({prompt_file})")
    with open(os.path.join(RUN, prompt_file + ".out.txt"), "w") as f:
        f.write(r.stdout + "\n--- stderr ---\n" + r.stderr)
    if r.returncode != 0:
        raise RuntimeError(f"claude 실패 ({prompt_file}): exit {r.returncode}")


def append_row(readme, header, row):
    """README 끝의 자동 기록 표에 한 줄 추가 (표가 없으면 만든다)"""
    text = open(readme).read() if os.path.exists(readme) else "# Archive\n"
    if header not in text:
        text = text.rstrip("\n") + "\n\n" + header
    text = text.rstrip("\n") + "\n" + row + "\n"
    with open(readme, "w") as f:
        f.write(text)


ARCHIVE_LOG = "## 자동 아카이브 기록\n\n| 날짜 | 항목 | 사유 |\n|---|---|---|"


def cell(s):
    return (s or "").replace("|", "\\|").replace("\n", " ")


# ---------------------------------------------------------------- 3) 적용
def apply_archive(decisions):
    ignore_path = os.path.join(PRI, "mirror-ignore.txt")
    for d in decisions:
        rel = d["id"]
        repo = SRC
        src, dst = os.path.join(repo, rel), os.path.join(repo, "archive", rel)
        if not os.path.exists(src) or os.path.exists(dst):
            log("건너뜀 (없거나 이미 아카이브에 있음):", d["id"]); continue
        log("아카이브:", d["id"], "-", d.get("reason", ""))
        if DRY:
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        sh("git", "mv", rel, "archive/" + rel, cwd=repo)
        append_row(os.path.join(repo, "archive", "README.md"), ARCHIVE_LOG, f"| {TODAY} | `{rel}` | {cell(d.get('reason'))} |")
        if rel.startswith("projects/"):
            prel = rel[len("projects/"):]
            with open(ignore_path, "a") as f:
                f.write(prel + "\n")
            orig = os.path.join(HOME, prel, ".claude")
            in_git = subprocess.run(["git", "-C", os.path.dirname(orig), "rev-parse"], capture_output=True).returncode == 0
            if os.path.isdir(orig) and not in_git:
                # 레포 사본과 같을 때만 지운다 (권한 기록 등 미러에서 빼는 파일은 비교 제외)
                diff = subprocess.run(["diff", "-rq", "-x", ".DS_Store", "-x", "settings.local.json", "-x", "*.lock",
                                       "-x", "*.log", "-x", ".plan-exists", "-x", ".mirror-source", orig, dst], capture_output=True)
                if diff.returncode == 0:
                    shutil.rmtree(orig); log("원본 .claude 삭제:", orig)
                else:
                    log("원본이 레포 사본과 달라 남겨 둠:", orig)


def main():
    os.makedirs(RUN, exist_ok=True)
    log("작업 폴더:", RUN)
    cands = archive_candidates()
    save_json(os.path.join(RUN, "candidates.json"), cands)
    log(f"아카이브 후보 {len(cands)}건")
    if cands:
        claude("archive-judge.md", f"작업 폴더: {RUN}\n후보 목록: {RUN}/candidates.json\n"
                                   f"원본 레포: {SRC}\n결과 파일: {RUN}/decisions.json")
        apply_archive(load_json(os.path.join(RUN, "decisions.json"), {}).get("archive", []))


if __name__ == "__main__":
    main()
