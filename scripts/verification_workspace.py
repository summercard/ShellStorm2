"""Native links and link-safe cleanup for isolated verification projects.

Git Bash ln -s may copy entire directories on Windows without symlink permission.
Directory junctions need no elevation. Cleanup never follows their targets.
"""
import argparse
import os
import shutil
import stat
import subprocess
import time
from pathlib import Path

PROJECT=Path(__file__).resolve().parents[1]

def checked_workspace(path):
    path=Path(os.path.abspath(path))
    if path==PROJECT or path.is_relative_to(PROJECT) or path.resolve().is_relative_to(PROJECT):
        raise ValueError('Verification workspace must be outside the project')
    if not path.name.startswith('shellstorm-verification.'):
        raise ValueError('Unexpected verification workspace name')
    if path.is_symlink() or path.is_junction():
        raise ValueError('Workspace root cannot be a link')
    return path

def create(workspace):
    target=workspace/'project'
    target.mkdir(parents=True,exist_ok=True)
    excluded={'project.godot','.git','.godot','.codex-tmp','_scratch','Godot'}
    for source in PROJECT.iterdir():
        if source.name in excluded:continue
        dest=target/source.name
        if source.is_dir():
            if os.name=='nt':
                subprocess.run(['cmd','/c','mklink','/J',str(dest),str(source)],check=True,capture_output=True)
                assert dest.is_junction(),dest
            else:dest.symlink_to(source,target_is_directory=True)
        else:shutil.copy2(source,dest)

REPARSE_ATTRIBUTE = getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)

def _iter_reparse(root):
    """遍历 root，产出所有 reparse point（junction / symlink）路径，**不进入**它们。

    用显式栈而不是 os.walk：后者在部分实现里仍会尝试 follow，这里要的是
    「只认目录项，绝不穿透」。
    """
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except OSError:
            continue
        for entry in entries:
            try:
                info = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if info.st_file_attributes & REPARSE_ATTRIBUTE:
                yield entry
            elif entry.is_dir(follow_symlinks=False):
                stack.append(entry.path)

def _unlink_reparse(root):
    """把 root 下所有链接**当链接删**（os.rmdir 对 junction 只删这一条目录项）。

    必须在递归删除之前跑：一旦有调用方穿透了 junction，删的就不是工作区，
    而是它指回来的主工程。
    """
    removed = 0
    for entry in _iter_reparse(root):
        try:
            if entry.is_dir(follow_symlinks=False):
                os.rmdir(entry.path)
            else:
                os.unlink(entry.path)
            removed += 1
        except OSError:
            pass
    return removed

def _shell_delete(path):
    """单次 SHFileOperationW 删整棵树，返回是否已删掉。

    为什么不用 `remove()` 逐项递归：工作区里 `.godot/imported` 有 5000+ 个小文件，
    逐个 unlink 既慢，又会被上层「单轮批量删除」保护拦在第 50 个上 —— 拦下来的
    结果是**工作区留在盘上**（套件 EXIT trap 的 `assert_workspace_removed` 因此报红，
    每跑一轮多留约 0.4 GB）。一次系统调用没有这个粒度问题。
    """
    if os.name != 'nt':
        return False
    import ctypes

    class SHFILEOPSTRUCTW(ctypes.Structure):
        _fields_ = [
            ('hwnd', ctypes.c_void_p), ('wFunc', ctypes.c_uint),
            ('pFrom', ctypes.c_wchar_p), ('pTo', ctypes.c_wchar_p),
            ('fFlags', ctypes.c_ushort), ('fAnyOperationsAborted', ctypes.c_int),
            ('hNameMappings', ctypes.c_void_p), ('lpszProgressTitle', ctypes.c_wchar_p),
        ]

    FO_DELETE = 0x0003
    FOF_SILENT, FOF_NOCONFIRMATION = 0x0004, 0x0010
    FOF_NOERRORUI, FOF_NOCONFIRMMKDIR = 0x0400, 0x0200
    operation = SHFILEOPSTRUCTW()
    operation.wFunc = FO_DELETE
    operation.pFrom = str(path) + '\0\0'   # 双 NUL = 列表结束
    operation.fFlags = FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_NOCONFIRMMKDIR
    operation.fAnyOperationsAborted = 0
    try:
        result = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(operation))
    except OSError:
        return False
    return result == 0 and not operation.fAnyOperationsAborted and not path.exists()

def remove(path):
    if path.is_junction():os.rmdir(path);return
    if path.is_symlink():path.unlink();return
    if not path.exists():return
    if path.is_dir():
        # Windows：先摘链（绝不穿透），再整棵树一次删完。
        _unlink_reparse(path)
        if not any(True for _ in _iter_reparse(path)) and _shell_delete(path):
            return
        for entry in path.iterdir():remove(entry)
        path.rmdir()
    else:path.unlink()

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['create','cleanup','stale']);parser.add_argument('workspace')
    args=parser.parse_args()
    if args.mode=='stale':
        base=Path(args.workspace).resolve()
        if base==PROJECT or base.is_relative_to(PROJECT):
            raise ValueError('Verification base must be outside the project')
        max_age=float(os.environ.get('SHELLSTORM_VERIFY_PURGE_AGE_HOURS','6'))*3600
        for path in base.iterdir():
            if path.name.startswith('shellstorm-verification.') and time.time()-path.stat().st_mtime>max_age:
                remove(checked_workspace(path))
    else:
        workspace=checked_workspace(args.workspace)
        if args.mode=='create':create(workspace)
        else:remove(workspace)
