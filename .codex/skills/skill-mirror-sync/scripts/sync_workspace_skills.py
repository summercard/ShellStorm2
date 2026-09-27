#!/usr/bin/env python3
"""工作区级 skill 回灌 / 校验。正本 A = ~/.workbuddy/skills  -->  工作区 W = <workspace>/.workbuddy/skills。

W 不在 sync_skill_mirrors.py 的 A/B/C/D 四副本内，但它才是 WorkBuddy 在本项目里
**真正发现 skill 的地方**（SKILL.md §工作区级正本不在四副本内）⇒ 改完 A 必须单独回灌 W。
默认只处理「W 里已经存在的 skill」，不会把 A 的 38 个全灌进去；要新增必须显式 --add。

用法：
    python sync_workspace_skills.py --check                       # 只读校验（退出码 1 = 有差异）
    python sync_workspace_skills.py --sync                         # 以 A 为准回灌 W 现有 skill
    python sync_workspace_skills.py --sync --add NAME [NAME ...]   # 顺带把 A 里的 NAME 拉进 W
    python sync_workspace_skills.py --sync --workspace <path>      # 覆盖工作区根

判据：每个 skill 的全部文件 sha256 与 A 逐字节相同；行尾全 CRLF（W 副本亦要求）。
"""
import argparse
import hashlib
import os
import shutil
import sys

A = os.path.expanduser(os.path.join("~", ".workbuddy", "skills"))
DEFAULT_WORKSPACE = os.path.join("I:" + os.sep, "工作项目", "shellstrom2")
SKIP_DIRS = {"__pycache__", ".git"}


def rel_files(root):
    out = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for f in fns:
            out.append(os.path.relpath(os.path.join(dp, f), root).replace("\\", "/"))
    return sorted(out)


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def lineend_bad(path):
    """返回 (孤立 LF 数, 裸 CR 数)。"""
    with open(path, "rb") as fh:
        b = fh.read()
    lone_lf = sum(1 for i, c in enumerate(b) if c == 0x0A and (i == 0 or b[i - 1] != 0x0D))
    bare_cr = sum(1 for i, c in enumerate(b) if c == 0x0D and (i + 1 >= len(b) or b[i + 1] != 0x0A))
    return lone_lf, bare_cr


def compare(name, src_root, dst_root):
    """返回 (状态, 说明)。"""
    src = os.path.join(src_root, name)
    dst = os.path.join(dst_root, name)
    if not os.path.isdir(src):
        return "SRC-MISSING", "A 里没有这个 skill"
    if not os.path.isdir(dst):
        return "W-MISSING", "W 里还没有（需 --add）"
    fs = rel_files(src)
    dfs = rel_files(dst)
    if dfs != fs:
        only_a = [f for f in fs if f not in set(dfs)]
        only_w = [f for f in dfs if f not in set(fs)]
        return "LIST-DIFF", "仅A:%s 仅W:%s" % (only_a or "-", only_w or "-")
    bad = [f for f in fs if sha(os.path.join(src, f)) != sha(os.path.join(dst, f))]
    badle = [f for f in fs if lineend_bad(os.path.join(src, f)) != (0, 0)]
    if bad:
        return "SHA-DIFF", "%d 个文件不同: %s" % (len(bad), bad[:5])
    if badle:
        return "A-LF", "A 侧行尾不是 CRLF: %s" % badle[:5]
    return "OK", ""


def backfill(name, src_root, dst_root):
    src = os.path.join(src_root, name)
    dst = os.path.join(dst_root, name)
    fs = rel_files(src)
    copied = 0
    for rel in fs:
        s = os.path.join(src, rel)
        d = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if os.path.isfile(d) and sha(s) == sha(d):
            continue
        shutil.copyfile(s, d)          # 字节复制，杜绝换行二次污染
        copied += 1
    # 清掉副本里可能被带过来的 __pycache__（只删 .pyc 再 rmdir，别整目录 rmtree）
    for dp, _dns, fns in os.walk(dst):
        if os.path.basename(dp) == "__pycache__":
            for f in fns:
                os.remove(os.path.join(dp, f))
    for dp, _dns, fns in os.walk(dst, topdown=False):
        if os.path.basename(dp) == "__pycache__" and not os.listdir(dp):
            os.rmdir(dp)
    return copied


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true", help="只读校验")
    g.add_argument("--sync", action="store_true", help="以 A 为准回灌 W")
    ap.add_argument("--add", nargs="*", default=[], help="额外从 A 拉进 W 的 skill 名（可多个）")
    ap.add_argument("--workspace", default=DEFAULT_WORKSPACE)
    args = ap.parse_args()

    W = os.path.join(args.workspace, ".workbuddy", "skills")
    if not os.path.isdir(A):
        print("A 不存在: %s" % A)
        return 2
    if not os.path.isdir(W):
        if not args.sync:
            print("W 不存在: %s" % W)
            return 2
        os.makedirs(W, exist_ok=True)

    names = sorted(d for d in os.listdir(W) if os.path.isdir(os.path.join(W, d)))
    for n in args.add:
        if n not in names:
            names.append(n)
    names = sorted(names)

    print("A  = %s" % A)
    print("W  = %s" % W)
    print("skill 数: %d（W 现有 %d + --add %d）" % (len(names), len(names) - len(args.add), len(args.add)))
    print()
    print("%-42s %-11s %s" % ("skill", "status", "note"))

    problems = []
    for n in names:
        if args.sync:
            if os.path.isdir(os.path.join(A, n)):
                copied = backfill(n, A, W)
            else:
                copied = -1
        else:
            copied = None
        status, note = compare(n, A, W)
        if args.sync and copied is not None:
            note = ("复制 %d 文件; " % copied if copied >= 0 else "A 缺失; ") + note
        if status not in ("OK",):
            problems.append((n, status))
        print("%-42s %-11s %s" % (n, status, note))

    print()
    if problems:
        print("FAILURE: %d 个 skill 未对齐 -> %s" % (len(problems), problems))
        return 1
    print("WORKSPACE_SKILL_SYNC_OK skills=%d" % len(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
