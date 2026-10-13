#!/usr/bin/env python3
"""远征关卡02「房间场景是否真按白模组装」的逐件对账。

只读，不起 Godot。做法：

  白盒 manifest（几何真源）
      ↓ 每件对象的 world bounds
  26 个 f00_*_static_layout.tscn 里的**实例**
      ↓ 用 L2 的房间中心做反变换，还原到世界坐标
  逐件比对：位置 / 朝向 / 尺寸

对账口径（与 `build_expedition02_room_scenes.py` 的写出逻辑严格对应）：
  · 房间根节点是世界轴对齐、无旋转的 ⇒ 实例世界位置 = 房间中心 + 实例局部原点
    （`Transform3D` 的 basis 只转网格自身，不改变 position）
  · 实例的 `metadata/placement_note` 存的就是白盒对象名 ⇒ 可以一对一配

输出四张表：房间中心一致性 / 实墙 / 门墙 / 地板与封顶。
任何一件位置、朝向或尺寸对不上都计入 FAIL。
"""

from __future__ import annotations

import importlib.util
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL = "expedition_02"


def _load_room_key_map() -> dict:
    """白盒 key ↔ 设计 key 的映射取自**生成器本身**，不在这里另抄一份。"""
    spec = importlib.util.spec_from_file_location(
        "_exp02_scenes", ROOT / "scripts/build_expedition02_room_scenes.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return dict(mod.ROOM_KEY_MAP)


# 白盒 key（balcony / tall_hall / …） → 设计 key（entry / room_01 / …）
WB_TO_DESIGN = _load_room_key_map()
DESIGN_TO_WB = {v: k for k, v in WB_TO_DESIGN.items()}

MANIFEST = (
    ROOT / "art_source/design/whitebox/tower_zones/expedition_02/v001"
    / "data/component_packages/hotel_floor_01/远征关卡02_白模_第1层_长廊与客房/asset_manifest.json"
)
L2 = ROOT / f"data/level_plans/{LEVEL}/floors/floor_00.json"
SCENES = ROOT / f"assets/art/environments/tower_zones/expedition/runtime/room_instances/{LEVEL}"

# 组件在 Godot 坐标下的**局部 AABB**（原点 = 底面中心）。
# 取自各组件 tscn 的 BoxShape3D + position，不由本脚本另行推算。
LOCAL_AABB = {
    "wall_standard_5m_h3":   ((-2.5, 0.0, -0.15), (2.5, 3.0, 0.15)),
    "wall_door_5m_h3":       ((-2.5, 0.0, -0.15), (2.5, 3.0, 0.15)),
    "wall_standard_5m_h12":  ((-2.5, 0.0, -0.15), (2.5, 11.9, 0.15)),
    "wall_door_5m_h12":      ((-2.5, 0.0, -0.15), (2.5, 11.9, 0.15)),
    "wall_collapse_5m_h12":  ((-2.5, 0.0, -0.15), (2.5, 11.9, 0.15)),
    "floor_base_5m":         ((-2.5, 0.0, -2.5), (2.5, 0.26, 2.5)),
    "floor_tile_5m":         ((-2.47, 0.0, -2.47), (2.47, 0.04, 2.47)),
    "ceiling_deck_5m":       ((-2.5, 0.0, -2.5), (2.5, 0.26, 2.5)),
}

TOL = 1e-4
FAILS: list[str] = []


def note(msg: str) -> None:
    FAILS.append(msg)


# ---------------------------------------------------------------- 解析

def parse_scene(path: Path):
    """返回 [(instance_name, slug, basis(9元组), origin(3元组), note)]。"""
    text = path.read_text(encoding="utf-8")
    out = []
    for block in text.split("[node name=")[1:]:
        if "instance=ExtResource(" not in block:
            continue
        name_m = re.match(r'"([^"]*)"', block)
        slug_m = re.search(r'instance=ExtResource\("\d+_([a-z0-9_]+)"\)', block)
        tr_m = re.search(r"^transform = Transform3D\(([^)]*)\)", block, re.M)
        if not (name_m and slug_m and tr_m):
            continue
        nums = [float(v) for v in tr_m.group(1).split(",")]
        if len(nums) != 12:
            raise SystemExit("%s 的 Transform3D 不是 12 个数：%s" % (path.name, tr_m.group(1)))
        note_m = re.search(r'^metadata/placement_note = "(.*)"$', block, re.M)
        out.append((
            name_m.group(1), slug_m.group(1),
            tuple(nums[:9]), tuple(nums[9:12]),
            note_m.group(1) if note_m else "",
        ))
    return out


def world_aabb(slug: str, basis, origin):
    lo, hi = LOCAL_AABB[slug]
    xa, ya, za = basis[0:3], basis[3:6], basis[6:9]
    pts = []
    for lx in (lo[0], hi[0]):
        for ly in (lo[1], hi[1]):
            for lz in (lo[2], hi[2]):
                pts.append(tuple(
                    xa[i] * lx + ya[i] * ly + za[i] * lz + origin[i] for i in range(3)
                ))
    return (
        tuple(min(p[i] for p in pts) for i in range(3)),
        tuple(max(p[i] for p in pts) for i in range(3)),
    )


def close(a: float, b: float, tol: float = TOL) -> bool:
    return abs(a - b) <= tol


def aabb_equal(a, b, tol: float = TOL) -> bool:
    return all(close(a[0][i], b[0][i], tol) and close(a[1][i], b[1][i], tol) for i in range(3))


# ---------------------------------------------------------------- 主流程

def main() -> int:
    wb = json.loads(MANIFEST.read_text(encoding="utf-8"))
    l2 = json.loads(L2.read_text(encoding="utf-8"))

    wb_rooms = {r["key"]: r for r in wb["rooms"]}
    l2_by_key = {str(r["key"]): r for r in l2["rooms"]}

    # ---- ① 房间中心：L2 vs 白盒 ----
    print("=" * 78)
    print("① 房间中心与尺寸：L2（运行时真源） vs 白盒 manifest")
    print("=" * 78)
    if not wb_rooms:
        note("白盒 manifest 里没有 rooms")
    ok_rooms = 0
    for key, l2r in sorted(l2_by_key.items()):
        wb_key = DESIGN_TO_WB.get(key)
        if wb_key is None or wb_key not in wb_rooms:
            note("L2 的 %s 在白盒里找不到对应房（映射 %s）" % (key, wb_key))
            continue
        wr = wb_rooms[wb_key]
        lc, ls = l2r["center_m"], l2r["size_m"]
        wc, ws = wr["center_m"], wr["size_m"]
        same = all(close(lc[i], wc[i]) for i in range(2)) and all(close(ls[i], ws[i]) for i in range(2))
        if not same:
            note("房间 %s(%s) 中心/尺寸不一致：L2 %s/%s vs 白盒 %s/%s"
                 % (key, wb_key, lc, ls, wc, ws))
        else:
            ok_rooms += 1
    print("  %d/%d 间中心与尺寸逐值一致" % (ok_rooms, len(l2_by_key)))
    leftover = set(wb_rooms) - set(WB_TO_DESIGN)
    if leftover:
        note("白盒有 %d 间没被映射到设计 key：%s" % (len(leftover), sorted(leftover)))
    else:
        print("  白盒 %d 间全部映射到设计 key ✓" % len(wb_rooms))
    unmapped_design = set(l2_by_key) - set(DESIGN_TO_WB)
    if unmapped_design:
        note("L2 有 %d 间没映射到白盒房：%s" % (len(unmapped_design), sorted(unmapped_design)))

    # ---- ② 解析全部房间场景 ----
    print()
    print("=" * 78)
    print("② 逐件对账：白盒对象 → 房间场景实例")
    print("=" * 78)
    scene_files = sorted(SCENES.glob("f00_*_static_layout.tscn"))
    print("  房间场景 %d 个" % len(scene_files))

    # room runtime id <-> design key 映射（用 tscn 里的 metadata）
    by_note: dict[str, list] = defaultdict(list)
    slug_count = Counter()
    total_instances = 0
    for path in scene_files:
        text = path.read_text(encoding="utf-8")
        rid = re.search(r'^metadata/room_id = "(.*)"$', text, re.M)
        key = re.search(r'^metadata/room_key = "(.*)"$', text, re.M)
        if not (rid and key):
            note("%s 缺 room_id / room_key metadata" % path.name)
            continue
        rid, key = rid.group(1), key.group(1)
        if key not in l2_by_key:
            note("%s 的 room_key=%s 在 L2 里不存在" % (path.name, key))
            continue
        cx, cy = l2_by_key[key]["center_m"][0], l2_by_key[key]["center_m"][1]
        for inst in parse_scene(path):
            name, slug, basis, origin, plnote = inst
            slug_count[slug] += 1
            total_instances += 1
            world = world_aabb(slug, basis, origin)
            # 房间根节点无旋转 ⇒ 实例世界 AABB = 房间中心平移 + 局部 AABB
            shifted = (
                (world[0][0] + cx, world[0][1], world[0][2] + cy),
                (world[1][0] + cx, world[1][1], world[1][2] + cy),
            )
            by_note[plnote].append(dict(
                room=rid, key=key, name=name, slug=slug,
                aabb=shifted, origin=origin, path=path.name,
            ))
    print("  实例合计 %d" % total_instances)
    print("  按组件：%s" % dict(sorted(slug_count.items())))

    # ---- ③ 实墙 ----
    wb_walls = [o for o in wb["components"] if o["kind"] == "wall"]
    print()
    print("③ 实墙 %d 件" % len(wb_walls))
    wall_ok = wall_bad = 0
    for obj in wb_walls:
        lo, hi = obj["bounds_world_m"]["min"], obj["bounds_world_m"]["max"]
        want = ((lo[0], lo[2], lo[1]), (hi[0], hi[2], hi[1]))   # 白盒(x,y,z) → Godot(x,z,y)
        hits = by_note.get(obj["name"], [])
        if len(hits) != 1:
            note("实墙 %s 的实例数 = %d（应为 1）" % (obj["name"], len(hits)))
            wall_bad += 1
            continue
        if aabb_equal(hits[0]["aabb"], want):
            wall_ok += 1
        else:
            note("实墙 %s 位置/朝向不符\n      白盒 %s\n      场景 %s（%s）"
                 % (obj["name"], want, hits[0]["aabb"], hits[0]["path"]))
            wall_bad += 1
    print("  位置+朝向+尺寸全部一致：%d ／ 不符：%d" % (wall_ok, wall_bad))

    # ---- ④ 门墙 ----
    print()
    n_door = sum(1 for d in wb["doors"] if str(d["kind"]) != "open")
    n_open = len(wb["doors"]) - n_door
    print("④ 门 %d 处（有门墙 %d + 通洞 %d）" % (len(wb["doors"]), n_door, n_open))
    print("   有门墙：白盒一个门槽 = 左右门垛 + 门楣 3 件 ⇒ 场景 1 个实例")
    print("   通洞：白盒里**本来就没有墙件**（纯开口）⇒ 反向验「槽位确实是空的」")
    door_ok = door_bad = open_ok = open_bad = 0
    # 所有墙/门实例的世界 AABB，用于通洞的「空槽」反证
    all_wall_insts = [
        h for n, hits in by_note.items()
        for h in hits if h["slug"].startswith("wall_")
    ]
    for d in wb["doors"]:
        key = str(d["door_key"])
        kind = str(d["kind"])
        line = float(d["line_coord_m"])
        at = float(d["opening_center_m"])
        axis = str(d["axis"])
        # 槽位 = 白盒建墙时的 5m 模块（module_start = floor(center/5)*5）
        mstart = math.floor(round(at / 5.0, 6)) * 5.0

        if kind == "open":
            # ⚠️ 判据是「**通道正中**是否被挡」，不是「整槽是否与墙 AABB 相交」。
            # 后者会把转角处正好与开口边缘相接的垂直墙判成堵路 —— 那种相接是
            # 正确几何（墙在开口角上收头），不是阻挡。半宽取 0.6m：足够宽到
            # 任何真横穿槽位的墙都会命中，又窄到只擦边的转角墙不会命中。
            if axis == "v":
                ocx, ocz = line, at
            else:
                ocx, ocz = at, line
            px0, px1 = ocx - 0.6, ocx + 0.6
            pz0, pz1 = ocz - 0.6, ocz + 0.6
            blocked = []
            for h in all_wall_insts:
                (ax0, ay0, az0), (ax1, ay1, az1) = h["aabb"]
                if ay1 <= 0.05:          # 纯地板件不参与
                    continue
                if ax0 < px1 and ax1 > px0 and az0 < pz1 and az1 > pz0:
                    blocked.append("%s(%s)" % (h["slug"], h["path"]))
            if blocked:
                note("通洞 %s 的通道正中(%g,%g)被墙件占用：%s" % (key, ocx, ocz, blocked[:3]))
                open_bad += 1
            else:
                open_ok += 1
            continue

        slot_objs = [
            o for o in wb["components"]
            if o["kind"] == "door_wall" and o.get("door_key") == key
        ]
        if not slot_objs:
            note("门 %s 在白盒里找不到 door_wall 对象" % key)
            door_bad += 1
            continue
        hz = max(o["bounds_world_m"]["max"][2] for o in slot_objs)
        if axis == "v":
            want = ((line - 0.15, 0.0, mstart), (line + 0.15, hz, mstart + 5.0))
        else:
            want = ((mstart, 0.0, line - 0.15), (mstart + 5.0, hz, line + 0.15))
        hits = by_note.get("门墙 %s" % str(d.get("name_zh", "")), [])
        if len(hits) != 1:
            note("门 %s 的实例数 = %d（应为 1）" % (key, len(hits)))
            door_bad += 1
            continue
        got = hits[0]["aabb"]
        # 组件自身占满整槽（5 × h × 0.3）；collapse 件的可视只有门楣，故按槽比
        if aabb_equal(got, want, 1e-3):
            door_ok += 1
        else:
            note("门 %s 槽位不符\n      白盒 %s\n      场景 %s（%s）" % (key, want, got, hits[0]["path"]))
            door_bad += 1
    print("   有门墙 槽位一致：%d ／ 不符：%d" % (door_ok, door_bad))
    print("   通洞   槽位确实为空：%d ／ 被堵：%d" % (open_ok, open_bad))

    # ---- ⑤ 地板 / 地砖 / 封顶 ----
    print()
    print("⑤ 地板 / 地砖 / 封顶：按房间矩形铺满 5m 格")
    print("=" * 78)
    grid_bad = 0
    covered = Counter()
    for path in scene_files:
        text = path.read_text(encoding="utf-8")
        rid = re.search(r'^metadata/room_id = "(.*)"$', text, re.M).group(1)
        key = re.search(r'^metadata/room_key = "(.*)"$', text, re.M).group(1)
        cx, cy = l2_by_key[key]["center_m"][0], l2_by_key[key]["center_m"][1]
        w, h = l2_by_key[key]["size_m"][0], l2_by_key[key]["size_m"][1]
        nx, ny = int(round(w / 5.0)), int(round(h / 5.0))
        if not (close(nx * 5.0, w) and close(ny * 5.0, h)):
            note("房间 %s 尺寸 %gx%g 不是 5 的整数倍" % (key, w, h))
            grid_bad += 1
        insts = parse_scene(path)
        want_centers = set()
        for ix in range(nx):
            for iy in range(ny):
                want_centers.add((
                    round(cx + (-w / 2 + 5.0 * (ix + 0.5)), 4),
                    round(cy + (-h / 2 + 5.0 * (iy + 0.5)), 4),
                ))
        for slug in ("floor_base_5m", "floor_tile_5m"):
            got = {
                (round(cx + i[3][0], 4), round(cy + i[3][2], 4))
                for i in insts if i[1] == slug
            }
            if got != want_centers:
                note("%s 的 %s 格位不符（缺 %d / 多 %d）"
                     % (key, slug, len(want_centers - got), len(got - want_centers)))
                grid_bad += 1
            covered[slug] += len(got)
        ceil_meta = re.search(r"^metadata/ceiling_bottom_y_m = (\S+)$", text, re.M).group(1)
        ceil_insts = [i for i in insts if i[1] == "ceiling_deck_5m"]
        if ceil_meta == "null":
            if ceil_insts:
                note("%s 声明不封顶，却有 %d 块顶盖" % (key, len(ceil_insts)))
                grid_bad += 1
        else:
            if not ceil_insts:
                note("%s 应有封顶却没有顶盖" % key)
                grid_bad += 1
            else:
                ys = {round(i[3][1], 4) for i in ceil_insts}
                if ys != {4.0}:
                    note("%s 顶盖高度 = %s，应为 4.0" % (key, sorted(ys)))
                    grid_bad += 1
                got = {(round(cx + i[3][0], 4), round(cy + i[3][2], 4)) for i in ceil_insts}
                if got != want_centers:
                    note("%s 的封顶格位不符" % key)
                    grid_bad += 1
        covered["ceiling_deck_5m"] += len(ceil_insts)
    print("  格位违规 %d 处" % grid_bad)
    print("  铺放件数：%s" % dict(sorted(covered.items())))

    # ---- 汇总 ----
    print()
    print("=" * 78)
    if FAILS:
        print("EXPEDITION02_ASSEMBLY_MATCH_FAILED count=%d" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        print("=" * 78)
        return 1
    print("EXPEDITION02_ASSEMBLY_MATCH_OK")
    print("  房间场景 %d 个 / 实例 %d 件" % (len(scene_files), total_instances))
    print("  实墙 %d / 门墙 %d / 地板地砖封顶 %d 件 —— 全部逐件对上白盒"
          % (len(wb_walls), len(wb["doors"]), sum(covered.values())))
    print("=" * 78)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
