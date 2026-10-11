"""Paths for disposable development artifacts outside the Godot project."""
import os
from pathlib import Path

PROJECT_ROOT=Path(__file__).resolve().parents[1]
def work_root():
    root=Path(os.environ.get('SHELLSTORM_WORK_ROOT',str(PROJECT_ROOT.parent/'ShellStorm2-work'))).resolve()
    if root==PROJECT_ROOT or root.is_relative_to(PROJECT_ROOT):
        raise ValueError('SHELLSTORM_WORK_ROOT must be outside the Godot project')
    return root

def work_path(relative):
    root=work_root();target=(root/relative).resolve()
    if not target.is_relative_to(root):raise ValueError('Work path escapes its root')
    target.parent.mkdir(parents=True,exist_ok=True)
    return target
