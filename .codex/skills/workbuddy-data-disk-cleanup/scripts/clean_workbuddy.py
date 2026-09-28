#!/usr/bin/env python3
"""WorkBuddy 数据目录分级清理。

默认 dry-run。删除采用 Windows 原生 SHFileOperationW（整目录入回收站），
比逐文件 os.remove 快约 12 倍；结束后自动清空回收站完成真正释放。

用法:
    python clean_workbuddy.py --level 1                # 预览 A 级
    python clean_workbuddy.py --level 1 --apply        # 执行 A 级 + 清空回收站
    python clean_workbuddy.py --level 2 --apply        # A+B 级（丢失改动回滚能力）
    python clean_workbuddy.py --level 1 --apply --no-purge   # 不自动清空回收站

级别定义见 SKILL.md。默认跳过「今天」的日志与被占用的文件。
"""
import argparse
import ctypes
import datetime
import os
import re
import shutil
import sys
import time
from ctypes import wintypes

# ---------------- 原生删除 ----------------

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


FO_DELETE = 0x0003
FLAGS = 0x0004 | 0x0010 | 0x0040 | 0x0400 | 0x0200  # SILENT|NOCONFIRMATION|ALLOWUNDO|NOERRORUI|NOCONFIRMMKDIR
SHERB = 0x1 | 0x2 | 0x4


def native_delete(path):
    """整目录/文件移入回收站。返回 True 表示路径已不存在。"""
    op = SHFILEOPSTRUCTW()
    op.wFunc = FO_DELETE
    op.pFrom = os.path.abspath(path) + "\x00\x00"
    op.pTo = None
    op.fFlags = FLAGS
    try:
        rc = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
    except Exception:
        rc = -1
    if rc == 0 and not os.path.exists(path):
        return True
    # 回退：逐文件
    if os.path.isdir(path):
        for dp, dns, fns in os.walk(path, topdown=False):
            for f in fns:
                try:
                    os.remove(os.path.join(dp, f))
                except OSError:
                    pass
            for d in dns:
                try:
                    os.rmdir(os.path.join(dp, d))
                except OSError:
                    pass
        try:
            os.rmdir(path)
        except OSError:
            pass
    elif os.path.isfile(path):
        try:
            os.remove(path)
        except OSError:
            pass
    return not os.path.exists(path)


def purge_recyclebin(drive="C:"):
    shell32 = ctypes.windll.shell32
    _, _, f0 = shutil.disk_usage(drive + os.sep)
    rc = shell32.SHEmptyRecycleBinW(None, drive + os.sep, SHERB)
    _, _, f1 = shutil.disk_usage(drive + os.sep)
    return rc, f1 - f0


# ---------------- 计划 ----------------

def dirsize(p):
    t = n = 0
    for dp, _, fns in os.walk(p):
        for f in fns:
            try:
                t += os.path.getsize(os.path.join(dp, f)); n += 1
            except OSError:
                pass
    return t, n


def build_plan(root, level):
    today = datetime.date.today()
    tstr = today.strftime("%Y-%m-%d")
    tcompact = today.strftime("%Y%m%d")
    day_start = datetime.datetime.combine(today, datetime.time.min).timestamp()
    root_real = os.path.realpath(root)
    plan = []

    def add(kind, p, force=False):
        rp = os.path.realpath(p)
        assert rp.startswith(root_real + os.sep), f"OUTSIDE ROOT: {rp}"
        assert rp != root_real, f"REFUSED root itself: {rp}"
        if not os.path.exists(p):
            return
        if not force:
            try:
                if os.path.isfile(p) and os.path.getmtime(p) >= day_start:
                    return
            except OSError:
                pass
        t, n = dirsize(p) if os.path.isdir(p) else (os.path.getsize(p), 1)
        plan.append((kind, p, t, n))

    # A 级
    ld = os.path.join(root, "logs")
    if os.path.isdir(ld):
        for name in sorted(os.listdir(ld)):
            p = os.path.join(ld, name)
            if os.path.isdir(p) and re.match(r"^\d{4}-\d{2}-\d{2}$", name) and name != tstr:
                add("logs/日期", p)
        sd = os.path.join(ld, "sandbox")
        if os.path.isdir(sd):
            for name in sorted(os.listdir(sd)):
                p = os.path.join(sd, name)
                if os.path.isdir(p) and re.match(r"^\d{8}$", name) and name != tcompact:
                    add("logs/sandbox", p)
                elif os.path.isdir(p) and name == "dumps":
                    add("logs/sandbox/dumps", p)
        for name in ("daemon.old.log", "main.old.log", "renderer.old.log",
                     "mcp-apps-diag.old.log", "installer.log", "register.log",
                     "vendor-extract.log", "win-share-target-registrar.log"):
            add("logs/归档", os.path.join(ld, name))

    for sub in ("traces", "file-tree-manifests"):
        d = os.path.join(root, sub)
        if os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                add(sub, os.path.join(d, name))

    for sub in ("clipboard-images", "shell-snapshots", "tmp",
                os.path.join("app", "CodeCache"), os.path.join("app", "Crashpad"),
                os.path.join("app", "cache")):
        d = os.path.join(root, sub)
        if os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                add("cache/" + sub, os.path.join(d, name), force=True)

    cd = os.path.join(root, "cache")
    if os.path.isdir(cd):
        for name in sorted(os.listdir(cd)):
            add("cache", os.path.join(cd, name))

    if level >= 2:
        ws = os.path.join(root, "workspace", "sessions")
        if os.path.isdir(ws):
            for sid in sorted(os.listdir(ws)):
                mb = os.path.join(ws, sid, "modify_backup")
                if os.path.isdir(mb):
                    add("B/modify_backup", mb, force=True)
        for sub in ("blobs", "changes-detail", "file-history"):
            d = os.path.join(root, sub)
            if os.path.isdir(d):
                for name in sorted(os.listdir(d)):
                    add("B/" + sub, os.path.join(d, name))
    return plan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.expanduser("~"), ".workbuddy"))
    ap.add_argument("--level", type=int, default=1, choices=(1, 2))
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--no-purge", action="store_true", help="不自动清空回收站")
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        print(f"目录不存在: {root}")
        sys.exit(1)

    plan = build_plan(root, a.level)
    total = sum(x[2] for x in plan)
    nfiles = sum(x[3] for x in plan)

    print(f"{'APPLY' if a.apply else 'DRY-RUN'}  level={a.level}  root={root}")
    print(f"计划 {len(plan)} 项，预计 {total/1048576:.1f} MB ({total/2**30:.2f} GB) / {nfiles} 文件")
    print("-" * 70)
    by = {}
    for kind, p, t, n in plan:
        by.setdefault(kind, [0, 0, 0])
        by[kind][0] += t; by[kind][1] += n; by[kind][2] += 1
    for k in sorted(by, key=lambda x: -by[x][0]):
        t, n, c = by[k]
        print(f"  {t/1048576:10.1f} MB  {n:6d}f  x{c:<4d}  {k}")
    print("-" * 70)
    for kind, p, t, n in sorted(plan, key=lambda x: -x[2])[:15]:
        print(f"  {t/1048576:10.1f} MB  {p[len(root)+1:]}")

    if not a.apply:
        print("\n[DRY-RUN] 未删除任何文件。确认后加 --apply。")
        print("提示：--apply 结束后会自动清空回收站（除非 --no-purge）。")
        return

    if not plan:
        print("\n无可清理项。")
        return

    print("\n=== 执行删除 ===")
    t0 = time.time()
    ok = fail = 0
    done_bytes = 0
    for kind, p, t, n in plan:
        if native_delete(p):
            ok += 1; done_bytes += t
        else:
            fail += 1
            print(f"  跳过（占用/无权限）: {p}")
        if ok % 25 == 0 and ok:
            print(f"  ... {ok}/{len(plan)}  已处理 {time.time()-t0:.0f}s")

    print(f"\n删除完成: 成功 {ok} 项，失败 {fail} 项，"
          f"{done_bytes/2**30:.2f} GB，耗时 {time.time()-t0:.0f}s")

    if not a.no_purge:
        drive = os.path.splitdrive(root)[0] or "C:"
        rc, freed = purge_recyclebin(drive)
        print(f"清空回收站 rc={rc}，实际释放 {freed/2**30:+.2f} GB")

    t2, n2 = dirsize(root)
    print(f"\n.workbuddy 现在: {t2/2**30:.2f} GB / {n2} files")
    _, _, f = shutil.disk_usage((os.path.splitdrive(root)[0] or "C:") + os.sep)
    print(f"磁盘可用: {f/2**30:.2f} GB")


if __name__ == "__main__":
    main()
