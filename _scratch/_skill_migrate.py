import io
import os
from pathlib import Path

S = Path(os.path.expanduser("~/.workbuddy/skills/godot-collision-proxy-segmentation/scripts"))

ROOT_OLD = "ROOT = Path(__file__).resolve().parents[1]"
ROOT_NEW = '''def _find_root():
    env = os.environ.get("SS2_ROOT")
    if env:
        return Path(env).resolve()
    p = Path.cwd().resolve()
    for cand in [p, *p.parents]:
        if (cand / "project.godot").exists():
            return cand
    return p


ROOT = _find_root()'''

targets = ["band_blocks.py", "dump_tris.py", "scan_box_proxy_vs_geometry.py", "verify_box_segments.py"]

for name in targets:
    p = S / name
    b = p.read_bytes()
    txt = b.decode("utf-8")
    if ROOT_OLD not in txt:
        print("!! ROOT line not found in", name)
        continue
    txt = txt.replace(ROOT_OLD, ROOT_NEW)
    if "\nimport os\n" not in txt.replace("\r\n", "\n") and "import os" not in txt:
        # add import os right before the first "import re" / "import json" / "import sys"
        lines = txt.split("\r\n")
        for i, ln in enumerate(lines):
            if ln.startswith("import "):
                lines.insert(i, "import os")
                break
        txt = "\r\n".join(lines)
    # normalize to CRLF
    txt = txt.replace("\r\n", "\n").replace("\n", "\r\n")
    with open(p, "wb") as fh:
        fh.write(txt.encode("utf-8"))
    print("patched", name)
