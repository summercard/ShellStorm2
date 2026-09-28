#!/usr/bin/env python3
"""清空回收站（WorkBuddy 文件删除的收尾步骤）。

在这个环境里「删除」只把文件搬进回收站，不清空就等于没删。
本脚本用 Windows 原生 SHEmptyRecycleBinW 逐盘清空。

用法:
    python purge_recyclebin.py            # 清 C 盘
    python purge_recyclebin.py C D        # 清指定盘
    python purge_recyclebin.py --audit    # 只审计，不清空
"""
import ctypes
import os
import shutil
import sys

SHERB_NOCONFIRMATION = 0x01
SHERB_NOPROGRESSUI = 0x02
SHERB_NOSOUND = 0x04
FLAGS = SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND


def dirsize(p):
    t = n = 0
    for dp, _, fns in os.walk(p):
        for f in fns:
            try:
                t += os.path.getsize(os.path.join(dp, f)); n += 1
            except OSError:
                pass
    return t, n


def recycle_usage(drive="C:"):
    rb = drive + os.sep + "$Recycle.Bin"
    if not os.path.isdir(rb):
        return 0, 0
    t = n = 0
    for sid in os.listdir(rb):
        p = os.path.join(rb, sid)
        if os.path.isdir(p):
            a, b = dirsize(p)
            t += a; n += b
    return t, n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    audit_only = "--audit" in sys.argv
    drives = [a.rstrip(":\\") + ":" for a in args] or ["C:"]
    shell32 = ctypes.windll.shell32

    for d in drives:
        try:
            _, _, free0 = shutil.disk_usage(d + os.sep)
        except OSError:
            print(f"{d} 不可访问，跳过")
            continue

        sz, n = recycle_usage(d)
        print(f"{d}  回收站 {sz/2**30:.3f} GB / {n} files   磁盘可用 {free0/2**30:.2f} GB")
        if audit_only:
            continue
        if sz == 0:
            print("      回收站已空")
            continue

        rc = shell32.SHEmptyRecycleBinW(None, d + os.sep, FLAGS)
        _, _, free1 = shutil.disk_usage(d + os.sep)
        sz2, _ = recycle_usage(d)
        print(f"      SHEmptyRecycleBinW rc={rc}  (0=成功)")
        print(f"      可用 {free0/2**30:.2f} -> {free1/2**30:.2f} GB "
              f"(释放 {(free1-free0)/2**30:+.2f} GB)   残余 {sz2/2**30:.3f} GB")

    print()
    print("提示：请同时确认回收站里没有用户自己删除的、仍需要的文件。")
    print("      可用 $I 元数据文件解析原路径（见 SKILL.md 第二节）。")


if __name__ == "__main__":
    main()
