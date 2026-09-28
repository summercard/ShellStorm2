#!/usr/bin/env python3
"""只读审计 WorkBuddy 数据目录占用。不做任何修改。

用法:
    python audit_disk.py [--root C:\\Users\\<you>\\.workbuddy] [--deep]
"""
import argparse
import os
import shutil
import sys

DEFAULT_ROOT = os.path.join(os.path.expanduser("~"), ".workbuddy")

LEVEL_A = [
    "logs", "traces", "file-tree-manifests", "cache", "tmp",
    "clipboard-images", "shell-snapshots",
    os.path.join("app", "CodeCache"), os.path.join("app", "Crashpad"),
    os.path.join("app", "cache"),
]
LEVEL_B = ["workspace", "blobs", "changes-detail", "file-history", "changes-index"]
LEVEL_C = [
    "skills", "memory", "SOUL.md", "IDENTITY.md", "USER.md", "MEMORY.md",
    "workbuddy.db", "settings.json", "sessions", "projects",
    "connectors", "keyblob", "security", "plugins", "binaries",
    "audit-log", "storage", "app", "security",
]


def dirsize(p):
    if os.path.isfile(p):
        try:
            return os.path.getsize(p), 1
        except OSError:
            return 0, 0
    t = n = 0
    for dp, _, fns in os.walk(p):
        for f in fns:
            try:
                t += os.path.getsize(os.path.join(dp, f)); n += 1
            except OSError:
                pass
    return t, n


def human(b):
    if b >= 2 ** 30:
        return f"{b/2**30:.2f} GB"
    return f"{b/1048576:.1f} MB"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--deep", action="store_true", help="列出子目录明细")
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        print(f"目录不存在: {root}")
        sys.exit(1)

    print(f"审计目标: {root}")
    try:
        t, u, f = shutil.disk_usage(os.path.splitdrive(root)[0] + os.sep)
        print(f"所在盘: free {f/2**30:.2f} GB / used {u*100/t:.0f}%")
    except Exception:
        pass
    print()

    items = {}
    total = 0
    for name in os.listdir(root):
        p = os.path.join(root, name)
        s, n = dirsize(p)
        items[name] = (s, n)
        total += s

    def bucket(name):
        if name in LEVEL_A:
            return "A"
        if name in LEVEL_B:
            return "B"
        if name in set(LEVEL_C):
            return "C"
        return "?"

    label = {
        "A": "A 级 可安全清理",
        "B": "B 级 可删但功能降级",
        "C": "C 级 绝对不能删（另含未识别项 ?，请人工判断）",
    }

    print(f"{'级别':<4}{'大小':>12}{'文件数':>10}  目录")
    print("-" * 62)
    for grp in "ABC?":
        rows = [(v, k) for k, v in items.items() if bucket(k) == grp]
        if not rows:
            continue
        rows.sort(reverse=True)
        if grp != "?":
            print(f"[{label[grp]}]")
        for (s, n), k in rows:
            print(f" {grp:<3}{human(s):>12}{n:>10}  {k}")
        if grp in "AB":
            sub = sum(s for (s, n), k in rows)
            print(f"     └─ {grp} 级小计 {human(sub)}")
        print()

    print("-" * 62)
    print(f"合计 {human(total)}   （A+B 可回收上限约 "
          f"{human(sum(s for k,(s,n) in items.items() if bucket(k) in 'AB'))}）")
    print()
    print("提示：本环境删除会进回收站并被备份到 workspace/sessions/<sid>/modify_backup，")
    print("      因此实际回收量 = 删除量，且必须追加一步清空回收站。详见 SKILL.md。")

    if a.deep and "logs" in items:
        print("\n--- logs/ 明细 ---")
        ld = os.path.join(root, "logs")
        sub = []
        for name in os.listdir(ld):
            s, n = dirsize(os.path.join(ld, name))
            sub.append((s, n, name))
        sub.sort(reverse=True)
        for s, n, name in sub[:15]:
            print(f"  {human(s):>12}{n:>10}  {name}")


if __name__ == "__main__":
    main()
