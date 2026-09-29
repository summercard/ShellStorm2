"""把 A 里的指定 skill 以「只增不删」方式镜像到 B/C/D 三处副本，并逐文件校验 sha256。

- 只覆盖 + 补齐，绝不 rmtree（本机 Safe-Delete 守卫会拦 rmtree 并留下半删状态）。
- 复制后清副本里的 __pycache__（只删 .pyc 再 rmdir 空目录，不整目录删）。
- 退出码 0 = 全部一致。
"""
import hashlib
import os
import shutil
import sys

A = r"C:\Users\zhuangmenghong\.workbuddy\skills"
B = r"I:\工作项目\shellstrom2\ShellStorm2\skills_drafts"
C = r"I:\工作项目\shellstrom2\ShellStorm2\.codex\skills"
D = r"C:\Users\zhuangmenghong\.codex\skills"

SKILLS = ["shellstorm2-cursor-and-crosshair", "shellstorm2-hud-visual-cleanup"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def rel_files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for name in filenames:
            full = os.path.join(dirpath, name)
            out.append(os.path.relpath(full, root).replace("\\", "/"))
    return sorted(out)


def clean_pycache(root):
    removed = []
    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".pyc"):
                os.remove(os.path.join(dirpath, name))
                removed.append(os.path.join(dirpath, name))
    # 自底向上删空目录
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        if os.path.basename(dirpath) == "__pycache__" and not os.listdir(dirpath):
            os.rmdir(dirpath)
    return removed


def main():
    rc = 0
    for skill in SKILLS:
        src = os.path.join(A, skill)
        if not os.path.isdir(src):
            print("MISSING_IN_A: %s" % skill)
            rc = 1
            continue
        files = rel_files(src)
        if "SKILL.md" not in files:
            print("NO_SKILL_MD: %s" % skill)
            rc = 1
            continue
        # A 侧行尾纯度断言
        bad = [f for f in files if b"\n" in open(os.path.join(src, f), "rb").read()
               and b"\r\n" not in open(os.path.join(src, f), "rb").read()]
        if bad:
            print("A_NON_CRLF: %s -> %s" % (skill, bad))
            rc = 1
            continue

        for label, root in (("B", B), ("C", C), ("D", D)):
            dst = os.path.join(root, skill)
            os.makedirs(dst, exist_ok=True)
            for rel in files:
                target = os.path.join(dst, rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copyfile(os.path.join(src, rel), target)
            clean_pycache(dst)
            # 逐文件校验
            dst_files = rel_files(dst)
            miss = [f for f in files if f not in dst_files]
            diff = [f for f in files
                    if f in dst_files
                    and sha256(os.path.join(src, f)) != sha256(os.path.join(dst, f))]
            status = "OK" if not miss and not diff else "FAIL"
            if status == "FAIL":
                rc = 1
            print("  %-2s %-38s %s files=%d miss=%s diff=%s" % (
                label, skill, status, len(files), miss, diff))
    print("MIRROR_COPY_RESULT=%s" % ("OK" if rc == 0 else "FAIL"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
