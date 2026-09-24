# -*- coding: utf-8 -*-
"""把指定文件从 LF 归一成 CRLF（先断言当前无 CR，避免 CRCRLF）。"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    "docs/v0.1/design/远征关卡01设计.md",
]

for rel in TARGETS:
    p = ROOT / rel
    b = p.read_bytes()
    assert b"\r" not in b, "already has CR: %s" % rel
    out = b.replace(b"\n", b"\r\n")
    p.write_bytes(out)
    print("CRLF ok  %-48s lf=%d crlf=%d" % (rel, b.count(b"\n"), out.count(b"\r\n")))
