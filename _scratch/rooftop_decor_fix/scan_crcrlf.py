#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫描工作区里的 CRCRLF（0d0d0a）异常行尾形态。

背景：某次 Python 以文本模式追加写入已含 CRLF 的文件，导致每行变成 \r\r\n。
      git 的 clean 过滤器只能把 \r\r\n 削成 \r\n（仍 != blob 的 LF），
      于是整个文件被当成「全文件改写」，git diff 出现数千行噪声。

只读扫描，不改文件。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKIP_DIRS = {".git", ".godot", "node_modules", "__pycache__", ".import"}
EXTS = {".gd", ".tscn", ".tres", ".json", ".md", ".cfg", ".py", ".sh", ".txt", ".import"}


def main() -> int:
    hits = []
    seen = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext not in EXTS:
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            seen += 1
            n = data.count(b"\r\r\n")
            if n:
                hits.append((n, os.path.relpath(path, ROOT).replace("\\", "/")))

    hits.sort(reverse=True)
    print("SCANNED=%d" % seen)
    print("CRCRLF_FILES=%d" % len(hits))
    for n, rel in hits:
        print("  %6d  %s" % (n, rel))
    return 0


if __name__ == "__main__":
    sys.exit(main())
