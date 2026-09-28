"""只读扫描：把「prefab 里实际声明的碰撞盒」与「GLB 几何的 XZ 投影」双向比对（**只看玩家高度带**）。

只处理「碰撞盒是几何代孕盒」的语义（`safe_box_proxy` / `structural_box_proxy`），
其它 policy（optimized_output_bounds_box 之类）是各自功能的占位盒，不在此列。

判据（几何一律先按玩家高度带 BAND_TOP 过滤）：
  A 空腔（空阻挡）＝盒并集内、离几何投影 > EMPTY_TOL 且成片的格 ⇒ 玩家在空地上被无故阻挡。
  B 漏覆盖（穿模）＝几何投影内、不在任何盒内的格 ⇒ 实体可以穿过去。

三条口径（都踩过）：
  * **只算玩家高度带**（默认 BAND_TOP=2.2 m）：只在 2.9 m 高处横跨整面墙的自发光灯带不需要
    碰撞；把它算成「必须覆盖」会永远 FAIL。不过滤时「几何在两端、中间真空」的件也会因为
    高处横梁把空腔填掉而漏报。
  * 🔴 **本扫描用的是 GLB 的局部 y**。挂在 11 m 高处的「墙顶管线收口」局部 y 只有 0..0.7，
    按局部 y 判定会被误报成「玩家可达」。故对每个件额外解析它在
    `assets/**/room_static_layout.tscn` 里的摆放原点 y（yaw-only 旋转下世界 y = 原点 y + 局部 y），
    给出世界 y 区间；整段都高于 BAND_TOP 时标注「高处放置，无害」。
  * 🔴 **`slot_role == "solid_wall"` 的墙面件不走「空腔」判据**。墙的代孕盒本就是要让墙不可穿
    越，盒 ⊃ 几何（超覆盖）是预期行为：墙底台阶凹口、装饰墙皮中央开口背后都有实体结构墙
    （`base_wall_*`）兜底，超覆盖挡不住任何通行空间。这类件只保留「漏覆盖（穿模）」为真 bug，
    外加一个大空腔兜底阈值 SOLID_WALL_CAVITY_LIMIT 供人工复核。真正会被空腔伤到的只有
    家具/设施/凸出物（`slot_role` 非 solid_wall）—— 那才是「L 型组件空阻挡」那一类。

用法：
  python _scratch/scan_box_proxy_vs_geometry.py [slug...] [--all-policy] [--all-band] [--band-top=2.2]
"""
import os
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

def _find_root():
    env = os.environ.get("SS2_ROOT")
    if env:
        return Path(env).resolve()
    p = Path.cwd().resolve()
    for cand in [p, *p.parents]:
        if (cand / "project.godot").exists():
            return cand
    return p


ROOT = _find_root()
CELL = 0.05
EMPTY_TOL = 0.30
R = int(round(EMPTY_TOL / CELL))
MIN_BLOB_M2 = 0.20
SOLID_WALL_CAVITY_LIMIT = 6.0   # solid_wall 件的大空腔兜底阈值（超过才提示人工复核）
POLICY_WHITELIST = {"safe_box_proxy", "structural_box_proxy"}
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"
BAND_TOP = 2.2


def boxes_from_tscn(text):
    sizes = {
        m.group(1): [float(v) for v in re.findall(NUM, m.group(2))]
        for m in re.finditer(
            r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\s*\r?\nsize = Vector3\(([^)]*)\)', text)
    }
    out = []
    for m in re.finditer(
        r'\[node name="([^"]+)" type="CollisionShape3D"[^\]]*\]\s*\r?\n((?:[^\[]*\r?\n)*?)(?=\[|$)', text):
        name, body = m.group(1), m.group(2)
        pm = re.search(r"position = Vector3\(([^)]*)\)", body)
        sm = re.search(r'shape = SubResource\("([^"]+)"\)', body)
        if not sm or sm.group(1) not in sizes:
            continue
        pos = [float(v) for v in re.findall(NUM, pm.group(1))] if pm else [0.0, 0.0, 0.0]
        size = sizes[sm.group(1)]
        if len(pos) < 3 or len(size) < 3:
            continue
        out.append((name, [pos[i] - size[i] / 2 for i in range(3)], [pos[i] + size[i] / 2 for i in range(3)]))
    return out


def _node_blocks(text):
    out, cur = [], None
    for line in text.splitlines():
        if line.startswith("[node "):
            if cur is not None:
                out.append(cur)
            cur = []
        elif cur is not None:
            cur.append(line)
    if cur is not None:
        out.append(cur)
    return out


def placements_origin_y():
    """slug -> [摆放原点 y, ...]（同名件在多个房间里可能各有一份摆位）。"""
    out = {}
    for p in ROOT.glob("assets/**/room_static_layout.tscn"):
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        for body in _node_blocks(text):
            txt = "\n".join(body)
            m = re.search(r'metadata/component_slug = "([^"]+)"', txt)
            if not m:
                continue
            t = re.search(r"transform = Transform3D\(([^)]*)\)", txt)
            nums = [float(v) for v in re.findall(NUM, t.group(1))] if t else []
            out.setdefault(m.group(1), []).append(nums[10] if len(nums) >= 12 else 0.0)
    return out


def scan(tscn: Path, all_policy: bool, band_top, placements):
    text = tscn.read_text(encoding="utf-8")
    policy = re.search(r'metadata/collision_policy = "([^"]*)"', text)
    policy = policy.group(1) if policy else ""
    if not all_policy and policy not in POLICY_WHITELIST:
        return None
    role = re.search(r'metadata/slot_role = "([^"]*)"', text)
    role = role.group(1) if role else ""
    boxes = boxes_from_tscn(text)
    if not boxes:
        return None
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    if not m:
        return None
    glb = ROOT / m.group(1).replace("res://", "")
    if not glb.exists():
        return {"tscn": str(tscn), "error": "GLB 缺失"}
    verts, tris = glbgeom.parse_glb(glb)
    if not verts or not tris:
        return {"tscn": str(tscn), "error": "无三角面"}

    if band_top is None:
        rel_ids = list(range(len(tris)))
    else:
        rel_ids = [t for t in range(len(tris))
                   if min(verts[tris[t][k]][1] for k in range(3)) <= band_top]
    if not rel_ids:
        rel_ids = list(range(len(tris)))

    gx = [verts[i][0] for t in rel_ids for i in tris[t]]
    gz = [verts[i][2] for t in rel_ids for i in tris[t]]
    gy = [verts[i][1] for t in rel_ids for i in tris[t]]
    bx0 = min([b[1][0] for b in boxes] + [min(gx)])
    bx1 = max([b[2][0] for b in boxes] + [max(gx)])
    bz0 = min([b[1][2] for b in boxes] + [min(gz)])
    bz1 = max([b[2][2] for b in boxes] + [max(gz)])
    nx = max(1, int((bx1 - bx0) / CELL) + 1)
    nz = max(1, int((bz1 - bz0) / CELL) + 1)
    if nx * nz > 12_000_000:
        return {"tscn": str(tscn), "error": "栅格过大 %dx%d" % (nx, nz)}

    geom = glbgeom.rasterize_xz_band(verts, tris, bx0, bz0, nx, nz, CELL, ids=rel_ids)
    boxm = bytearray(nx * nz)
    for _, lo, hi in boxes:
        i0, i1 = max(0, int((lo[0] - bx0) / CELL)), min(nx - 1, int((hi[0] - bx0) / CELL))
        j0, j1 = max(0, int((lo[2] - bz0) / CELL)), min(nz - 1, int((hi[2] - bz0) / CELL))
        for j in range(j0, j1 + 1):
            row = j * nx
            for i in range(i0, i1 + 1):
                boxm[row + i] = 1

    geom_grown = glbgeom.dilate(geom, nx, nz, R)
    box_grown = glbgeom.dilate(boxm, nx, nz, R)
    cavity = bytearray(boxm[k] and not geom_grown[k] for k in range(nx * nz))
    miss = bytearray(geom[k] and not box_grown[k] for k in range(nx * nz))
    min_cells = max(1, int(MIN_BLOB_M2 / (CELL * CELL)))

    cav_total, cav_big, _ = glbgeom.blob_stat(cavity, nx, nz, min_cells)
    miss_total, miss_big, _ = glbgeom.blob_stat(miss, nx, nz, min_cells)

    aabb_area = (max(gx) - min(gx)) * (max(gz) - min(gz))
    ylo, yhi = min(gy), max(gy)
    oys = placements.get(tscn.parent.name)
    if oys:
        wy = sorted((o + ylo, o + yhi) for o in oys)
        y_world = [round(min(a for a, _ in wy), 3), round(max(b for _, b in wy), 3)]
    else:
        y_world = None

    return {
        "rel": tscn.relative_to(ROOT).as_posix(),
        "slug": tscn.parent.name,
        "room_type": tscn.parent.parent.name,
        "policy": policy,
        "slot_role": role,
        "shape_nodes": len(boxes),
        "box_area": sum((hi[0] - lo[0]) * (hi[2] - lo[2]) for _, lo, hi in boxes),
        "geom_area": sum(geom) * CELL * CELL,
        "aabb_area": aabb_area,
        "cavity_area": cav_total * CELL * CELL,
        "cavity_biggest": cav_big * CELL * CELL,
        "miss_area": miss_total * CELL * CELL,
        "miss_biggest": miss_big * CELL * CELL,
        "y_local": [round(ylo, 3), round(yhi, 3)],
        "y_world": y_world,
        "tris": len(tris),
        "tris_in_band": len(rel_ids),
    }


def _is_high(r, band_top):
    return band_top is not None and r["y_world"] is not None and r["y_world"][0] > band_top


def _needs_action(r, band_top):
    """真正需要人工分段的判据（排除墙面件与高处放置件）。"""
    if r["miss_biggest"] > MIN_BLOB_M2:
        return True                       # 穿模恒为真 bug
    if _is_high(r, band_top):
        return False                      # 整段高于玩家带，够不到
    if r["slot_role"] == "solid_wall":
        return r["cavity_biggest"] > SOLID_WALL_CAVITY_LIMIT
    return r["cavity_biggest"] > MIN_BLOB_M2


def _tag_of(r, band_top):
    if r["miss_biggest"] > MIN_BLOB_M2:
        return "★ 需处理（穿模）"
    if _is_high(r, band_top):
        return "高处放置，无害"
    if r["slot_role"] == "solid_wall":
        return "墙面件，超覆盖无害"
    if r["cavity_biggest"] > MIN_BLOB_M2:
        return "★ 需处理"
    return "OK"


def main():
    global BAND_TOP
    args = sys.argv[1:]
    all_policy = "--all-policy" in args
    all_band = "--all-band" in args
    for a in args:
        if a.startswith("--band-top="):
            BAND_TOP = float(a.split("=")[1])
    only = [a for a in args if not a.startswith("--")]
    band_top = None if all_band else BAND_TOP

    targets = sorted((ROOT / "assets").rglob("*_root_top3d.tscn"))
    if only:
        s = set(only)
        targets = [t for t in targets if t.parent.name in s]

    placements = placements_origin_y()

    rows, errors = [], []
    for n, tscn in enumerate(targets, 1):
        try:
            r = scan(tscn, all_policy, band_top, placements)
        except Exception as exc:  # noqa: BLE001
            errors.append((tscn, repr(exc)))
            continue
        if r is None:
            continue
        if "error" in r:
            errors.append((tscn, r["error"]))
            continue
        rows.append(r)
        if _needs_action(r, band_top):
            print("[%d/%d] %-16s %-32s 盒=%d 空腔=%.2f 漏=%.2f"
                  % (n, len(targets), r["room_type"], r["slug"], r["shape_nodes"],
                     r["cavity_area"], r["miss_area"]), file=sys.stderr)

    rows.sort(key=lambda r: -max(r["cavity_biggest"], r["miss_biggest"]))
    (ROOT / "_scratch" / "box_proxy_scan.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")

    bad = [r for r in rows if r["cavity_biggest"] > MIN_BLOB_M2 or r["miss_biggest"] > MIN_BLOB_M2]
    n_act = sum(1 for r in bad if _needs_action(r, band_top))
    print("扫描 %d 个 prefab，命中 policy 白名单 %d 个；几何候选 %d 个，其中真正需人工分段 %d 个"
          % (len(targets), len(rows), len(bad), n_act))
    print("高度带口径：%s；solid_wall 墙面件只判穿模（空腔兜底 %.1f m^2）\n"
          % ("全部几何（--all-band）" if band_top is None else "y <= %.2f m（局部）" % band_top,
             SOLID_WALL_CAVITY_LIMIT))
    print("%-16s %-28s %4s %9s %9s %9s %9s %-22s %s" %
          ("房型", "slug", "盒数", "几何投影", "最大空腔", "总空腔", "漏覆盖", "世界 y 区间", "判定"))
    print("-" * 132)
    for r in bad:
        yw = r["y_world"]
        tag = _tag_of(r, band_top)
        ytxt = "-" if yw is None else "[%.3f, %.3f]" % (yw[0], yw[1])
        print("%-16s %-28s %4d %9.2f %9.2f %9.2f %9.2f %-22s %s"
              % (r["room_type"], r["slug"], r["shape_nodes"], r["geom_area"],
                 r["cavity_biggest"], r["cavity_area"], r["miss_area"], ytxt, tag))
    print("\n其余 %d 个候选均为墙面件 / 高处放置，超覆盖无害。" % (len(bad) - n_act))
    if errors:
        print("\n跳过/失败 %d 件：" % len(errors))
        for t, e in errors[:25]:
            print("  ! %s : %s" % (t.name, e))


if __name__ == "__main__":
    main()
