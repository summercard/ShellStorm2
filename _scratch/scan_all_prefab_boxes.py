"""只读全量扫描：所有 `*_root_top3d.tscn`（policy = safe_box_proxy / structural_box_proxy）
用 `verify_box_segments.verify` 的双向判据过一遍，列出不合格件与不合格维度。

口径见 verify_box_segments.py：只看触及玩家高度带的几何；覆盖判据给半格容差。

用法：python _scratch/scan_all_prefab_boxes.py [--band-top=2.2] [--empty-tol=0.30] [--cell=0.05]
"""
import contextlib
import io
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_box_segments as V  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
POLICIES = {"safe_box_proxy", "structural_box_proxy"}


def main():
    band, tol, cell = 2.2, 0.30, 0.05
    for a in sys.argv[1:]:
        if a.startswith("--band-top="):
            band = float(a.split("=")[1])
        elif a.startswith("--empty-tol="):
            tol = float(a.split("=")[1])
        elif a.startswith("--cell="):
            cell = float(a.split("=")[1])
    V.CELL = cell

    prefabs = sorted(ROOT.glob("assets/art/environments/**/*_root_top3d.tscn"))
    picked = []
    for p in prefabs:
        text = p.read_text(encoding="utf-8", errors="replace")
        m = re.search(r'metadata/collision_policy = "([^"]+)"', text)
        if m and m.group(1) in POLICIES:
            picked.append(p)
    print("扫描 %d 个 prefab，命中 policy 白名单 %d 个；CELL=%.2f band=%.2f tol=%.2f\n"
          % (len(prefabs), len(picked), cell, band, tol))

    bad = []
    t0 = time.time()
    for i, p in enumerate(picked, 1):
        rel = p.relative_to(ROOT).as_posix()
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                ok = V.verify(rel, tol, band, quiet=True)
        except Exception as e:  # noqa: BLE001
            ok = False
            buf.write("EXC %s\n" % e)
        if not ok:
            bad.append((rel, buf.getvalue()))
        if i % 25 == 0:
            print("  ... %d/%d  %.0fs" % (i, len(picked), time.time() - t0))
    print("\n不合格 %d / %d 个（用时 %.0fs）\n" % (len(bad), len(picked), time.time() - t0))
    for rel, _ in bad:
        print("  %s" % rel)
    print()
    for rel, detail in bad:
        print("=" * 100)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            V.verify(rel, tol, band, quiet=False)
        print(buf.getvalue())


if __name__ == "__main__":
    main()
