# -*- coding: utf-8 -*-
"""外科式拆除验证工作区。

安全前提：验证工作区的 project/ 下挂了大量 **符号链接** 指向主工程
（.claude / .codex / .gitignore / .workbuddy ...）。任何 rd /s /q 或
shutil.rmtree 都会穿透删掉主工程。因此：
  · 遇到 reparse point（symlink / junction）只删链接本身，绝不递归；
  · 只删除真实文件与真实目录；
  · 动手前先做一次 dry-run 扫描并打印所有链接目标。

用法：
  python _ws_teardown.py <workspace_dir> --dry-run
  python _ws_teardown.py <workspace_dir>
"""
import os
import sys

FILE_ATTRIBUTE_REPARSE_POINT = 0x400
MARKER_REL = os.path.join("src", "ui", "ItemModelIcon3D.gd")


def project_marker_for(root):
    """验证工作区形如 <project>/_scratch/.verify_ws/<ws>，据此定位主工程标记文件。"""
    norm = root.replace("\\", "/")
    idx = norm.find("/_scratch/")
    if idx < 0:
        return None
    return os.path.normpath(norm[:idx] + "/" + MARKER_REL)


def is_reparse(path):
    try:
        st = os.lstat(path)
    except OSError:
        return None
    return bool(getattr(st, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT)


def scan(root):
    """返回 (links, real_files, real_dirs)。"""
    links, real_files, real_dirs = [], [], []
    stack = [root]
    while stack:
        cur = stack.pop()
        try:
            entries = list(os.scandir(cur))
        except OSError as err:
            print("SCANDIR_FAIL %s %s" % (cur, err))
            continue
        for e in entries:
            rp = is_reparse(e.path)
            if rp is None:
                continue
            if rp:
                links.append(e.path)
                continue
            if e.is_dir(follow_symlinks=False):
                real_dirs.append(e.path)
                stack.append(e.path)
            else:
                real_files.append(e.path)
    return links, real_files, real_dirs


def purge(root, links, real_files, real_dirs):
    n_link = n_file = n_dir = 0
    for p in links:
        try:
            os.unlink(p)
            n_link += 1
        except OSError:
            try:
                os.rmdir(p)   # 目录型 reparse point
                n_link += 1
            except OSError as err:
                print("LINK_FAIL %s %s" % (p, err))
    for p in real_files:
        try:
            os.unlink(p)
            n_file += 1
        except OSError as err:
            print("FILE_FAIL %s %s" % (p, err))
    for p in sorted(real_dirs, key=lambda s: s.count(os.sep), reverse=True):
        try:
            os.rmdir(p)
            n_dir += 1
        except OSError as err:
            print("DIR_FAIL %s %s" % (p, err))
    try:
        os.rmdir(root)
        print("ROOT_REMOVED")
    except OSError as err:
        print("ROOT_FAIL %s" % err)
    return n_link, n_file, n_dir


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = os.path.abspath(sys.argv[1])
    dry = "--dry-run" in sys.argv

    if not os.path.isdir(root):
        print("NOT_A_DIR %s" % root)
        return 2
    if "verify_ws" not in root.replace("\\", "/"):
        print("REFUSE: 目标不在 .verify_ws 下，拒绝执行：%s" % root)
        return 3

    links, real_files, real_dirs = scan(root)
    print("SCAN links=%d real_files=%d real_dirs=%d"
          % (len(links), len(real_files), len(real_dirs)))

    marker = project_marker_for(root)

    outside = []
    for p in links:
        try:
            tgt = os.readlink(p)
        except OSError:
            tgt = "<?>"
        if "ShellStorm2" not in tgt.replace("\\", "/"):
            outside.append((p, tgt))
    print("LINKS_POINTING_OUTSIDE_PROJECT=%d" % len(outside))
    for p, t in outside[:10]:
        print("  OUTSIDE %s -> %s" % (p, t))

    print("PRE_CHECK marker=%s exists=%s"
          % (marker, os.path.isfile(marker) if marker else "N/A"))

    if dry:
        print("DRY_RUN_ONLY")
        return 0

    if outside:
        print("REFUSE: 存在指向主工程之外的链接，需人工确认。")
        return 3

    n_link, n_file, n_dir = purge(root, links, real_files, real_dirs)
    print("PURGED links=%d dirs=%d files=%d" % (n_link, n_dir, n_file))
    print("SURVIVOR_CHECK_OK" if (marker and os.path.isfile(marker)) else "SURVIVOR_CHECK_FAIL")
    return 0


if __name__ == "__main__":
    sys.exit(main())
