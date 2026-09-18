#!/usr/bin/env python3
"""skill 四副本镜像同步 / 校验。正本 = ~/.workbuddy/skills。"""
import argparse
import hashlib
import os
import shutil
import sys

A = os.path.expanduser(os.path.join("~", ".workbuddy", "skills"))
COPIES = {
    "B_drafts": os.path.join("I:" + os.sep, "工作项目", "shellstrom2", "ShellStorm2", "skills_drafts"),
    "C_project_codex": os.path.join("I:" + os.sep, "工作项目", "shellstrom2", "ShellStorm2", ".codex", "skills"),
    "D_user_codex": os.path.expanduser(os.path.join("~", ".codex", "skills")),
}
SKIP_DIRS = {"__pycache__", ".git"}


def tree(root):
    out = {}
    for dp, dns, fs in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for f in fs:
            fp = os.path.join(dp, f)
            rel = os.path.relpath(fp, root).replace("\\", "/")
            with open(fp, "rb") as fh:
                out[rel] = hashlib.sha256(fh.read()).hexdigest()
    return out


def skills_of(root):
    return sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))


def canon_tree():
    """A 内所有 skill 目录的文件（排除根部引擎标记文件）。"""
    out = {}
    for s in skills_of(A):
        for rel, h in tree(os.path.join(A, s)).items():
            out[s + "/" + rel] = h
    return out


def copy_tree(src, dst):
    for dp, dns, fs in os.walk(src):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        rel = os.path.relpath(dp, src)
        tgt = dst if rel == "." else os.path.join(dst, rel)
        os.makedirs(tgt, exist_ok=True)
        for f in fs:
            shutil.copy2(os.path.join(dp, f), os.path.join(tgt, f))


def do_sync():
    skills = skills_of(A)
    for name, root in COPIES.items():
        if not os.path.isdir(root):
            print("!! copy missing, skip: %s %s" % (name, root))
            continue
        for s in skills:
            d = os.path.join(root, s)
            if os.path.isdir(d):
                shutil.rmtree(d)
            copy_tree(os.path.join(A, s), d)
        print("  -> %s: wrote %d skills" % (name, len(skills)))
    return 0


def do_check():
    skills = skills_of(A)
    ta = canon_tree()
    bad = 0
    eol_bad = []
    for p in sorted(ta):
        with open(os.path.join(A, p), "rb") as fh:
            b = fh.read()
        crlf = b.count(b"\r\n")
        lone = b.replace(b"\r\n", b"").count(b"\n")
        bare = b.count(b"\r") - crlf
        if not (crlf and not lone and not bare):
            eol_bad.append(p)
    for name, root in COPIES.items():
        if not os.path.isdir(root):
            print("  !! copy missing: %s" % name)
            bad += 1
            continue
        tb = tree(root)
        local = set(skills_of(root))
        for s in skills:
            sa = {p: h for p, h in ta.items() if p.startswith(s + "/")}
            sb = {p: h for p, h in tb.items() if p.startswith(s + "/")}
            if sa != sb:
                miss = sorted(set(sa) - set(sb))
                ext = sorted(set(sb) - set(sa))
                dif = sorted(x for x in set(sa) & set(sb) if sa[x] != sb[x])
                print("  XX %s/%s miss=%s extra=%s diff=%s" % (name, s, miss, ext, dif))
                bad += 1
        missing_skill = sorted(set(skills) - local)
        if missing_skill:
            print("  !! %s missing skills: %s" % (name, missing_skill))
            bad += 1
    if eol_bad:
        print("  !! A has %d non-CRLF file(s):" % len(eol_bad))
        for p in eol_bad:
            print("       %s" % p)
        bad += 1
    if bad:
        print("SKILL_MIRROR_CHECK_FAIL issues=%d" % bad)
        return 1
    print("SKILL_MIRROR_CHECK_OK skills=%d files=%d copies=%d" % (len(skills), len(ta), len(COPIES)))
    return 0


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--sync", action="store_true")
    g.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(A):
        print("!! canon missing: %s" % A)
        return 1
    return do_sync() if a.sync else do_check()


if __name__ == "__main__":
    sys.exit(main())
