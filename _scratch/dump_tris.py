"""只读：把 prefab 对应 GLB 的三角面逐条打印（或按顶点去重后打印顶点表）。

用法：
  python _scratch/dump_tris.py <prefab 相对路径> [verts|tris|quads] [--in-band=2.2]

  verts  : 按精度去重后打印顶点表（默认）
  tris   : 打印每个三角面（含所在件名）
  quads  : 把相邻两个三角面拼成四边形打印（轴对齐的方盒更好读）
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "verts"
    band = None
    for a in sys.argv[2:]:
        if a.startswith("--in-band="):
            band = float(a.split("=")[1])

    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    parts = glbgeom.parse_glb_parts(glb)

    print("GLB %s" % glb.name)
    for label, pv, pt in parts:
        short = label.replace("/ROOT_", "").replace("_组件/", " / ")
        vs = sorted({round(c, 4) for p in pv for c in p})
        print("\n=== %s  verts=%d(去重%d) tris=%d" % (short, len(pv), len(vs), len(pt)))
        if mode == "verts":
            uniq = sorted({tuple(round(c, 4) for c in p) for p in pv})
            for p in uniq:
                print("    (%9.4f, %8.4f, %9.4f)" % p)
        elif mode == "tris":
            for k, (a, b, c) in enumerate(pt):
                ya = (pv[a][1], pv[b][1], pv[c][1])
                if band is not None and min(ya) > band:
                    continue
                print("   t%-4d (%9.4f,%8.4f,%9.4f) (%9.4f,%8.4f,%9.4f) (%9.4f,%8.4f,%9.4f)"
                      % (k, pv[a][0], pv[a][1], pv[a][2],
                         pv[b][0], pv[b][1], pv[b][2], pv[c][0], pv[c][1], pv[c][2]))


if __name__ == "__main__":
    main()
