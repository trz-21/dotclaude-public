#!/usr/bin/env python3
"""~/.claude/me 아래 파일들의 frontmatter(summary, updated)를 모아
~/.claude/CLAUDE.md 의 ME-ARCHIVE 마커 블록을 다시 쓴다. 마커 밖은 건드리지 않는다."""
import re
from pathlib import Path

ROOT = Path.home() / ".claude/me"
CLAUDE_MD = Path.home() / ".claude/CLAUDE.md"
START, END = "<!-- ME-ARCHIVE:START -->", "<!-- ME-ARCHIVE:END -->"


def frontmatter(p):
    m = re.match(r"^---\n(.*?)\n---\n", p.read_text(), re.S)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fm[k.strip()] = v.strip()
    return fm


def main():
    rows = []
    for p in sorted(ROOT.rglob("*.md")):
        rel = p.relative_to(ROOT)
        if any(part.startswith(("_", ".")) for part in rel.parts):
            continue
        fm = frontmatter(p)
        rows.append(f"- `{rel}` — {fm.get('summary', '(요약 없음)')} _(updated {fm.get('updated', '?')})_")

    block = "\n".join([
        START,
        "## About Me (개인 아카이브)",
        "",
        "사용자에 대한 정보는 `~/.claude/me/`에 분류되어 있다. 아래 인덱스를 보고, 답변이나 판단에 사용자 배경이",
        "도움이 될 때 해당 파일을 Read로 열어 참고한다. 새로 알게 된 사용자 정보는 `archive-me` 스킬로 저장한다.",
        "",
        *rows,
        END,
    ])

    text = CLAUDE_MD.read_text() if CLAUDE_MD.exists() else ""
    if START in text and END in text:
        text = re.sub(re.escape(START) + r".*?" + re.escape(END), lambda _: block, text, flags=re.S)
    else:
        text = text.rstrip() + "\n\n" + block + "\n"
    CLAUDE_MD.write_text(text)
    print(f"index rebuilt: {len(rows)} files")


if __name__ == "__main__":
    main()
