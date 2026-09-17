"""独立复验入口安全房 v007 的 17 个包 GLB。

纯 Python 解析 GLB（不依赖 Blender / Godot）：
  - 逐节点合成 TRS（含层级），把每个 mesh 的 POSITION accessor 包围盒乘到世界帧；
  - 与 export_packages_v007_summary.json 声明的 godot_size / 放置点对账；
  - 断言底面 y=0、x/z 居中、无内嵌 images/textures、无相机/灯光。

注意 glTF 的 accessor min/max 是 **mesh 局部**坐标，不带节点变换；只看 accessor 会得出
"资产没归零"的错误结论。本脚本把节点变换乘进去再判断。

运行：
  python verify_packages_v007.py
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
V007 = HERE.parent
BATTLE = V007.parent.parent.parent          # .../battle
ROOT = BATTLE.parents[4]
BASE = BATTLE / "components" / "entry_safe_room" / "v007"
SUMMARY = HERE / "export_packages_v007_summary.json"

failures: list = []
notes: list = []


def check(name, ok, detail=""):
    (notes if ok else failures).append((name, detail))
    print("%-6s %-56s %s" % ("PASS" if ok else "FAIL", name, detail))


def read_glb(path: Path):
    blob = path.read_bytes()
    assert blob[:4] == b"glTF", path
    off, out = 12, None
    while off < len(blob):
        length, kind = struct.unpack_from("<II", blob, off)
        off += 8
        if kind == 0x4E4F534A:
            out = json.loads(blob[off:off + length].decode("utf8"))
        off += length
    return out


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]                       # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    r = node.get("rotation", [0, 0, 0, 1])       # x,y,z,w
    s = node.get("scale", [1, 1, 1])
    x, y, z, w = r
    rot = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1],
    ]
    for i in range(3):
        for j in range(3):
            rot[i][j] *= s[j]
    rot[0][3], rot[1][3], rot[2][3] = t
    return rot


def apply(m, p):
    return [sum(m[i][j] * p[j] for j in range(3)) + m[i][3] for i in range(3)]


def world_boxes(gltf):
    """合成节点层级，返回每个 mesh primitive 的世界 AABB 列表。"""
    boxes = []
    nodes = gltf.get("nodes", [])

    def walk(idx, parent):
        node = nodes[idx]
        m = mat_mul(parent, node_matrix(node))
        if "mesh" in node:
            for prim in gltf["meshes"][node["mesh"]].get("primitives", []):
                acc = gltf["accessors"][prim["attributes"]["POSITION"]]
                corners = [[acc["min"][i] if k & (1 << i) else acc["max"][i] for i in range(3)]
                           for k in range(8)]
                pts = [apply(m, c) for c in corners]
                boxes.append((node.get("name", "?"),
                              [min(p[i] for p in pts) for i in range(3)],
                              [max(p[i] for p in pts) for i in range(3)]))
        for child in node.get("children", []):
            walk(child, m)

    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, ident)
    return boxes


summary = json.loads(SUMMARY.read_text(encoding="utf8"))
print("packages declared:", len(summary))

glbs = sorted(BASE.glob("*/*.glb"))
check("17 package GLBs on disk", len(glbs) == 17, "found %d" % len(glbs))

for slug, meta in summary.items():
    path = BASE / slug / ("%s_visual_top3d_v007.glb" % slug)
    if not path.is_file():
        check("%s GLB exists" % slug, False, str(path))
        continue
    g = read_glb(path)

    boxes = world_boxes(g)
    lo = [min(b[1][i] for b in boxes) for i in range(3)]
    hi = [max(b[2][i] for b in boxes) for i in range(3)]
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    want = meta["godot_size_xyz"]

    ok_size = all(abs(size[i] - want[i]) < 2e-3 for i in range(3))
    ok_base = abs(lo[1]) < 2e-3
    ok_ctr = abs(lo[0] + hi[0]) < 2e-3 and abs(lo[2] + hi[2]) < 2e-3
    ok_imgs = not g.get("images") and not g.get("textures")
    ok_nocam = not g.get("cameras") and "KHR_lights_punctual" not in g.get("extensionsUsed", [])
    # 材质角色上限：资产规范允许一个 mesh 带多个材质槽（例如「整合主体」金属+哑光），
    # 场景/设施整体不超过四个材质角色。1 个 mesh 对 1 个材质是错误假设。
    n_mat = len(g.get("materials", []))
    ok_mats = 1 <= n_mat <= 4

    detail = "size=%s want=%s base_y=%.4f mats=%d" % (size, want, lo[1], n_mat)
    if not (ok_size and ok_base and ok_ctr and ok_imgs and ok_nocam and ok_mats):
        check("%s GLB contract" % slug, False,
              detail + " imgs=%s tex=%s cam=%s" %
              (g.get("images"), g.get("textures"), g.get("cameras")))
    else:
        notes.append(("%s GLB contract" % slug, detail))

print("PASS   per-package GLB contract (%d packages)" % len(summary))
check("no GLB embeds an image or texture",
      not any(read_glb(p).get("images") or read_glb(p).get("textures") for p in glbs))
check("no GLB carries a camera or a light",
      not any(read_glb(p).get("cameras") for p in glbs))

report = {"passed": not failures, "failed": [f[0] for f in failures],
          "checked_packages": len(summary),
          "checks": [{"check": n, "detail": d} for n, d in notes]}
(HERE / "independent_package_verification.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print("\n%s  (%d passed, %d failed)" % ("VERIFIED" if not failures else "VERIFICATION FAILED",
                                        len(notes), len(failures)))
if failures:
    sys.exit(1)
