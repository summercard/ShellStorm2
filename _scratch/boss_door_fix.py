#!/usr/bin/env python3
"""boss 静态 TSCN 门位空阻挡外科手术 (v4, 保计数·保资产)。

诊断(实测 _scratch/boss_door_passage.py / scan_all_doors.py):
  boss 房型源 v011 把「源门洞」author 在 slot 04 = 局部 z=+2.5, 而运行时门槽是
  z=-2.5 (snapshot_tower_wall_door_offset_{west,east} = -2.5), 相差一个 5m 模块。
  于是源在运行时门槽上放了实心墙皮 + 贴墙机架。运行时装配器只对结构墙做门槽处理
  (west: 共墙非所有者 => continue; east: 提升为门墙), 不处理 room_type_component
  装饰件 => 门被墙皮整条封死(0.000m 空缝, 需 >= 0.68m)。

本脚本动作(全部保节点/保计数, 目标复现原生成版 209 实例 + ConnectionPorts = 210):
  1) 补回 plant_01..04 —— 相对原生成版 661f8bf2(209 实例) 被人工误删。
  2) wall_skin_west_04 / wall_skin_east_04 —— 骑在运行时门槽 z=-2.5 上的装饰墙皮;
     该处基底实墙已被剔除(west)/提升(east), 墙皮冗余且封死门。**迁移**到北墙空
     模位(x=-12.5 / +12.5): 北墙 10 个模位只有 north_00(=-22.5)、north_09(=+22.5)
     两处有墙皮, 余 8 个空位; 墙皮 prefab 与墙向无关(同一 armored prefab 本就同时
     用在 north_00 与 west_00), 4.925m 长恰为整模位, 无需畸变网格。同步把
     tower_wall_direction 由 "south" 改为北墙口径 "west"(与 north_00 一致)。
  3) 迁移 west_damaged_01 —— server_rack_compact_damaged 源位 z=-3.5 占门带
     (余 0.515m < 0.68m)。沿西墙 z: -3.5 -> -7.5, 让出门带。
  4) 还原 archive_shelf_02 —— 被人工搬到门道(x 23.588)并旋转; 还原为源位
     (21, -0.058, -2) 与单位旋转 => 退出东门通道 x[23,27]。
  5) east_complete_03/04 保留 —— 各仅擦门带边缘 0.185m, 门带中部余 1.83m > 0.68m。

行尾: 纯 LF。幂等: 打过补丁再跑直接跳过。
"""
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSCN = os.path.join(
    REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "runtime", "room_instances", "expedition_01", "f00_boss_static_layout.tscn",
)

# 搬去北墙空模位: 节点 -> (旧 transform 串, 新 transform 串, 新 direction)
NORTH_ROT = "1.1924881e-08, 0, -1, 0, 1, 0, 1, 0, 1.1924881e-08"
RELOCATE_SKIN = {
    "wall_skin_west_04": (
        "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -24.65, -0.308, -2.5)",
        "Transform3D(%s, -12.5, -0.308, -19.65)" % NORTH_ROT,
    ),
    "wall_skin_east_04": (
        "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 24.65, -0.308, -2.5)",
        "Transform3D(%s, 12.5, -0.308, -19.65)" % NORTH_ROT,
    ),
}

PLANTS = [
    ("plant_01", "24_hi7xl", 917164477, "ENV-EXPEDITION-L01-BOSS-PLANT_B", -19.9744, -0.058, -7.0),
    ("plant_02", "25_snexm", 727564675, "ENV-EXPEDITION-L01-BOSS-PLANT_C", -19.9744, -0.058, 12.0),
    ("plant_03", "23_p14cg", 1727999696, "ENV-EXPEDITION-L01-BOSS-PLANT_A", -14.9744, -0.058, 17.0),
    ("plant_04", "25_snexm", 807589747, "ENV-EXPEDITION-L01-BOSS-PLANT_C", 20.0256, -0.058, -13.0),
]
EXT_NEW = [("plant_b", "24_hi7xl"), ("plant_c", "25_snexm")]
EXT_BASE = ("res://assets/art/environments/tower_zones/expedition/runtime/"
            "room_type_components/boss_room/%s/%s_root_top3d.tscn")

RELOCATE = {"west_damaged_01": ("-22.712, -0.228, -3.5", "-22.712, -0.228, -7.5")}
REVERT = {
    "archive_shelf_02": (
        "Transform3D(0.016482515, -0.9684993, -0.24847011, 0.9998552, 0.01701615, 0, "
        "0.0042280047, -0.24843414, 0.96863955, 23.588589, 1.0730814, -2)",
        "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 21, -0.058, -2)",
    ),
}


def find_block(text, node_name):
    m = re.search(r'(?m)^\[node name="%s"[^\]]*\]\n' % re.escape(node_name), text)
    if not m:
        return None
    nxt = re.search(r'(?m)^\[node ', text[m.end():])
    end = m.end() + (nxt.start() if nxt else len(text) - m.end())
    while end < len(text) and text[end] == "\n":
        end += 1
    return (m.start(), end)


def main():
    text = open(TSCN, encoding="utf-8", newline="").read()
    assert "\r" not in text, "目标文件不是纯 LF"

    if 'name="plant_04"' in text and 'metadata/tower_wall_direction = "west"' in text \
            and "Transform3D(1.1924881e-08, 0, -1, 0, 1, 0, 1, 0, 1.1924881e-08, -12.5" in text:
        print("已打过补丁，跳过")
        return

    existing = set(int(x) for x in re.findall(r'unique_id=(\d+)', text))
    for name, _eid, uid, _cid, _x, _y, _z in PLANTS:
        assert uid not in existing, "unique_id %d (%s) 冲突" % (uid, name)

    # 1) ext_resource
    for slug, eid in EXT_NEW:
        if 'id="%s"' % eid in text:
            continue
        anchor = re.search(
            r'(?m)^\[ext_resource type="PackedScene" path="[^"]*plant_a/[^"]+" id="23_p14cg"\]\n', text)
        assert anchor, "找不到 plant_a ext_resource 锚点"
        text = (text[:anchor.end()]
                + '[ext_resource type="PackedScene" path="%s" id="%s"]\n' % (EXT_BASE % (slug, slug), eid)
                + text[anchor.end():])
        print("+ ext_resource %s" % eid)

    # 2) 植物
    block = find_block(text, "plant_00")
    assert block, "找不到 plant_00"
    add = []
    for name, eid, uid, cid, x, y, z in PLANTS:
        if 'name="%s"' % name in text:
            continue
        add.append(
            '[node name="%s" parent="." unique_id=%d instance=ExtResource("%s")]\n'
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\n'
            'metadata/authored_component_id = "%s"\n'
            'metadata/authored_slot_role = "room_type_component"\n\n'
            % (name, uid, eid, x, y, z, cid))
        print("+ node %s" % name)
    text = text[:block[1]] + "".join(add) + text[block[1]:]

    # 3) 门槽墙皮 -> 北墙空模位(含 direction 改北墙口径)
    for name, (old_t, new_t) in RELOCATE_SKIN.items():
        b = find_block(text, name)
        assert b, "找不到 %s" % name
        seg = text[b[0]:b[1]]
        assert old_t in seg, "%s 原 transform 不匹配" % name
        assert 'metadata/tower_wall_direction = "south"' in seg, "%s direction 非 south" % name
        seg = seg.replace(old_t, new_t).replace(
            'metadata/tower_wall_direction = "south"', 'metadata/tower_wall_direction = "west"')
        text = text[:b[0]] + seg + text[b[1]:]
        print("~ skin %s -> 北墙 (%s)" % (name, new_t.split(", ")[-2]))

    # 4) 机架让出门带
    for name, (old_t, new_t) in RELOCATE.items():
        b = find_block(text, name)
        assert b, "找不到 %s" % name
        seg = text[b[0]:b[1]]
        assert old_t in seg, "%s 平移不匹配" % name
        text = text[:b[0]] + seg.replace(old_t, new_t) + text[b[1]:]
        print("~ move %s  %s -> %s" % (name, old_t, new_t))

    # 5) 道具还原源位
    for name, (old_t, new_t) in REVERT.items():
        b = find_block(text, name)
        assert b, "找不到 %s" % name
        seg = text[b[0]:b[1]]
        assert old_t in seg, "%s 变换不匹配" % name
        text = text[:b[0]] + seg.replace(old_t, new_t) + text[b[1]:]
        print("~ revert %s" % name)

    assert "\r" not in text, "写入前发现 CR"
    open(TSCN, "w", encoding="utf-8", newline="").write(text)

    direct = len(re.findall(r'(?m)^\[node name="[^"]+"[^\]]*?\bparent="\."', text))
    inst = len(re.findall(r'(?m)^\[node name="[^"]+"[^\]]*?\bparent="\."[^\]]*instance=ExtResource', text))
    print("写入 %s | 直接子=%d 实例=%d" % (os.path.relpath(TSCN, REPO), direct, inst))


if __name__ == "__main__":
    main()
