"""Native links and link-safe cleanup for isolated verification projects.

Git Bash ln -s may copy entire directories on Windows without symlink permission.
Directory junctions need no elevation. Cleanup never follows their targets.
"""
import argparse
import os
import shutil
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

def remove(path):
    if path.is_junction():os.rmdir(path);return
    if path.is_symlink():path.unlink();return
    if not path.exists():return
    if path.is_dir():
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
