#!/usr/bin/env python3
"""Claude Code 세션 목록 (ccr 용).
  sessions.py [--grep 키워드]   -> 날짜\t폴더\t제목\tsessionId\tcwd (최신순)
  sessions.py --preview ID     -> 미리보기 텍스트
"""
import json, os, sys, glob, time

ROOT = os.path.expanduser("~/.claude/projects")
HOME = os.path.expanduser("~")
SKIP = ("/private/", "/.claude/", "/Library/")

def short(p):
    return "~" + p[len(HOME):] if p.startswith(HOME) else p

def parse(path):
    cwd = title = custom = None
    prompts = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if cwd is None and '"cwd":"' in line:
                try: cwd = json.loads(line).get("cwd")
                except Exception: pass
            if '"type":"ai-title"' in line or '"type":"custom-title"' in line or '"type":"last-prompt"' in line:
                try: o = json.loads(line)
                except Exception: continue
                t = o.get("type")
                if t == "ai-title": title = o.get("aiTitle") or title
                elif t == "custom-title": custom = o.get("customTitle") or custom
                elif t == "last-prompt" and o.get("lastPrompt"):
                    p = o["lastPrompt"].strip()
                    if not prompts or prompts[-1] != p: prompts.append(p)
    return cwd, (custom or title), prompts

def files():
    return glob.glob(os.path.join(ROOT, "*", "*.jsonl"))

def listing(keyword=None):
    rows = []
    for path in files():
        if keyword:
            with open(path, encoding="utf-8", errors="replace") as f:
                if keyword.lower() not in f.read().lower(): continue
        cwd, title, prompts = parse(path)
        if not cwd or any(s in cwd for s in SKIP) or not prompts: continue
        if not os.path.isdir(cwd): continue
        mtime = os.path.getmtime(path)
        name = title or prompts[0]
        name = " ".join(name.split())[:70]
        sid = os.path.basename(path)[:-6]
        rows.append((mtime, sid, cwd, name))
    rows.sort(reverse=True)
    for mtime, sid, cwd, name in rows:
        print("\t".join([time.strftime("%m-%d %H:%M", time.localtime(mtime)), short(cwd), name, sid, cwd]))

def preview(sid):
    m = glob.glob(os.path.join(ROOT, "*", sid + ".jsonl"))
    if not m: return
    cwd, title, prompts = parse(m[0])
    print(f"제목: {title or '-'}\n폴더: {short(cwd or '')}\n수정: {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(m[0])))}\n")
    print("입력했던 내용 (최근순):")
    for p in reversed(prompts[-15:]):
        print(" •", " ".join(p.split())[:200])

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--preview"]: preview(a[1])
    elif a[:1] == ["--grep"]: listing(" ".join(a[1:]))
    else: listing()
