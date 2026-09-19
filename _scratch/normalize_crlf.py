"""把指定文件的裸 LF 统一成 CRLF，并报告改动前后字节数。

项目约定：.gd / .tscn / .json / .md / .py 保持 CRLF。工具生成的文本常常是 LF，
所以每次写完文件都跑一遍，避免整文件行尾 diff 污染。

用法：
    python normalize_crlf.py <file> [<file> ...]
    python normalize_crlf.py --check <file> [<file> ...]   # 只报不改
"""

import sys
from pathlib import Path


def process(path: Path, check_only: bool) -> bool:
    raw = path.read_bytes()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    bare = lf - crlf
    if bare == 0:
        print("OK      %-70s lines=%d crlf=%d" % (path.name, lf, crlf))
        return True
    if check_only:
        print("BARE-LF %-70s bare=%d of %d" % (path.name, bare, lf))
        return False
    fixed = raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    path.write_bytes(fixed)
    print("FIXED   %-70s bare=%d -> crlf=%d" % (path.name, bare, fixed.count(b"\r\n")))
    return True


def main() -> int:
    args = sys.argv[1:]
    check_only = "--check" in args
    targets = [a for a in args if a != "--check"]
    if not targets:
        print(__doc__)
        return 2
    ok = True
    for target in targets:
        path = Path(target)
        if not path.exists():
            print("MISSING %s" % target)
            ok = False
            continue
        ok = process(path, check_only) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
