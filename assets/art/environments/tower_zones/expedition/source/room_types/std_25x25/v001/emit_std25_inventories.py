# -*- coding: utf-8 -*-
"""标准房间种类（四墙平房 25x25m）v001 —— 清单派生器。

从三份真源**确定性派生**出两份清单，不手写任何一条记录：

    输入① std_25x25_v001.layout.json            （本房型摆位真源，82 实例）
    输入② office_room/v001/component_inventory.json  （106 包）
    输入③ bridge_room/v002/component_inventory.json  （242 包）

    输出① component_inventory.json   —— 本房型**引用**到的资产包清单（81 包）+ 本房用法
    输出② room_type_manifest.json    —— 房型级清单（元数据 + packages[]，与输出①同构）

⚠️ 与 office/bridge 的 component_inventory 语义差异（有意为之）：
    那两批是「**本房型自己拆出来的**组件清单」（房型自持几何）；
    本房型是 skill 03 意义上的「**实例布局**」——自持几何 = 0，一切几何来自两批已验收源，
    所以这里的 component_inventory 记的是**被引用的外部资产包**及其在本房的用法，
    `output_mesh_count = 0` / `room_owned_geometry = false`。

用法：
    python emit_std25_inventories.py
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
OUT = HERE.parent
ROOT = HERE.parents[9]                       # ShellStorm2/
ROOM_TYPES = ROOT / "assets/art/environments/tower_zones/expedition/source/room_types"

LAYOUT = OUT / "std_25x25_v001.layout.json"
INVENTORY_OUT = OUT / "component_inventory.json"
MANIFEST_OUT = OUT / "room_type_manifest.json"

SOURCE_INVENTORY = {
    "office_room/v001": ROOM_TYPES / "office_room/v001/component_inventory.json",
    "bridge_room/v002": ROOM_TYPES / "bridge_room/v002/component_inventory.json",
}
# 两批源 manifest 里的公共字段直接沿用，保证同一工作区内口径一致
SIBLING_MANIFEST = {
    "office_room/v001": ROOM_TYPES / "office_room/v001/room_type_manifest.json",
    "bridge_room/v002": ROOM_TYPES / "bridge_room/v002/room_type_manifest.json",
}
PLAN_SHEET = ROOT / "docs/v0.1/design/refs/expedition01/plans/08-标准房间.svg"
WHITEBOX = ROOT / "source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/std_25x25.json"

fails = []


def chk(cond, msg):
    if not cond:
        fails.append(msg)
    return cond


# ------------------------------------------------------------------ 读真源
plan = json.loads(LAYOUT.read_text(encoding="utf-8"))
instances = plan["instances"]
whitebox = json.loads(WHITEBOX.read_text(encoding="utf-8"))
office_man = json.loads(SIBLING_MANIFEST["office_room/v001"].read_text(encoding="utf-8"))

REC = {}
for src, path in SOURCE_INVENTORY.items():
    inv = json.loads(path.read_text(encoding="utf-8"))
    for r in inv:
        key = (src, r["slug"])
        chk(key not in REC, "两批源出现重复 (source, slug)：%s" % (key,))
        REC[key] = r
print("[真源] 两批源可解析资产包合计 %d 个（office %d + bridge %d）"
      % (len(REC),
         sum(1 for k in REC if k[0] == "office_room/v001"),
         sum(1 for k in REC if k[0] == "bridge_room/v002")))

# ------------------------------------------------------------------ 按实例出现序汇总引用
order = []
by_ref = {}
for it in instances:
    key = (it["source_room_type"], it["slug"])
    chk(key in REC, "实例引用了清单里不存在的组件：%s / %s" % (it["instance_id"], key))
    if key not in by_ref:
        by_ref[key] = {"instance_ids": [], "slot_roles": [], "positions_m": [], "rotations_z_deg": []}
        order.append(key)
    u = by_ref[key]
    u["instance_ids"].append(it["instance_id"])
    u["slot_roles"].append(it["slot_role"])
    u["positions_m"].append([round(v, 4) for v in it["position_m"]])
    u["rotations_z_deg"].append(it["rotation_z_deg"])

print("[引用] 唯一资产包 %d 个 / 实例 %d 件" % (len(order), len(instances)))

# ------------------------------------------------------------------ 组装清单记录
records = []
for src, slug in order:
    base = REC[(src, slug)]
    u = by_ref[(src, slug)]
    rec = dict(base)                      # 原字段逐字保留，不改、不丢
    rec["source_room_type"] = src
    rec["source_manifest"] = (
        "assets/art/environments/tower_zones/expedition/source/room_types/%s/room_type_manifest.json" % src)
    rec["usage_in_std_25x25"] = {
        "instance_count": len(u["instance_ids"]),
        "instance_ids": u["instance_ids"],
        "slot_roles": sorted(set(u["slot_roles"])),
        "positions_m": u["positions_m"],
        "rotations_z_deg": u["rotations_z_deg"],
    }
    records.append(rec)

# 断言：原字段一个不少
for (src, slug), rec in zip(order, records):
    missing = set(REC[(src, slug)].keys()) - set(rec.keys())
    chk(not missing, "字段丢失：%s / %s -> %s" % (src, slug, sorted(missing)))
# 断言：package_id 全局唯一（两批源的 package_id 已带 -OFFICE-/-BRIDGE- 命名空间）
ids = [r["package_id"] for r in records]
chk(len(ids) == len(set(ids)), "package_id 出现重复：%s"
    % [i for i in set(ids) if ids.count(i) > 1])

by_cat = {}
for r in records:
    by_cat[r["category"]] = by_cat.get(r["category"], 0) + 1
by_src = {}
for r in records:
    by_src[r["source_room_type"]] = by_src.get(r["source_room_type"], 0) + 1
print("[分类] %s" % by_cat)
print("[来源] %s" % by_src)

# ------------------------------------------------------------------ 输出① 组件清单
INVENTORY_OUT.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8", newline="\r\n")
print("[写出]", INVENTORY_OUT.name, "(%d 条)" % len(records))

# ------------------------------------------------------------------ 输出② 房型清单
lanes = whitebox["wall_lane_table"]
door_lanes = {k: len(v) for k, v in lanes.items()}
authored_doors = [i for i in instances if i["slot_role"] == "door_wall"]
door_slots = {}
for i in authored_doors:
    door_slots[i["instance_id"]] = {"position_m": i["position_m"],
                                    "rotation_z_deg": i["rotation_z_deg"],
                                    "lane_offset_m": i["position_m"][1] if "WEST" in i["instance_id"]
                                    or "EAST" in i["instance_id"] else i["position_m"][0]}

plan_sha = hashlib.sha256(PLAN_SHEET.read_bytes()).hexdigest() if PLAN_SHEET.exists() else None

manifest = {
    "schema": "shellstorm2.room_type_art_manifest",
    "schema_version": 1,
    "version": plan["layout_version"],
    "template_id": whitebox["template_id"],
    "room_type": whitebox["room_type"],
    "block_id": plan["block_id"],
    "design_scope": "scene_art",
    "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::资产主表",
    "room_asset_id": plan["asset_id"],
    "source_blend": "标准房间种类_四墙平房_25x25m_v001.blend",
    "whitebox_source": "source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/std_25x25.json",
    "layout_source": "assets/art/environments/tower_zones/expedition/source/room_types/std_25x25/v001/std_25x25_v001.layout.json",
    "dimensions_m": plan["dimensions_m"],
    "grid_unit_m": plan["grid_unit_m"],
    "wall_visual_height_m": plan["wall_height_m"],
    "wall_logic_height_m": 12,
    "interior_walls": False,
    "source_composition": plan["scope"],
    "composition": plan["composition"],
    "source_room_types": plan["component_sources"],
    "cross_source_slug_collisions": plan["cross_source_slug_collisions"],
    "door_contract": whitebox["door_contract"],
    "door_lanes": dict(total=sum(door_lanes.values()), **door_lanes),
    "door_lanes_authored": {
        "west": 0.0,
        "east": 0.0,
        "note": "本房型冻结西/东墙 lane 0 对穿（西进东出）。依据：设计页 §4.2.1 记 room_06→07 与 room_07→08 均走西/东墙；参考图 08-标准房间.svg 门标在左右墙中线。",
        "instances": door_slots,
    },
    "door_wall_piece": {
        "reusable": True,
        "authored_at": "north wall lane x=+2.5",
        "source_package": "office_room/v001::door_wall",
        "geometry_wdh_m": [5.0, 11.9, 0.3],
        "note": "门洞墙件几何对各朝向一致；本房型把该件以 90°/270° 摆到西/东墙 lane 0。运行时按门位车道替换对应标准墙件、并由 RoomDoor3D 开关门扇，房型源不序列化门扇。",
    },
    "required_components": [
        "segmented floor deck tiles（25 块，取自 office_room/v001）",
        "perimeter wall bays（18 件实墙 + 2 扇门墙，取自 office_room/v001）",
        "reusable door wall bay（office_room/v001::door_wall，西/东墙 lane 0）",
        "mechanical/utility facilities（取自 bridge_room/v002 上层件）",
        "office furniture clusters（取自 office_room/v001）",
    ],
    "required_facilities": [
        "4 workstation clusters（office）",
        "totem column / locker bank / printer station / shelving / water & supply corner / prep bench（office）",
        "server banks ×2 / power cabinets ×2 / upper banks ×4 / consoles ×2（bridge）",
        "partitions ×2 / partition boxes ×2 / crates ×6（bridge）",
        "overhead cable headers ×3 / torn headers ×2（bridge，高位）",
    ],
    "door_geometry_in_source": False,
    "reference_image": str(PLAN_SHEET),
    "reference_sha256": plan_sha,
    "reference_note": "本房型无独立效果图：设计依据 = 平面图纸 08-标准房间.svg + 两批源房型各自的参考图（office 办公室01.jpg / bridge 见其 manifest）。",
    "scope": {
        "modifiable": "布局（实例的位置/旋转/启用）、展示相机与灯光",
        "locked": "白盒尺寸(25×25×11.9) / 地面标高 / 门洞契约 / 无内墙 / 组件几何与材质与根原点 / 玩法",
        "previous_versions_preserved": True,
    },
    "package_count": len(records),
    "instance_count": len(instances),
    "output_mesh_count": 0,
    "room_owned_geometry": False,
    "room_owned_components_created": 0,
    "material_roles": office_man["material_roles"],
    "palette_texture": office_man["palette_texture"],
    "preview_note": plan.get("scope_note", ""),
    "notes": plan["notes"],
    "packages": records,
}

MANIFEST_OUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8", newline="\r\n")
print("[写出]", MANIFEST_OUT.name)

# ------------------------------------------------------------------ 收口
expected_refs = 81
expected_instances = 82
chk(len(records) == expected_refs, "引用资产包数应为 %d，实为 %d" % (expected_refs, len(records)))
chk(len(instances) == expected_instances, "实例数应为 %d，实为 %d" % (expected_instances, len(instances)))

if fails:
    print("\n失败 %d 项：" % len(fails))
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("\nOK  清单派生通过（引用 %d 包 / 实例 %d 件 / 自持几何 0）" % (len(records), len(instances)))
