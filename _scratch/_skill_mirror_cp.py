import os
import shutil
from pathlib import Path

SKILL = "godot-collision-proxy-segmentation"
A = Path(os.path.expanduser("~/.workbuddy/skills")) / SKILL

COPIES = {
    "B_drafts": Path(r"I:\工作项目\shellstrom2\ShellStorm2\skills_drafts") / SKILL,
    "C_project_codex": Path(r"I:\工作项目\shellstrom2\ShellStorm2\.codex\skills") / SKILL,
    "D_user_codex": Path(os.path.expanduser("~/.codex/skills")) / SKILL,
}

for name, dst in COPIES.items():
    if not dst.parent.is_dir():
        print("!! parent missing, skip:", name, dst.parent)
        continue
    dst.mkdir(parents=True, exist_ok=True)
    for src in A.rglob("*"):
        if src.is_dir():
            continue
        rel = src.relative_to(A)
        tgt = dst / rel
        tgt.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, tgt)
    n = sum(1 for _ in dst.rglob("*") if _.is_file())
    print("copied %d files -> %s" % (n, name))
