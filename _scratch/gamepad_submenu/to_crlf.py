"""把新建的 .gd 统一成 CRLF（项目里 .gd/.tscn/.json/.md 一律 CRLF）。

只做字节级换行归一：先把 CRLF 压成 LF，再全量展开成 CRLF，避免出现 CRCRLF。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("用法: python to_crlf.py <相对路径> [更多]")
        return 2
    for rel in argv[1:]:
        path = ROOT / rel
        if not path.exists():
            print(f"FAIL 不存在：{rel}")
            return 1
        raw = path.read_bytes()
        normalized = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
        changed = normalized != raw
        if changed:
            path.write_bytes(normalized)
        print(f"{'OK  ' if changed else 'SKIP'} {rel} ({len(raw)} → {len(normalized)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
