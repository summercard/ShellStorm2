import os
import shutil
from pathlib import Path

SKILL = "godot-collision-proxy-segmentation"
A = Path(os.path.expanduser("~/.workbuddy/skills")) / SKILL
W = Path(r"I:\工作项目\shellstrom2\.workbuddy\skills") / SKILL

W.mkdir(parents=True, exist_ok=True)
for src in A.rglob("*"):
    if src.is_dir():
        continue
    tgt = W / src.relative_to(A)
    tgt.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, tgt)
print("copied ->", W)
print("files:", sum(1 for _ in W.rglob('*') if _.is_file()))
