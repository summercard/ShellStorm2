"""Rebuild env_base100_upper_shell_30x30_h12_root_top3d.tscn.

用户口径（2026-09-20）：
- 东/西/南三面共 17 个 5m 普通墙槽 -> 天台参考组件库 v002「房间标准墙」
- 东面 z=-7.5 门洞槽**不动**：继续用 base99 门墙（它是 100F 唯一过场门位，
  功能门 RoomDoor3D 的净尺寸写死 TOWER_GEOMETRY.DOOR_CLEAR_* = 2.2x2.5）
- 北面 2 普通墙 + 4 窗墙**不动**（base99）
- 24m 封顶 36 格 -> 天台参考组件库 v002 房顶模块（4 角 + 16 边 + 16 内圈）

朝向口径（三方互证：TowerFloorStage3D._build_rooftop_facade_ring() 的立面环注释、
美术自己的 reference_assembly.json、以及本脚本的 rotation 反解）：
  v002 朝外法线 = 局部 +Z；max z 边 -> 0°，min z 边 -> 180°，
  max x 边 -> +90°，min x 边 -> -90°。
  ⚠️ base99 件是 forward=-Z，差 180°：同一条东墙，base99 用 -90°、v002 用 +90°。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/art/environments/base_facility_3d/runtime/env_base100_upper_shell_30x30_h12/env_base100_upper_shell_30x30_h12_root_top3d.tscn"

BASE = "res://assets/art/environments/base_facility_3d/runtime"
ROOFTOP = "res://assets/art/props/dungeon_3d"

EXT = [
    ("1_plain", "PackedScene", f"{BASE}/env_base99_wall_plain_5x12/env_base99_wall_plain_5x12_root_top3d.tscn"),
    ("2_window", "PackedScene", f"{BASE}/env_base99_wall_window_5x12/env_base99_wall_window_5x12_root_top3d.tscn"),
    ("3_door", "PackedScene", f"{BASE}/env_base99_wall_door_5x12/env_base99_wall_door_5x12_root_top3d.tscn"),
    ("4_shell", "Script", "res://src/world3d/Base100UpperShell3D.gd"),
    ("5_room_wall", "PackedScene", f"{ROOFTOP}/prp_rooftop_room_wall_5x12.tscn"),
    ("6_roof_full", "PackedScene", f"{ROOFTOP}/prp_rooftop_roof_full_5m.tscn"),
    ("7_roof_edge", "PackedScene", f"{ROOFTOP}/prp_rooftop_roof_edge_5m.tscn"),
    ("8_roof_corner", "PackedScene", f"{ROOFTOP}/prp_rooftop_roof_corner_5m.tscn"),
]

PI = 3.14159265
HALF_PI = 1.57079633

HEADER = """; 基地100层上层围护与24米封顶（30x30 x h12）
;
; 【美术来源一分为二 · 2026-09-20】
;   天台参考组件库 v002（东/西/南三面墙 + 24m 封顶）：
;     res://assets/art/environments/tower_zones/rooftop/source/reference_components/v002/天台区块_参考组件库_v002.blend
;     Prefab：prp_rooftop_room_wall_5x12 / prp_rooftop_roof_{full,edge,corner}_5m
;   基地99层模块（北面 2 普通墙 + 4 窗墙 + 东面门洞槽）：
;     res://assets/art/environments/base_facility_3d/source/env_base99_modular_room/env_base99_modular_room_source_v001.blend
;
; ⚠️【朝向差 180° — 改这层墙必须先看这条】
;   v002 件的外法线 = 局部 +Z；base99 件 = 局部 -Z。同一条边，两者 rotation_y 差 π：
;     | 边   | v002 (+Z 朝外)      | base99 (-Z 朝外)   |
;     | max z(南) | 0°             | 180°               |
;     | min z(北) | 180°           | 0°                 |
;     | max x(东) | +90°           | -90°               |
;     | min x(西) | -90°           | +90°               |
;   本文件里东墙 5 块 v002 用 +90°、而东墙门洞槽的 base99 门墙仍用 -90°：
;   两者都朝 +X（房间外），视觉一致，别"顺手统一"成同一个角度。
;   口径来源三方互证：TowerFloorStage3D._build_rooftop_facade_ring() 注释、
;   美术 reference_assembly.json 的四向 rotation_z、以及本文件实测反解。
;
; ⚠️【东面门洞槽为什么不换成 v002 的厚石门洞墙】
;   v002 房间门洞墙的洞是 3.80 x 6.80 m；而这个门位是 100F 唯一的外梯过场门，
;   由 TowerDescent3D._install_base_rooftop_transit_door() 挂 RoomDoor3D，
;   其净尺寸写死 TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M/HEIGHT_M = 2.2 x 2.5（改它等于
;   改全游戏所有门）。故门洞槽保留 base99 门墙，v002 的门洞墙/门/门扇三件
;   已制作并登记，仅未在此场景摆放。见 prp_rooftop_room_door*.tscn 顶部注释。
;
; 子节点位置完全由本 tscn 持有；Base100UpperShell3D 只提供连续结构碰撞与投影策略。
"""


def g(v: float) -> str:
    return "%g" % v


def vec(x, y, z) -> str:
    return "Vector3(%s, %s, %s)" % (g(x), g(y), g(z))


def node(name, ext_id, x, y, z, rot_y, meta_lines):
    lines = ['[node name="%s" parent="100层围护墙_可移动旋转" instance=ExtResource("%s")]' % (name, ext_id)]
    lines.append("position = %s" % vec(x, y, z))
    if rot_y != 0.0:
        lines.append("rotation = Vector3(0, %s, 0)" % g(rot_y))
    lines.extend(meta_lines)
    return "\n".join(lines)


META_FLOOR100 = ['metadata/floor_index = 100', 'metadata/segment_count = 1']

parts = []
parts.append("[gd_scene load_steps=%d format=3]\n" % (len(EXT) + 1))
parts.append(HEADER)
for eid, etype, path in EXT:
    parts.append('[ext_resource type="%s" path="%s" id="%s"]' % (etype, path, eid))
parts.append("")

parts.append('[node name="基地100层上层围护与封顶" type="Node3D"]')
parts.append('script = ExtResource("4_shell")')
parts.append('metadata/asset_id = "ENV-BASE100-UPPER-SHELL-30X30-H12"')
parts.append('metadata/logic_id = "base100_upper_shell_30x30_h12"')
parts.append('metadata/asset_category = "environment_kit_3d"')
parts.append('metadata/floor_index = 100')
parts.append('metadata/plain_wall_count = 19')
parts.append('metadata/window_wall_count = 4')
parts.append('metadata/door_wall_count = 1')
parts.append('metadata/roof_tile_count = 36')
parts.append('metadata/rooftop_room_wall_count = 17')
parts.append('metadata/rooftop_roof_corner_count = 4')
parts.append('metadata/rooftop_roof_edge_count = 16')
parts.append('metadata/rooftop_roof_full_count = 16')
parts.append('metadata/shadow_policy = "cast_and_receive"')
parts.append('metadata/source_blend = "res://assets/art/environments/base_facility_3d/source/env_base99_modular_room/env_base99_modular_room_source_v001.blend"')
parts.append('metadata/rooftop_source_blend = "res://assets/art/environments/tower_zones/rooftop/source/reference_components/v002/天台区块_参考组件库_v002.blend"')
parts.append('metadata/art_note = "东/西/南三面 17 块墙与 24m 封顶 36 格换成天台参考组件库 v002；北面 4 大窗与东面门洞槽保留 base99（东门槽是 100F 唯一过场门位，RoomDoor3D 净尺寸写死 2.2x2.5）。"')
parts.append("")

# ---------------------------------------------------------------- 墙
parts.append('[node name="100层围护墙_可移动旋转" type="Node3D" parent="."]')
parts.append('metadata/usage = "北侧 2 普通墙 + 中间 4 块窗墙（base99，未替换）；东/西/南三面 17 块天台 v002 房间标准墙 + 东面 1 块 base99 门墙。⚠️ v002 用 +Z 朝外、base99 用 -Z 朝外，两者 rotation_y 差 180°。"')

X = [-12.5, -7.5, -2.5, 2.5, 7.5, 12.5]

# 北墙：base99，不动（rot 0）
parts.append(node("北墙_00_普通墙", "1_plain", -12.5, 12, -15, 0.0, META_FLOOR100))
for idx, x in enumerate([-7.5, -2.5, 2.5, 7.5], start=1):
    parts.append(node("北墙_%02d_窗墙" % idx, "2_window", x, 12, -15, 0.0, META_FLOOR100))
parts.append(node("北墙_05_普通墙", "1_plain", 12.5, 12, -15, 0.0, META_FLOOR100))

# 南墙：v002 标准墙，z=+15 是 max z 边 -> v002 用 0°
for idx, x in enumerate([12.5, 7.5, 2.5, -2.5, -7.5, -12.5]):
    parts.append(node("南墙_%02d_标准墙" % idx, "5_room_wall", x, 12, 15, 0.0, META_FLOOR100))

# 西墙：v002 标准墙，x=-15 是 min x 边 -> v002 用 -90°
for idx, z in enumerate([-12.5, -7.5, -2.5, 2.5, 7.5, 12.5]):
    parts.append(node("西墙_%02d_标准墙" % idx, "5_room_wall", -15, 12, z, -HALF_PI, META_FLOOR100))

# 东墙：x=+15 是 max x 边 -> v002 用 +90°；门洞槽 (z=-7.5) 仍是 base99 门墙 -> -90°
parts.append(node("东墙_00_标准墙", "5_room_wall", 15, 12, -12.5, HALF_PI, META_FLOOR100))
parts.append(node("东墙_01_侧向门墙", "3_door", 15, 12, -7.5, -HALF_PI, META_FLOOR100))
for idx, z in enumerate([-2.5, 2.5, 7.5, 12.5], start=2):
    parts.append(node("东墙_%02d_标准墙" % idx, "5_room_wall", 15, 12, z, HALF_PI, META_FLOOR100))
parts.append("")

# ---------------------------------------------------------------- 封顶 6x6
parts.append('[node name="24米封顶_6x6地砖" type="Node3D" parent="."]')
parts.append('metadata/usage = "6×6 共 36 格天台参考组件库 v002 房顶模块：4 角格 roof_corner + 16 边格 roof_edge + 16 内圈格 roof_full。参与真实遮光并产生投影。"')
parts.append('metadata/floor_index = 101')
parts.append('metadata/tile_count = 36')
parts.append('metadata/roof_corner_count = 4')
parts.append('metadata/roof_edge_count = 16')
parts.append('metadata/roof_full_count = 16')

COORDS = [-12.5, -7.5, -2.5, 2.5, 7.5, 12.5]
for j, z in enumerate(COORDS):          # j: z 行下标（0 = min z）
    for i, x in enumerate(COORDS):      # i: x 列下标（0 = min x）
        at_min_z, at_max_z = (j == 0), (j == 5)
        at_min_x, at_max_x = (i == 0), (i == 5)
        if (at_min_z or at_max_z) and (at_min_x or at_max_x):
            ext = "8_roof_corner"
            if at_min_x and at_max_z:
                rot = 0.0                   # (min x, max z)
            elif at_max_x and at_max_z:
                rot = HALF_PI               # (max x, max z)
            elif at_max_x and at_min_z:
                rot = PI                    # (max x, min z)
            else:
                rot = -HALF_PI              # (min x, min z)
        elif at_max_z:
            ext, rot = "7_roof_edge", 0.0
        elif at_min_z:
            ext, rot = "7_roof_edge", PI
        elif at_max_x:
            ext, rot = "7_roof_edge", HALF_PI
        elif at_min_x:
            ext, rot = "7_roof_edge", -HALF_PI
        else:
            ext, rot = "6_roof_full", 0.0
        lines = ['[node name="封顶_%02d_%02d" parent="24米封顶_6x6地砖" instance=ExtResource("%s")]' % (j, i, ext)]
        lines.append("position = %s" % vec(x, 24, z))
        if rot != 0.0:
            lines.append("rotation = Vector3(0, %s, 0)" % g(rot))
        lines.append("metadata/floor_index = 101")
        lines.append("metadata/instance_count = 1")
        parts.append("\n".join(lines))

# 先按 \n 拼装，再整体归一为纯 CRLF（parts 内部的多行串含裸 \n，只 join 不够）
text = "\n".join(parts) + "\n"
text = text.replace("\r\n", "\n").replace("\n", "\r\n")
OUT.write_bytes(text.encode("utf-8"))
print("WROTE %s bytes=%d" % (OUT, len(text.encode("utf-8"))))

# ---- 自检：计数与朝向分布 ----
import collections
counts = collections.Counter()
rot_by_ext = collections.defaultdict(set)
for line in text.split("\r\n"):
    for eid in ["5_room_wall", "3_door", "1_plain", "2_window", "6_roof_full", "7_roof_edge", "8_roof_corner"]:
        if 'instance=ExtResource("%s")' % eid in line:
            counts[eid] += 1
print("COUNTS", dict(counts))
assert counts["5_room_wall"] == 17, counts
assert counts["1_plain"] == 2, counts
assert counts["2_window"] == 4, counts
assert counts["3_door"] == 1, counts
assert counts["8_roof_corner"] == 4, counts
assert counts["7_roof_edge"] == 16, counts
assert counts["6_roof_full"] == 16, counts
print("SELFCHECK_OK walls=%d roof=%d" % (17 + 2 + 4 + 1, 36))
