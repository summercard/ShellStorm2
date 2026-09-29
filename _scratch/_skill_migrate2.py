import os
from pathlib import Path

S = Path(os.path.expanduser("~/.workbuddy/skills/godot-collision-proxy-segmentation/scripts"))
targets = ["band_blocks.py", "dump_tris.py", "scan_box_proxy_vs_geometry.py", "verify_box_segments.py"]

for name in targets:
    p = S / name
    txt = p.read_bytes().decode("utf-8").replace("\r\n", "\n")
    if "import os\n" in txt:
        print("skip (already has import os):", name)
        continue
    lines = txt.split("\n")
    for i, ln in enumerate(lines):
        if ln.startswith("import ") or ln.startswith("from "):
            lines.insert(i, "import os")
            break
    else:
        print("!! no import line in", name)
        continue
    out = "\n".join(lines).replace("\n", "\r\n")
    with open(p, "wb") as fh:
        fh.write(out.encode("utf-8"))
    print("patched", name)
