#!/usr/bin/env python3
"""boss 静态 TSCN 门位空阻挡修复 (v5)。

诊断（实测，见 _scratch/boss_door_passage.py 与 scan_all_doors.py）：
  boss 房型源 v011 把装甲墙皮摆在了**门模块**上（godot 局部 z=-2.5）：
    wall_skin_west_04 / wall_skin_east_04
  而 boss 的两扇门（西 -> room_10、东 -> extraction）门槽 lane 都是 z=-2.5
  （见 boss TSCN 的 ConnectionPorts: Port_A/Port_B 均 lane_m=-2.5，
   与 snapshot_tower_wall_door_offset_{west,east} = -2.5 一致）。
  墙皮 prefab 的碰撞是**单个 BoxShape3D 0.36 x 11.8 x 4.925**（全高、近 5m 宽），
  压在门洞上 => 门被整条封死（净空缝 0.000m，玩家胶囊需 >= 0.68m）。

  运行时 `DungeonRoom3D._apply_authored_runtime_door_contract()` 在房间有
  connection_ports 时**早退**，只对结构墙做门槽处理（西：共墙非所有者剔除；
  东：提升为门墙），**不处理装饰件** => 墙皮不会被门槽剔除。

  另有两件加剧阻挡：
    west_damaged_01  （server_rack_compact_damaged）摆在 z=-3.5，把西门缝压到 0.515m；
    archive_shelf_02 被拖到 x=23.589 并旋转，整个横在东门通道口 x[23,23.8]。

  原始生成版 661f8bf2 即已如此（门一直就是堵的），与后续人工改动无关。

修复动作（保计数、不引入新资产、纯外科）：
  1) 删除 wall_skin_west_04 / wall_skin_east_04（两件本就不该出现在门模块）。
  2) west_damaged_01 沿西墙 z: -3.5 -> -7.5（让出门带 [z_lane ± 1.1]）。
  3) archive_shelf_02 还原到摆位源坐标 (21, -0.058, -2) 与单位旋转，退出东门通道。
  4) 补回 plant_01..04 —— 661f8bf2（权威生成版）有 5 株，7b8aa1f6 的编辑器重存
     误删了 4 株。节点文本原样取自 661f8bf2，含完整 metadata。

行尾：保持工作区 CRLF（仓库 LF / 工作区 CRLF，core.autocrlf=true）。
幂等：打过补丁再跑直接跳过。
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSCN = os.path.join(
    REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "runtime", "room_instances", "expedition_01", "f00_boss_static_layout.tscn",
)

# ---- 1) 要删的门模块墙皮 ----
DELETE_SKINS = ["wall_skin_west_04", "wall_skin_east_04"]

# ---- 2) 机架让出门带 ----
RACK = "west_damaged_01"
RACK_OLD = "-22.712, -0.228, -3.5"
RACK_NEW = "-22.712, -0.228, -7.5"

# ---- 3) 档案架还原摆位源坐标 ----
SHELF = "archive_shelf_02"
SHELF_OLD = ("Transform3D(0.016482515, -0.9684993, -0.24847011, 0.9998552, 0.01701615, 0, "
             "0.0042280047, -0.24843414, 0.96863955, 23.588589, 1.0730814, -2)")
SHELF_NEW = "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 21, -0.058, -2)"

# ---- 4) 补回植物（原文取自 661f8bf2，含完整 metadata）----
PLANT_EXT = [
    ('plant_a', 'res://assets/art/environments/tower_zones/expedition/runtime/'
                'room_type_components/boss_room/plant_a/plant_a_root_top3d.tscn', '23_p14cg'),
    ('plant_b', 'res://assets/art/environments/tower_zones/expedition/runtime/'
                'room_type_components/boss_room/plant_b/plant_b_root_top3d.tscn', '24_hi7xl'),
    ('plant_c', 'res://assets/art/environments/tower_zones/expedition/runtime/'
                'room_type_components/boss_room/plant_c/plant_c_root_top3d.tscn', '25_snexm'),
]
_B = 'ENV-EXPEDITION-L01-BOSS-'
_BLEND = ('res://assets/art/environments/tower_zones/expedition/source/common_components/'
          'v011/component_packages/%s/%s.blend')


def plant_block(name, uid, ext_id, slug, cid, bounds, x, y, z, zh):
    return (
        '[node name="%s" type="Node3D" parent="." unique_id=%d instance=ExtResource("%s")]\n'
        'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\n'
        'metadata/asset_id = "%s%s"\n'
        'metadata/asset_version = "v011"\n'
        'metadata/room_type = "BOSS_ROOM"\n'
        'metadata/component_slug = "%s"\n'
        'metadata/display_name_zh = "%s"\n'
        'metadata/source_blend = "%s"\n'
        'metadata/origin_contract = "bottom_center"\n'
        'metadata/front_axis_blender = "-Y"\n'
        'metadata/up_axis = "+Y"\n'
        'metadata/bounds_size_m = Vector3(%s, %s, %s)\n'
        'metadata/slot_role = "room_type_component"\n'
        'metadata/collision_owner = "self"\n'
        'metadata/collision_policy = "safe_box_proxy"\n'
        'metadata/collision_shape_count = 1\n'
        'metadata/runtime_instantiation = "per_instance_prefab"\n'
        'metadata/authored_component_id = "%s%s"\n'
        'metadata/authored_slot_role = "room_type_component"\n\n'
        % (name, uid, ext_id, x, y, z,
           _B, cid, slug, zh, _BLEND % (slug, slug),
           bounds[0], bounds[1], bounds[2], _B, cid)
    )


PLANTS = [
    plant_block("plant_01", 917164477, "24_hi7xl", "plant_b", "PLANT_B",
                ("1.6487", "1.7055", "1.6742"), "-19.9744", "-0.058", "-7",
                "固定绿植（型 B）1.65×1.67×1.71m"),
    plant_block("plant_02", 727564675, "25_snexm", "plant_c", "PLANT_C",
                ("1.6487", "1.6891", "1.6742"), "-19.9744", "-0.058", "12",
                "固定绿植（型 C）1.65×1.67×1.69m"),
    plant_block("plant_03", 1727999696, "23_p14cg", "plant_a", "PLANT_A",
                ("1.6487", "1.7098", "1.6742"), "-14.9744", "-0.058", "17",
                "固定绿植（型 A）1.65×1.67×1.71m"),
    plant_block("plant_04", 807589747, "25_snexm", "plant_c", "PLANT_C",
                ("1.6487", "1.6891", "1.6742"), "20.0256", "-0.058", "-13",
                "固定绿植（型 C）1.65×1.67×1.69m"),
]


def find_block(text, node_name):
    """返回节点块 [start, end)（含其后的空行）。"""
    m = re.search(r'(?m)^\[node name="%s"[^\]]*\]$' % re.escape(node_name), text)
    if not m:
        return None
    nxt = re.search(r'(?m)^\[node ', text[m.end():])
    end = m.end() + (nxt.start() if nxt else len(text) - m.end())
    while end < len(text) and text[end] == "\n":
        end += 1
    return (m.start(), end)


def main():
    raw = open(TSCN, "rb").read()
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    assert lone_lf == 0, "工作区文件含孤立 LF（%d），先确认真实行尾" % lone_lf
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if 'name="wall_skin_west_04"' not in text and 'name="plant_04"' in text \
            and RACK_NEW in text and SHELF_NEW in text:
        print("已打过补丁，跳过")
        return

    existing_ids = set(int(x) for x in re.findall(r'unique_id=(\d+)', text))
    for blk in PLANTS:
        uid = int(re.search(r'unique_id=(\d+)', blk).group(1))
        nm = re.search(r'name="([^"]+)"', blk).group(1)
        if 'name="%s"' % nm in text:
            continue
        assert uid not in existing_ids, "unique_id %d (%s) 与现有节点冲突" % (uid, nm)
        existing_ids.add(uid)

    # ---- A) ext_resource：补 plant_b / plant_c ----
    for slug, path, ext_id in PLANT_EXT:
        if 'id="%s"' % ext_id in text:
            continue
        anchor = re.search(
            r'(?m)^\[ext_resource type="PackedScene" path="[^"]*plant_a/[^"]+" id="23_p14cg"\]$',
            text)
        assert anchor, "找不到 plant_a ext_resource 锚点"
        ins = ('[ext_resource type="PackedScene" path="%s" id="%s"]' % (path, ext_id))
        text = text[:anchor.end()] + "\n" + ins + text[anchor.end():]
        print("+ ext_resource %s" % ext_id)

    # ---- B) 补植物：插在 plant_00 块之后 ----
    blk = find_block(text, "plant_00")
    assert blk, "找不到 plant_00"
    add = "".join(p for p in PLANTS
                  if 'name="%s"' % re.search(r'name="([^"]+)"', p).group(1) not in text)
    if add:
        text = text[:blk[1]] + add + text[blk[1]:]
        for p in PLANTS:
            nm = re.search(r'name="([^"]+)"', p).group(1)
            if 'name="%s"' % nm in add:
                print("+ node %s" % nm)

    # ---- C) 删门模块墙皮 ----
    for name in DELETE_SKINS:
        b = find_block(text, name)
        assert b, "找不到 %s" % name
        seg = text[b[0]:b[1]]
        assert 'tower_wall_direction = "south"' in seg, "%s 方向元数据异常" % name
        assert "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, " in seg, "%s 变换异常" % name
        text = text[:b[0]] + text[b[1]:]
        print("- node %s (门模块墙皮)" % name)

    # ---- D) 机架让位 ----
    b = find_block(text, RACK)
    assert b, "找不到 %s" % RACK
    seg = text[b[0]:b[1]]
    assert RACK_OLD in seg, "%s 原平移不匹配" % RACK
    text = text[:b[0]] + seg.replace(RACK_OLD, RACK_NEW) + text[b[1]:]
    print("~ move %s  z -3.5 -> -7.5" % RACK)

    # ---- E) 档案架还原 ----
    b = find_block(text, SHELF)
    assert b, "找不到 %s" % SHELF
    seg = text[b[0]:b[1]]
    assert SHELF_OLD in seg, "%s 现有变换不匹配" % SHELF
    text = text[:b[0]] + seg.replace(SHELF_OLD, SHELF_NEW) + text[b[1]:]
    print("~ revert %s -> (21, -0.058, -2) 单位旋转" % SHELF)

    assert "\r" not in text, "写入前发现 CR"
    out = text.replace("\n", "\r\n").encode("utf-8")
    open(TSCN, "wb").write(out)

    direct = len(re.findall(r'(?m)^\[node name="[^"]+"[^\]]*?\bparent="\."', text))
    inst = len(re.findall(r'(?m)^\[node name="[^"]+"[^\]]*?\bparent="\."[^\]]*instance=ExtResource', text))
    print("写入 %s" % os.path.relpath(TSCN, REPO))
    print("  直接子=%d  实例=%d  (阈值 EXPECTED_MIN_CHILDREN[boss] 见探针)" % (direct, inst))


if __name__ == "__main__":
    main()
