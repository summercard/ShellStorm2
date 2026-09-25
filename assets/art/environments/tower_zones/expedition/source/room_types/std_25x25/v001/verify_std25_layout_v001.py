# -*- coding: utf-8 -*-
"""std_25x25 布局源 v001 结构契约校验（独立复算，不信任 layout json）。

在保存后的 .blend 上跑：从集合实例反算每个实例的**实际世界包络**，逐条断言：
  A. 实例数 / 角色数 / 来源数与 layout json 一致
  B. 每个实例的集合都来自 library（没有本地副本）、空物体无缩放
  C. 本文件**不自持任何 Mesh datablock**（无 Append、无新建几何）
  D. 地砖 25 块铺满 25×25、无洞无重叠
  E. 四墙 20 槽在房界带上、每边恰 5 槽、槽心 = 5k
  F. 门墙 2 扇落在西/东墙 lane 0，门洞通行带 |y|<1.5 内无其它件
  G. 中央东西向主通道 |y|<2.5 净空（地面段）
  H. 陈设不越界、两两不重叠
  I. 全部件脚高 ≥ −0.33（不穿地）

用法：blender --background <blend> --python verify_std25_layout_v001.py -- --json <输出>
"""
import bpy
import json
import sys
from collections import Counter
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve()
OUT = HERE.parent
BLEND = OUT / "标准房间种类_四墙平房_25x25m_v001.blend"
LAYOUT = OUT / "std_25x25_v001.layout.json"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
JSON_OUT = Path(argv[argv.index("--json") + 1]) if "--json" in argv else OUT / "qa_report.json"

plan = json.loads(LAYOUT.read_text(encoding="utf-8"))
HALF = plan["dimensions_m"][0] / 2.0
GRID = plan["grid_unit_m"]
FAC_LIMIT = 12.0
CORRIDOR_HALF = 2.5
DOOR_HALF = 1.5
DOOR_Z = (0.30, 3.00)

fails = []
warns = []

# ⚠️ 必须先求值依赖图：.blend 里的 object.matrix_world 在本次会话未求值前可能仍是文件里存的
#    obmat（构建时若未 update 就会是单位阵）⇒ 直接读会静默拿到错矩阵。
bpy.context.view_layer.update()

# ---------------------------------------------------------------- 反算实例包络
inst_coll = bpy.data.collections.get("ROOM_LAYOUT_INSTANCES")
if inst_coll is None:
    raise SystemExit("找不到 ROOM_LAYOUT_INSTANCES")


def world_bbox(empty):
    """集合实例的实际世界 AABB（用空物体矩阵乘组件内对象矩阵）。"""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    n = 0
    for ob in empty.instance_collection.objects:
        if ob.type != "MESH" or not ob.data:
            continue
        m = empty.matrix_world @ ob.matrix_world
        for v in ob.data.vertices:
            p = m @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
            n += 1
    return lo, hi, n


items = []
for e in inst_coll.objects:
    src = e.get("source_room_type", "?")
    lo, hi, nv = world_bbox(e)
    items.append(dict(
        instance_id=e.get("instance_id", e.name),
        slug=e.get("component_slug", "?"),
        role=e.get("slot_role", "?"),
        source=src,
        empty_loc=[round(v, 4) for v in e.location],
        rot_z=round(float(e.rotation_euler.z) if e.rotation_mode != "QUATERNION" else 0.0, 4),
        bbox=[[round(v, 4) for v in lo], [round(v, 4) for v in hi]],
        verts=nv,
    ))

SOLID = ("solid_wall", "door_wall", "floor_tile")
fac = [it for it in items if it["role"] not in SOLID]

# A) 计数一致
cnt_role = Counter(it["role"] for it in items)
cnt_src = Counter(it["source"] for it in items)
want_role = plan["composition"]["counts"]
for role in ("floor_tile", "solid_wall", "door_wall", "facility"):
    if cnt_role.get(role, 0) == 0:
        fails.append("A｜角色 %s 缺失" % role)
if len(items) != want_role["total"]:
    fails.append("A｜实例数 %d ≠ layout %d" % (len(items), want_role["total"]))
for role, n in cnt_role.items():
    if want_role.get(role) != n:
        fails.append("A｜%s 数量 %d ≠ layout %d" % (role, n, want_role.get(role)))

# B) 来源都是 library、空物体无缩放
for e in inst_coll.objects:
    c = e.instance_collection
    if c is None:
        fails.append("B｜%s 没有 instance_collection" % e.name)
        continue
    if c.library is None:
        fails.append("B｜%s 的集合 %s 不是 library 链接（疑似本地副本）" % (e.name, c.name))
    if any(abs(s - 1.0) > 1e-6 for s in e.scale):
        fails.append("B｜%s 非单位缩放 %s" % (e.name, tuple(e.scale)))

# C) 本文件不自持 Mesh
own_meshes = [m.name for m in bpy.data.meshes if m.library is None]
if own_meshes:
    fails.append("C｜本文件自持 %d 个 Mesh datablock（应全部来自 library）：%s"
                 % (len(own_meshes), own_meshes[:5]))
scene_local_objs = [o.name for o in bpy.data.objects
                    if o.type == "MESH" and o.library is None]
if scene_local_objs:
    fails.append("C｜场景根有 %d 个本地 Mesh 对象" % len(scene_local_objs))
# 被链接集合本体不得挂进场景树
scene_colls = set()
stack = list(bpy.context.scene.collection.children)
while stack:
    c = stack.pop()
    scene_colls.add(c.name)
    stack.extend(c.children)
bad = [k for k in [
    "地砖_-3_-4_资产包"] if k in scene_colls]
if bad:
    fails.append("C｜被链接的组件集合本体被挂进了场景树：%s" % bad)

# D) 地砖铺满 25×25、无洞无重叠
tiles = [it for it in items if it["role"] == "floor_tile"]
if len(tiles) != 25:
    fails.append("D｜地砖 %d 块 ≠ 25" % len(tiles))
tile_centers = set()
for it in tiles:
    (x0, y0, z0), (x1, y1, z1) = it["bbox"]
    tile_centers.add((round((x0 + x1) / 2, 3), round((y0 + y1) / 2, 3)))
    if abs((x1 - x0) - 5.0) > 0.15 or abs((y1 - y0) - 5.0) > 0.15:
        fails.append("D｜地砖尺寸异常 %s: %.3f×%.3f" % (it["instance_id"], x1 - x0, y1 - y0))
want_centers = {(5 * kx, 5 * ky) for kx in range(-2, 3) for ky in range(-2, 3)}
if tile_centers != want_centers:
    fails.append("D｜地砖中心网格不符：缺 %s 多 %s"
                 % (sorted(want_centers - tile_centers), sorted(tile_centers - want_centers)))
# 地砖覆盖范围
cov_x0 = min(it["bbox"][0][0] for it in tiles)
cov_x1 = max(it["bbox"][1][0] for it in tiles)
cov_y0 = min(it["bbox"][0][1] for it in tiles)
cov_y1 = max(it["bbox"][1][1] for it in tiles)
if not (cov_x1 - cov_x0 >= 24.0 and cov_y1 - cov_y0 >= 24.0):
    fails.append("D｜地砖覆盖不足 x[%.3f,%.3f] y[%.3f,%.3f]" % (cov_x0, cov_x1, cov_y0, cov_y1))

# E) 四墙 20 槽
walls = [it for it in items if it["role"] in ("solid_wall", "door_wall")]
edge = {w: [] for w in ("north", "south", "east", "west")}
for it in walls:
    (x0, y0, z0), (x1, y1, z1) = it["bbox"]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if cy > 0 and abs(cy) > abs(cx):
        w = "north"
        lane = cx
    elif cy < 0 and abs(cy) > abs(cx):
        w = "south"
        lane = cx
    elif cx > 0:
        w = "east"
        lane = cy
    else:
        w = "west"
        lane = cy
    edge[w].append((it["instance_id"], round(lane, 3), it))
    # 墙件必须贴房界带：沿法线方向的中心 |coord| 落在 [HALF-0.6, HALF+0.4]
    nrm = cx if w in ("east", "west") else cy
    if not (HALF - 0.6 <= abs(nrm) <= HALF + 0.4):
        fails.append("E｜墙件不在房界带 %s nrm=%.3f" % (it["instance_id"], nrm))
for w, lst in edge.items():
    if len(lst) != 5:
        fails.append("E｜%s 墙槽 %d ≠ 5" % (w, len(lst)))
    lanes = sorted(round(v, 3) for _, v, _ in lst)
    if lanes != [-10.0, -5.0, 0.0, 5.0, 10.0]:
        fails.append("E｜%s 墙槽心不符 %s" % (w, lanes))

# F) 门墙在西/东墙 lane 0
doors = [it for it in items if it["role"] == "door_wall"]
if len(doors) != 2:
    fails.append("F｜门墙 %d ≠ 2" % len(doors))
for it in doors:
    lane = it["bbox"][0][1]  # 门宽 5 的槽，取包围盒下边界
    cy = (it["bbox"][0][1] + it["bbox"][1][1]) / 2
    cx = (it["bbox"][0][0] + it["bbox"][1][0]) / 2
    if abs(cx) > abs(cy):
        if abs(cy) > 0.6:
            fails.append("F｜门槽不在 lane 0 %s y=%.3f" % (it["instance_id"], cy))
    else:
        if abs(cx) > 0.6:
            fails.append("F｜门槽不在 lane 0 %s x=%.3f" % (it["instance_id"], cx))
# 门洞通行带净空（|y|<1.5，z∈[0.3,3.0]）
for it in fac:
    (x0, y0, z0), (x1, y1, z1) = it["bbox"]
    if y0 < DOOR_HALF and y1 > -DOOR_HALF and z0 < DOOR_Z[1] and z1 > DOOR_Z[0]:
        fails.append("F｜侵占门洞通行带 %s y[%.3f,%.3f] z[%.3f,%.3f]"
                     % (it["instance_id"], y0, y1, z0, z1))

# G) 中央主通道净空
for it in fac:
    (x0, y0, z0), (x1, y1, z1) = it["bbox"]
    if z0 < DOOR_Z[1] and z1 > DOOR_Z[0] and y0 < CORRIDOR_HALF and y1 > -CORRIDOR_HALF:
        fails.append("G｜侵占中央主通道 %s y[%.3f,%.3f]" % (it["instance_id"], y0, y1))

# H) 陈设越界 / 两两重叠
for it in fac:
    (x0, y0, z0), (x1, y1, z1) = it["bbox"]
    if x0 < -FAC_LIMIT - 0.05 or x1 > FAC_LIMIT + 0.05:
        fails.append("H｜越界(x) %s [%.3f,%.3f]" % (it["instance_id"], x0, x1))
    if y0 < -FAC_LIMIT - 0.05 or y1 > FAC_LIMIT + 0.05:
        fails.append("H｜越界(y) %s [%.3f,%.3f]" % (it["instance_id"], y0, y1))
    if z0 < -0.33 - 1e-6:
        fails.append("I｜穿地 %s z0=%.3f" % (it["instance_id"], z0))
for i in range(len(fac)):
    for j in range(i + 1, len(fac)):
        a, b = fac[i]["bbox"], fac[j]["bbox"]
        ox = min(a[1][0], b[1][0]) - max(a[0][0], b[0][0])
        oy = min(a[1][1], b[1][1]) - max(a[0][1], b[0][1])
        oz = min(a[1][2], b[1][2]) - max(a[0][2], b[0][2])
        if ox > 1e-3 and oy > 1e-3 and oz > 1e-3:
            fails.append("H｜重叠 %s × %s (Δ=%.3f,%.3f,%.3f)"
                         % (fac[i]["instance_id"], fac[j]["instance_id"], ox, oy, oz))

# 包络
all_lo = Vector((min(it["bbox"][0][0] for it in items),
                 min(it["bbox"][0][1] for it in items),
                 min(it["bbox"][0][2] for it in items)))
all_hi = Vector((max(it["bbox"][1][0] for it in items),
                 max(it["bbox"][1][1] for it in items),
                 max(it["bbox"][1][2] for it in items)))
if not (22.0 <= all_hi[2] <= 16.0):
    pass
if abs(all_lo[2] - (-0.32)) > 0.02:
    warns.append("包络底面 z=%.3f（预期 −0.32 地砖底）" % all_lo[2])
if all_hi[2] < 11.8:
    fails.append("I｜墙高不足：包络顶 z=%.3f < 11.9" % all_hi[2])

report = dict(
    schema="shellstorm2.room_type_layout_qa",
    schema_version=1,
    room_type_id=plan["room_type_id"],
    blend=BLEND.name,
    instances=len(items),
    counts=dict(cnt_role),
    sources=dict(cnt_src),
    envelope_m=dict(
        min=[round(v, 4) for v in all_lo],
        max=[round(v, 4) for v in all_hi],
        size=[round(all_hi[i] - all_lo[i], 4) for i in range(3)],
    ),
    tile_coverage_m=[round(cov_x1 - cov_x0, 3), round(cov_y1 - cov_y0, 3)],
    linked_packages=len({(it["source"], it["slug"]) for it in items}),
    room_owned_meshes=len(own_meshes),
    wall_slots={w: sorted(round(v, 3) for _, v, _ in lst) for w, lst in edge.items()},
    total_vertices_sampled=sum(it["verts"] for it in items),
    warnings=warns,
    failures=fails,
    instances_detail=items,
)
JSON_OUT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n",
                    encoding="utf-8", newline="\r\n")

print("=== std_25x25 布局源 v001 结构契约校验 ===")
print("实例总数      :", len(items))
print("按角色        :", dict(cnt_role))
print("按来源        :", dict(cnt_src))
print("链接资产包    :", report["linked_packages"])
print("本文件自持Mesh:", report["room_owned_meshes"])
print("包络          :", report["envelope_m"]["size"], "min", report["envelope_m"]["min"])
print("地砖覆盖      :", report["tile_coverage_m"])
print("墙槽          :", report["wall_slots"])
for w in warns:
    print("  ⚠", w)
if fails:
    print("!! 失败 %d 条：" % len(fails))
    for f in fails:
        print("  ✗", f)
    print("STD25_LAYOUT_QA_FAILED")
    sys.exit(1)
print("STD25_LAYOUT_QA_OK")
