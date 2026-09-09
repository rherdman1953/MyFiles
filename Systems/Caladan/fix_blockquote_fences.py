#!/usr/bin/env python3
"""De-quote fenced code blocks that sit inside a markdown blockquote.

python-markdown's fenced_code preprocessor runs before blockquote parsing, so a
'> ```' fence is never detected: the block leaks as raw text and any '#' comment
inside it becomes a heading. build_html.py's source lint rejects this. This
script performs the fix build_html.py asks for.

For each quoted fence it:
  * removes any trailing bare '>' separator line above the fence
  * inserts a blank line, closing the blockquote
  * strips the '> ' prefix from the fence and every line through the closing
    fence, preserving continuation indentation

Rewrites in place. Review with `git diff` before rebuilding.

    python3 fix_blockquote_fences.py caladan_automation_guide.md
"""

import sys


def dequote(s):
    s = s.lstrip()
    if s.startswith("> "):
        return s[2:]
    return "" if s == ">" else s


def fix(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    out, i, fixed = [], 0, 0

    while i < len(lines):
        if not lines[i].lstrip().startswith("> ```"):
            out.append(lines[i])
            i += 1
            continue

        # Close the blockquote above the fence.
        while out and out[-1].strip() == ">":
            out.pop()
        if out and out[-1].strip():
            out.append("")

        # Emit the opening fence, then everything through the closing fence.
        out.append(dequote(lines[i]))
        i += 1
        while i < len(lines):
            closing = lines[i].lstrip().startswith("> ```")
            out.append(dequote(lines[i]))
            i += 1
            if closing:
                break
        fixed += 1

    open(path, "w", encoding="utf-8").write("\n".join(out))
    return fixed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: fix_blockquote_fences.py <file.md>")
    n = fix(sys.argv[1])
    print(f"de-quoted {n} fenced block(s)" if n else "no quoted fences found")
