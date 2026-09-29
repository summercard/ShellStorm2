#!/usr/bin/env python3
"""清理 ShellStorm2 验证套件遗留的 mktemp 工作区。

背景
----
`scripts/run_verification_suite.sh` 用 `mktemp -d` 建一个隔离工程，并把主工程的
`.godot/imported` 缓存整份复制进去（`seed_isolated_import_cache`），单轮约 5 GB。
正常退出由 EXIT/INT/TERM trap 里的 `cleanup_verification_workspace()` 删除；但被
watchdog `kill -9` / `taskkill /F` 强杀时 trap 不触发 ⇒ 残留。

2026-09-29 实测：`%LOCALAPPDATA%\\Temp` 下堆了 9 个残留合计 32.7 GB，把系统盘压到
只剩 1.55 GB，且「跑一轮漏一个」。本工具是那条缺失的兜底：可手动跑，也被套件在每
次启动时自动调用（只清陈旧残留）。

用法
----
    python purge_stale_verification_workspaces.py                # 清 >6h 的陈旧残留
    python purge_stale_verification_workspaces.py --dry-run      # 只看不删
    python purge_stale_verification_workspaces.py --all          # 不按年龄过滤
    python purge_stale_verification_workspaces.py --no-system-temp
    python purge_stale_verification_workspaces.py --base <dir>   # 额外扫描的基址

安全护栏
--------
1. 目标目录必须**恰好**位于被扫描基址的根下（防相对路径 / junction 把删除引到别处）；
2. 目录名必须以 `shellstorm-verification.` 开头，且后缀长度 = 6（mktemp 模板）；
3. 目录树内**出现任何 reparse point（junction/symlink）即整体拒绝** —— 不跟随、不
   穿透。本项目里确实存在指向主工程的 junction（`_scratch/entry_cinematic_project`
   有 9 个，指回 assets/ source/ .godot/ 等），一旦跟随就会把主工程删掉；
4. 默认只删 **mtime 早于 --max-age-hours**（默认 6）的目录，避免误删另一个正在运行
   的套件实例的工作区；
5. 删除用 `SHFileOperationW` **不带** `FOF_ALLOWUNDO` ⇒ 永久删除，不进回收站
   （进回收站空间不释放，等于没清）。
"""

from __future__ import annotations

import argparse
import ctypes
import os
import shutil
import stat
import sys
import time
from ctypes import wintypes
from pathlib import Path

PREFIX = "shellstorm-verification."
SUFFIX_LEN = 6
REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
IS_WINDOWS = os.name == "nt"

FO_DELETE = 0x0003
FOF_SILENT = 0x0004
FOF_NOCONFIRMATION = 0x0010
FOF_NOERRORUI = 0x0400
FOF_NOCONFIRMMKDIR = 0x0200
# 刻意不含 FOF_ALLOWUNDO(0x0040)：要永久删除，否则进回收站、空间不释放。


class SHFILEOPSTRUCTW(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND),
        ("wFunc", wintypes.UINT),
        ("pFrom", wintypes.LPCWSTR),
        ("pTo", wintypes.LPCWSTR),
        ("fFlags", ctypes.c_uint16),
        ("fAnyOperationsAborted", wintypes.BOOL),
        ("hNameMappings", ctypes.c_void_p),
        ("lpszProgressTitle", wintypes.LPCWSTR),
    ]


def repo_root() -> Path:
    """本文件位于 <repo>/scripts/ ⇒ 仓库根是上一级。"""
    return Path(__file__).resolve().parent.parent


def default_bases() -> list[Path]:
    return [repo_root() / "_scratch" / ".verify_ws"]


def system_temp_base() -> Path | None:
    tmp = os.environ.get("LOCALAPPDATA")
    if IS_WINDOWS and tmp:
        return Path(tmp) / "Temp"
    for key in ("TMPDIR", "TEMP", "TMP"):
        value = os.environ.get(key)
        if value:
            return Path(value)
    return Path("/tmp")


def scan_tree(root: Path) -> tuple[int, int, list[str]]:
    """返回 (总字节, 文件数, reparse point 相对路径列表)。不跟随 reparse。"""
    total = 0
    files = 0
    links: list[str] = []
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            links.append(str(Path(entry.path).relative_to(root)))
                            continue
                        lst = os.lstat(entry.path)
                        if getattr(lst, "st_file_attributes", 0) & REPARSE:
                            links.append(str(Path(entry.path).relative_to(root)))
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            stack.append(Path(entry.path))
                        else:
                            total += lst.st_size
                            files += 1
                    except OSError:
                        pass
        except OSError:
            pass
    return total, files, links


def permanent_delete(path: Path) -> int:
    if IS_WINDOWS:
        op = SHFILEOPSTRUCTW()
        op.wFunc = FO_DELETE
        op.pFrom = str(path) + "\x00\x00"
        op.pTo = None
        op.fFlags = (
            FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_NOCONFIRMMKDIR
        )
        return ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
    shutil.rmtree(path)
    return 0


def collect(base: Path, max_age_seconds: float | None) -> list[tuple[Path, int]]:
    """列出一个基址下符合条件的残留目录。"""
    if not base.is_dir():
        return []
    base_resolved = base.resolve()
    picked: list[tuple[Path, int]] = []
    now = time.time()
    with os.scandir(base) as it:
        for entry in sorted(it, key=lambda e: e.name):
            try:
                if not entry.is_dir(follow_symlinks=False) or entry.is_symlink():
                    continue
            except OSError:
                continue
            name = entry.name
            if not name.startswith(PREFIX):
                continue
            if len(name) - len(PREFIX) != SUFFIX_LEN:
                print(f"  SKIP 非 mktemp 模板名：{name}")
                continue
            target = Path(entry.path)
            # 护栏 1：必须真的在基址根下（防 junction / 相对路径把删除引到别处）
            try:
                if target.resolve().parent != base_resolved:
                    print(f"  SKIP 不在基址根下：{name}")
                    continue
            except OSError:
                continue
            # 护栏 4：只清陈旧残留
            if max_age_seconds is not None:
                try:
                    mtime = target.stat().st_mtime
                except OSError:
                    mtime = 0
                if now - mtime < max_age_seconds:
                    print(
                        f"  SKIP 仍新鲜（{format_age(now - mtime)}）：{name}"
                    )
                    continue
            picked.append((target, 0))
    return picked


def format_age(seconds: float) -> str:
    if seconds < 3600:
        return f"{seconds / 60:.0f} 分钟"
    if seconds < 86400:
        return f"{seconds / 3600:.1f} 小时"
    return f"{seconds / 86400:.1f} 天"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="清理验证套件遗留的 shellstorm-verification.* 工作区"
    )
    parser.add_argument("--base", action="append", default=[], help="额外扫描的基址目录")
    parser.add_argument("--no-system-temp", action="store_true", help="不扫描系统 Temp")
    parser.add_argument(
        "--max-age-hours",
        type=float,
        default=6.0,
        help="只清理 mtime 早于该小时数的残留（默认 6）",
    )
    parser.add_argument("--all", action="store_true", help="忽略年龄，清理全部残留")
    parser.add_argument("--dry-run", action="store_true", help="只列出，不删除")
    args = parser.parse_args(argv)

    bases: list[Path] = [Path(b) for b in args.base]
    bases += default_bases()
    if not args.no_system_temp:
        tmp = system_temp_base()
        if tmp is not None:
            bases.append(tmp)

    seen: set[str] = set()
    ordered: list[Path] = []
    for base in bases:
        key = str(base.resolve()) if base.exists() else str(base)
        if key in seen:
            continue
        seen.add(key)
        ordered.append(base)

    max_age = None if args.all else args.max_age_hours * 3600
    now = time.time()
    targets: list[tuple[Path, int, int, list[str], float]] = []
    for base in ordered:
        picked = collect(base, max_age)
        for target, _ in picked:
            size, files, links = scan_tree(target)
            try:
                age = now - target.stat().st_mtime
            except OSError:
                age = 0.0
            targets.append((target, size, files, links, age))

    if not targets:
        print("没有遗留的 shellstorm-verification.* 目录")
        return 0

    total = sum(t[1] for t in targets)
    print(f"发现 {len(targets)} 个残留，合计 {total / 1024**3:.3f} GB：")
    for target, size, files, links, age in targets:
        flag = f"  ⚠ 含 {len(links)} 个 reparse point ⇒ 拒绝删除" if links else ""
        print(
            f"  {size / 1024**3:8.3f} GB  {files:6d} 文件  "
            f"age {format_age(age):>9}  {target}{flag}"
        )

    if args.dry_run:
        print("\n--dry-run：未删除任何东西")
        return 0

    deleted = 0
    refused: list[str] = []
    failed: list[str] = []
    for target, size, _files, links, _age in targets:
        # 护栏 3：目录树里出现任何 reparse point 就整体拒绝，绝不穿透
        if links:
            refused.append(f"{target.name}（含 {len(links)} 个 reparse point）")
            continue
        rc = permanent_delete(target)
        if rc == 0 and not target.exists():
            deleted += size
        else:
            failed.append(f"{target.name} (rc={rc})")

    print(f"\n已永久删除 {deleted / 1024**3:.3f} GB")
    for item in refused:
        print(f"  REFUSED {item}")
    for item in failed:
        print(f"  FAILED  {item}")
    return 1 if (failed or refused) else 0


if __name__ == "__main__":
    raise SystemExit(main())
