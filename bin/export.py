#!/usr/bin/env python3
"""원본(비공개) 레포에서 공개 레포를 만든다. sync.sh 가 매번 부른다.

원칙: 공개 레포는 결과물이다. 직접 고치지 않고 매번 원본에서 다시 만든다.
      확인되지 않은 내용은 공개하지 않는다 (검토 실패·대기 → 이전에 검토된 버전 유지, 없으면 비공개 처리).

순서
  1) 원본을 항목 단위로 나누고 export-policy.tsv 로 방식(exclude/redact/copy/review)을 정한다
  2) 텍스트 파일에서 비공개 표시 구역을 지운 "준비본"을 만들고 해시를 구한다
  3) review 항목 중 해시가 캐시(state/export.json)와 다른 것만 Claude 가 검토한다
     (prompts/mask.md, 한 번에 최대 MAX_REVIEW 개, LLM 검토는 REVIEW_INTERVAL 마다 한 번)
  4) 결과를 임시 폴더에 모아 전체를 leak-check 하고, 걸리는 항목은 비공개 처리한다
  5) 공개 레포 작업 트리를 결과로 바꾼다 (.git 제외). 커밋·푸시는 sync.sh 가 한다

    export.py [--no-review] [--force-review ITEM ...]
"""
import fnmatch, hashlib, json, os, re, shutil, subprocess, sys, time
from datetime import datetime

HOME = os.path.expanduser("~")
REG = os.path.join(HOME, ".claude", "dotclaude")
SRC = os.path.realpath(os.path.join(REG, "source"))
OUT = os.path.realpath(os.path.join(REG, "export"))
BIN = os.path.join(SRC, "bin")
CACHE_PATH = os.path.join(SRC, "state", "export.json")
LAST_REVIEW = os.path.join(SRC, "state", "last-export-review")
MAX_REVIEW = int(os.environ.get("DOTCLAUDE_MAX_REVIEW", "10"))
REVIEW_INTERVAL = 6 * 3600
TODAY = datetime.now().strftime("%Y-%m-%d")
RUN = os.path.join(HOME, ".claude", "dotclaude-runs", datetime.now().strftime("export-%Y%m%d-%H%M%S"))

# 자식 하나하나가 항목인 폴더 / 파일 하나하나가 항목인 폴더 / .mirror-source 로 항목을 찾는 폴더
CONTAINERS = ["skills", "agents", "commands", "archive/skills", "archive/agents", "archive/commands", "archive/memory"]
FILE_SPLIT = ["global", "hooks", "setup"]
PROJECT_ROOTS = ["projects", "archive/projects"]
SKIP_NAMES = {".git", ".DS_Store", "__pycache__", ".mirror-source"}
# 표시는 줄 하나를 통째로 차지해야 한다 (앞에 #, // 주석 기호는 허용). 문서 속 설명용 예시는 건드리지 않는다
PRIVATE_BLOCK = re.compile(r"^[ \t]*(?:#|//)?[ \t]*<!-- (ME-ARCHIVE|PRIVATE):START -->[ \t]*$.*?"
                           r"^[ \t]*(?:#|//)?[ \t]*<!-- \1:END -->[ \t]*$", re.S | re.M)
PRIVATE_NOTE = "<!-- 이 구역은 개인 정보라 공개 사본에서 가렸습니다 -->"
# 공개에 필요 없는 메타데이터 줄 (Claude 메모리 머리말의 세션 ID 등)
DROP_LINES = re.compile(r"^[ \t]*(originSessionId|sessionId|session_id)[ \t]*:.*\n?", re.M)


def log(*a):
    print(datetime.now().strftime("%F %T"), "[export]", *a, flush=True)


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


# ---------------------------------------------------------------- 1) 항목과 방식
def list_items():
    items, taken = [], set()

    def add(rel):
        items.append(rel)
        taken.add(rel)

    for root in PROJECT_ROOTS:
        base = os.path.join(SRC, root)
        for dirpath, dirs, files in os.walk(base):
            if ".mirror-source" in files:
                dirs[:] = []
                add(os.path.relpath(dirpath, SRC))
        if os.path.isdir(base):
            taken.add(root)
    for c in CONTAINERS + FILE_SPLIT:
        base = os.path.join(SRC, c)
        if not os.path.isdir(base):
            continue
        taken.add(c)
        for name in sorted(os.listdir(base)):
            if name in SKIP_NAMES:
                continue
            if c in FILE_SPLIT and not os.path.isfile(os.path.join(base, name)):
                continue
            add(f"{c}/{name}")
    # 나머지: 위에서 다룬 폴더의 조상이 아니면 최상위 항목, 조상이면 그 안의 남은 파일
    for dirpath, dirs, files in os.walk(SRC):
        rel_dir = os.path.relpath(dirpath, SRC)
        rel_dir = "" if rel_dir == "." else rel_dir
        dirs[:] = [d for d in dirs if d not in SKIP_NAMES]
        for name in sorted(dirs) + sorted(files):
            if name in SKIP_NAMES:
                continue
            rel = f"{rel_dir}/{name}" if rel_dir else name
            if rel in taken or any(t.startswith(rel + "/") for t in taken) or any(rel.startswith(t + "/") for t in taken):
                continue
            if os.path.isdir(os.path.join(SRC, rel)):
                dirs.remove(name)
            add(rel)
    return sorted(items)


def load_policy():
    rules = []
    with open(os.path.join(SRC, "export-policy.tsv")) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            pat, mode = line.split("\t")[:2]
            rules.append((pat, mode))
    return rules


def mode_of(item, rules):
    for pat, mode in rules:
        if fnmatch.fnmatchcase(item, pat):
            return mode
    return "review"


# ---------------------------------------------------------------- 2) 준비본과 해시
def prepare(item, dst):
    """비공개 표시 구역을 지운 사본을 dst 에 만든다"""
    src = os.path.join(SRC, item)
    if os.path.isdir(src):
        shutil.copytree(src, dst, symlinks=True, ignore=shutil.ignore_patterns(*SKIP_NAMES))
    else:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    for path in walk_files(dst):
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        new = DROP_LINES.sub("", PRIVATE_BLOCK.sub(PRIVATE_NOTE, text))
        root = project_root(item)
        if root:  # 프로젝트 자신의 절대경로 → 프로젝트 루트 기준 상대경로 (구조는 남기고 로컬 위치는 지운다)
            rel_root = "$CLAUDE_PROJECT_DIR" if path.endswith((".sh", ".json", ".py", ".js", ".ts")) else "."
            # 어느 기기의 홈이든 같은 결과가 나오게 (기기마다 해시가 달라져 재검토되지 않도록)
            home_prefix = r"(?:(?:/Users|/home)/[^/\s\"']+|~|\$HOME|\$\{HOME\})/"
            new = re.sub(home_prefix + re.escape(root) + r"(?=[/\s\"'`)]|$)", lambda m: rel_root, new)
        if new != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)


def project_root(item):
    """프로젝트 미러 항목이면 홈 기준 프로젝트 경로 (projects/Desktop/x → Desktop/x)"""
    for root in PROJECT_ROOTS:
        if item.startswith(root + "/"):
            return item[len(root) + 1:]
    return None


def walk_files(path):
    if os.path.isfile(path):
        yield path
        return
    for dirpath, _, files in os.walk(path):
        for f in sorted(files):
            yield os.path.join(dirpath, f)


def tree_hash(path):
    h = hashlib.sha256()
    for f in sorted(walk_files(path)):
        h.update(os.path.relpath(f, path).encode() + b"\0")
        with open(f, "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


# ---------------------------------------------------------------- 공개 경로
def default_public_path(item):
    if item == "PUBLIC_README.md":
        return "README.md"
    for root in PROJECT_ROOTS:  # 로컬 폴더 구조는 공개하지 않는다
        if item.startswith(root + "/"):
            return f"{root}/{os.path.basename(item)}"
    return item


def masked_name(item):
    return "masked-" + hashlib.sha256(item.encode()).hexdigest()[:8]


def leak_check(path, public_rel):
    r = subprocess.run([os.path.join(BIN, "leak-check.sh"), "--paths-from", path, public_rel], capture_output=True, text=True)
    return r.returncode == 0, r.stderr


def safe_public_path(item, want=None):
    """공개 경로가 leak-check 에 걸리면 마지막 이름을 가린다"""
    rel = want or default_public_path(item)
    probe = os.path.join(RUN, "probe")
    os.makedirs(probe, exist_ok=True)
    ok, _ = leak_check(probe, rel)
    if ok:
        return rel
    return f"{os.path.dirname(rel)}/{masked_name(item)}".lstrip("/")


# ---------------------------------------------------------------- redact
def write_redacted(item, dst, show_tree):
    """비공개 안내만 남긴다. show_tree 면 폴더 구조도 남긴다 (policy 가 redact 인 항목만.
    Claude 가 비공개로 판정한 항목은 하위 이름도 단서가 될 수 있어 구조를 남기지 않는다. 판정 사유는 비공개 캐시에만 둔다)"""
    src = os.path.join(SRC, item)
    note = "🔒 **비공개** — 개인 정보나 회사 정보가 들어 있어 공개 사본에서는 내용을 가렸습니다. 원본은 비공개 레포에 있습니다.\n"
    if os.path.isfile(src) or not show_tree:
        target = dst if os.path.isfile(src) else os.path.join(dst, "README.md")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w") as f:
            f.write(note)
        return
    # 폴더 구조만 남긴다 (이름이 차단 목록에 걸리는 폴더는 가림)
    tree, n = [], 0
    for dirpath, dirs, _ in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_NAMES and not d.startswith("."))
        rel = os.path.relpath(dirpath, src)
        if rel == ".":
            continue
        parts = rel.split(os.sep)
        ok, _ = leak_check(os.path.join(RUN, "probe"), "/".join(parts))
        if not ok:
            n += 1
            parts = parts[:-1] + [f"masked-{n}"]
            dirs[:] = []
        out_rel = "/".join(parts)
        os.makedirs(os.path.join(dst, out_rel), exist_ok=True)
        open(os.path.join(dst, out_rel, ".gitkeep"), "w").close()
        tree.append("  " * (len(parts) - 1) + parts[-1] + "/")
    os.makedirs(dst, exist_ok=True)
    with open(os.path.join(dst, "README.md"), "w") as f:
        f.write(note + ("\n구조:\n\n```\n" + "\n".join(tree) + "\n```\n" if tree else ""))


# ---------------------------------------------------------------- 3) Claude 검토
def review(pending, prep):
    stage = os.path.join(RUN, "stage")
    for it in pending:
        dst = os.path.join(stage, it)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        (shutil.copytree if os.path.isdir(os.path.join(prep, it)) else shutil.copy2)(os.path.join(prep, it), dst)
    save_json(os.path.join(RUN, "review-items.json"), pending)
    with open(os.path.join(SRC, "prompts", "mask.md")) as f:
        prompt = f.read() + (f"\n\n작업 폴더: {RUN}\n검토할 항목 목록: {RUN}/review-items.json\n"
                             f"검토할 사본: {stage}/<항목 경로>\n차단 목록: {SRC}/blocklist.txt\n"
                             f"이미 공개된 사본(읽기만): {OUT}\n결과 파일: {RUN}/review.json")
    exe = shutil.which("claude") or os.path.join(HOME, ".local", "bin", "claude")
    try:
        r = subprocess.run([exe, "-p", prompt, "--model", "opus", "--no-session-persistence", "--strict-mcp-config",
                            "--permission-mode", "bypassPermissions", "--tools", "Read", "Write", "Edit", "Glob", "Grep",
                            "--add-dir", SRC, OUT],
                           cwd=RUN, env=dict(os.environ, CLAUDE_HOOK_CHILD="1"), capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=3600)
    except subprocess.TimeoutExpired:
        log("검토 시간 초과 — 이번에는 이전 결과를 유지")
        return {}
    with open(os.path.join(RUN, "review.out.txt"), "w") as f:
        f.write(r.stdout + "\n--- stderr ---\n" + r.stderr)
    if r.returncode != 0:
        log("검토 실패 (exit", r.returncode, ") — 이번에는 이전 결과를 유지")
        return {}
    results = {v["item"]: v for v in load_json(os.path.join(RUN, "review.json"), {}).get("items", [])}
    for it, v in results.items():
        base = os.path.realpath(os.path.join(stage, it))
        for rel in v.get("delete", []):
            target = os.path.realpath(os.path.join(RUN, rel))
            if target.startswith(base):
                (shutil.rmtree if os.path.isdir(target) else os.remove)(target)
    return results


# ---------------------------------------------------------------- 메인
def main():
    role_file = os.path.join(OUT, ".dotclaude-role")
    if not os.path.isfile(role_file) or open(role_file).read().strip() != "export":
        log("공개 레포가 등록되지 않았거나 역할이 export 가 아님:", OUT); return 1
    os.makedirs(RUN, exist_ok=True)
    rules = load_policy()
    cache = load_json(CACHE_PATH, {})
    items = list_items()
    prep = os.path.join(RUN, "prep")
    out = os.path.join(RUN, "out")
    force = set(sys.argv[sys.argv.index("--force-review") + 1:]) if "--force-review" in sys.argv else set()

    plan, pending = {}, []
    for it in items:
        mode = mode_of(it, rules)
        if mode == "exclude":
            continue
        prepare(it, os.path.join(prep, it))
        h = tree_hash(os.path.join(prep, it))
        if mode == "copy":
            ok, _ = leak_check(os.path.join(prep, it), default_public_path(it))
            if ok:
                plan[it] = {"result": "copy", "hash": h, "public_path": default_public_path(it)}
                continue
            log("copy 항목이 유출 검사에 걸려 검토로 넘김:", it)
            mode = "review"
        if mode == "redact":
            plan[it] = {"result": "redacted", "hash": h, "public_path": safe_public_path(it)}
            continue
        c = cache.get(it)
        if c and c.get("hash") == h and it not in force and c.get("result") == "redacted":
            plan[it] = dict(c, public_path=safe_public_path(it))  # 비공개 판정 그대로 (안내문·경로는 다시 만든다)
        elif c and c.get("hash") == h and it not in force and os.path.lexists(os.path.join(OUT, c["public_path"])):
            plan[it] = dict(c, keep=True)  # 이미 검토된 그대로
        else:
            pending.append(it)

    # LLM 검토 (간격·개수 제한). 못 한 항목은 이전 공개본 유지, 없으면 비공개
    reviewed = {}
    last = float(open(LAST_REVIEW).read()) if os.path.exists(LAST_REVIEW) else 0
    if pending and "--no-review" not in sys.argv and (force or time.time() - last >= REVIEW_INTERVAL):
        batch = pending[:MAX_REVIEW]
        log(f"검토 {len(batch)}건 (대기 {len(pending)}건)")
        with open(LAST_REVIEW, "w") as f:  # 실패해도 간격을 지켜 매 세션 재시도하지 않게 먼저 기록
            f.write(str(time.time()))
        reviewed = review(batch, prep)
    for it in pending:
        h = tree_hash(os.path.join(prep, it))
        v = reviewed.get(it)
        if v and v.get("verdict") in ("public", "masked"):
            want = None
            if v.get("public_name"):
                name = re.sub(r"[^A-Za-z0-9._-]", "-", v["public_name"]).strip("-") or masked_name(it)
                want = f"{os.path.dirname(default_public_path(it))}/{name}".lstrip("/")
            plan[it] = {"result": v["verdict"], "hash": h, "public_path": safe_public_path(it, want),
                        "summary": v.get("summary", ""), "blinded": v.get("blinded", ""), "date": TODAY,
                        "from": os.path.join(RUN, "stage" if v["verdict"] == "masked" else "prep", it)}
        elif v:
            plan[it] = {"result": "redacted", "hash": h, "public_path": safe_public_path(it), "reason": v.get("reason", ""), "date": TODAY}
        elif cache.get(it) and os.path.lexists(os.path.join(OUT, cache[it]["public_path"])):
            plan[it] = dict(cache[it], keep=True)   # 검토 대기: 이전에 검토된 공개본 유지 (해시는 옛것 → 다음에 다시 검토)
            log("검토 대기, 이전 공개본 유지:", it)
        else:
            plan[it] = {"result": "redacted", "hash": None, "public_path": safe_public_path(it), "reason": "검토 대기"}
            log("검토 대기, 비공개 처리:", it)

    # 4) 결과 모으기 + 전체 유출 검사
    def build(it, p):
        dst = os.path.join(out, p["public_path"])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if p.get("keep"):
            src = os.path.join(OUT, p["public_path"])
            (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst)
        elif p["result"] == "redacted":
            write_redacted(it, dst, show_tree=mode_of(it, rules) == "redact")
        else:
            src = p.pop("from", None) or os.path.join(prep, it)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst)

    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for it, p in sorted(plan.items()):
        build(it, p)
    for attempt in range(2):
        bad = [it for it, p in plan.items() if not leak_check(os.path.join(out, p["public_path"]), p["public_path"])[0]]
        if not bad:
            break
        for it in bad:
            log("최종 유출 검사에 걸려 비공개 처리:", it)
            dst = os.path.join(out, plan[it]["public_path"])
            (shutil.rmtree if os.path.isdir(dst) else os.remove)(dst)
            plan[it] = {"result": "redacted", "hash": None, "public_path": safe_public_path(it), "reason": "유출 검사 실패"}
            build(it, plan[it])
    else:
        log("유출 검사를 통과하지 못해 export 중단"); return 1

    with open(os.path.join(out, ".dotclaude-role"), "w") as f:
        f.write("export\n")
    write_index(plan, out)
    ok, err = leak_check(out, "")
    if not ok:
        log("최종 전체 유출 검사 실패 — export 중단\n" + err); return 1

    # 5) 공개 레포 작업 트리 교체 (.git 과 .githooks 설정은 그대로)
    subprocess.run(["rsync", "-a", "--delete", "--exclude", ".git", out + "/", OUT + "/"], check=True)
    for it in list(cache):
        if it not in plan:
            del cache[it]
    for it, p in plan.items():
        cache[it] = {k: v for k, v in p.items() if k not in ("keep", "from")}
    save_json(CACHE_PATH, cache)
    counts = {}
    for p in plan.values():
        counts[p["result"]] = counts.get(p["result"], 0) + 1
    log("완료", counts)
    return 0


def write_index(plan, out):
    """공개 레포의 EXPORT.md: 어떤 항목이 어떻게 공개됐는지"""
    label = {"copy": "그대로", "public": "그대로 (검토함)", "masked": "가려서 공개", "redacted": "🔒 비공개"}
    rows = []
    for it, p in sorted(plan.items(), key=lambda x: x[1]["public_path"]):
        # 무엇을 가렸는지(blinded)는 그 자체가 단서가 될 수 있어 공개 목록에 쓰지 않는다 (비공개 캐시에만)
        desc = p.get("summary", "") if p["result"] in ("public", "masked") else ""
        rows.append(f"| `{p['public_path']}` | {label[p['result']]} | {desc.replace('|', '/')} |")
    with open(os.path.join(out, "EXPORT.md"), "w") as f:
        f.write("# 공개 사본 목록\n\n이 레포는 비공개 원본 레포에서 자동으로 만들어진 공개 사본이다. 직접 고치지 않는다.\n"
                "개인 정보·회사 정보가 들어 있는 항목은 가리거나(🔒) 식별 정보를 자리표시자로 바꿨다.\n\n"
                "| 경로 | 공개 방식 | 설명 |\n|---|---|---|\n" + "\n".join(rows) + "\n")


if __name__ == "__main__":
    sys.exit(main())
