#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 CRCRLF(0d0d0a) 归一回 CRLF(0d0a)，只动行尾、不动任何内容字节。

安全闸：
  - 以二进制读写，绝不触碰行尾以外的字节；
  - 归一前后比对「去掉全部 CR」的内容必须逐字节相同（内容零变化证明）；
  - 归一后不得再残留 0d0d0a。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TARGETS = [
    "src/world3d/TowerFloorStage3D.gd",
]


def main() -> int:
    rc = 0
    for rel in TARGETS:
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        with open(path, "rb") as fh:
            before = fh.read()

        n_before = before.count(b"\r\r\n")
        if n_before == 0:
            print("SKIP(no crcrlf) %s" % rel)
            continue

        after = before.replace(b"\r\r\n", b"\r\n")

        # 闸1：内容零变化
        strip = lambda b: b.replace(b"\r", b"")
        if strip(before) != strip(after):
            print("ABORT content would change: %s" % rel)
            rc = 1
            continue
        # 闸2：无残留
        if after.count(b"\r\r\n"):
            print("ABORT residual crcrlf: %s" % rel)
            rc = 1
            continue

        with open(path, "wb") as fh:
            fh.write(after)

        with open(path, "rb") as fh:
            verify = fh.read()
        print(
            "FIXED %s  crcrlf %d->%d  bytes %d->%d  crlf=%d  lf_only=%d"
            % (
                rel,
                n_before,
                verify.count(b"\r\r\n"),
                len(before),
                len(verify),
                verify.count(b"\r\n"),
                verify.count(b"\n") - verify.count(b"\r\n"),
            )
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
