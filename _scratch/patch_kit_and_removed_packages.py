# -*- coding: utf-8 -*-
"""2026-09-20 收尾补丁。

背景：给安全房房间包内嵌 BoxShape3D 碰撞后，复用这些包当装饰的
`wall_floor_facility_kit` 跟着带上了碰撞，撞破了它自己「设施纯视觉」的旧断言。
本脚本：
  1) 把 kit 的声明改成与新事实一致（设施碰撞来自被复用 prefab），并升到 v002；
  2) 把 verify_battle_wall_floor_facility_kit 的硬编码「必须为 0」改成
     「声明值 == 实际启用形数」的一致性断言 + 防假绿哨兵；
  3) 顺手清掉仓库里最后两处「幽灵结构代理」残留（两个已移出安全房的包）。
字节级替换，逐文件按实际行尾（CRLF/LF）构造，不动其余任何字符。
"""
import io
import sys

EDITS = []


def add(path, pairs):
    EDITS.append((path, pairs))


# ---------------------------------------------------------------- 1. kit tscn
KIT_TSCN = ("assets/art/environments/tower_zones/battle/runtime/"
            "wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn")

add(KIT_TSCN, [
    ("; 结构组件保持独立：墙/地板各自负责视觉与结构契约；墙边设施为独立视觉包。\n"
     "; 装饰包不改变5m网格、12m逻辑墙高、导航或战斗碰撞。\n",
     "; 结构组件保持独立：墙/地板各自负责视觉与结构契约。\n"
     "; 墙边设施直接复用 v007 房间包，因此设施自带内嵌 BoxShape3D 碰撞（layer 1）——\n"
     "; 2026-09-20 起 kit 不再声明「设施纯视觉」；设施挡不挡一律以被复用 prefab 的\n"
     "; collision_shape_count 为准。墙/地板仍不改变 5m 网格与 12m 逻辑墙高。\n"),

    ('metadata/asset_version = "v001"\n',
     'metadata/asset_version = "v002"\n'),

    ('metadata/visual_only_facilities = true\n',
     'metadata/visual_only_facilities = false\n'),

    ('metadata/collision_policy = "walls_self;floor_host_owned;facilities_none"\n',
     'metadata/collision_policy = "walls_self;floor_host_owned;facilities_self_per_package"\n'),

    ('[node name="WallSideFacilities" type="Node3D" parent="."]\n'
     'metadata/visual_only = true\n'
     'metadata/collision_policy = "none_in_package"\n',
     '[node name="WallSideFacilities" type="Node3D" parent="."]\n'
     'metadata/visual_only = false\n'
     'metadata/collision_policy = "self_per_facility_package"\n'
     'metadata/collision_inheritance = "每个设施实例的碰撞来自被复用的 v007 房间包（内嵌 BoxShape3D, layer 1）；kit 自身不添加任何碰撞。"\n'),
])

# ------------------------------------------------------------ 2. kit manifest
KIT_JSON = ("assets/art/environments/tower_zones/battle/runtime/"
            "wall_floor_facility_kit/asset_manifest.json")

add(KIT_JSON, [
    ('"version": "v001",', '"version": "v002",'),
    ('"collision_policy": "walls_self;floor_host_owned;facilities_none",',
     '"collision_policy": "walls_self;floor_host_owned;facilities_self_per_package",'),
    ('"visual_only_facilities": true,',
     '"visual_only_facilities": false,\n'
     '  "facility_collision_note": "墙边设施复用 v007 房间包，碰撞随包自带（内嵌 BoxShape3D, layer 1）。2026-09-20 起 kit 不再声明设施纯视觉；设施挡不挡以被复用 prefab 的 collision_shape_count 为准。",'),
])

# ------------------------------------------------- 3. kit 验收脚本：硬编码 -> 一致性
KIT_GD = "tests/verification/verify_battle_wall_floor_facility_kit.gd"

OLD_GD = (
    '\tif not bool(facilities.get_meta("visual_only", false)):\n'
    '\t\t_fail("FACILITY_VISUAL_ONLY_MISSING")\n'
    '\t\treturn\n'
    '\tfor child in facilities.get_children():\n'
    '\t\tif child.get_meta("collision_shape_count", 0) != 0:\n'
    '\t\t\t_fail("FACILITY_COLLISION_NOT_ZERO:%s" % child.name)\n'
    '\t\t\treturn\n'
    '\troot.free()\n'
    '\tprint("BATTLE_WALL_FLOOR_FACILITY_KIT_OK walls=12 floors=9 facilities=3")\n'
    '\tcall_deferred("_finish", 0)\n'
)

NEW_GD = (
    '\t# 2026-09-20：kit 复用的 v007 房间包已按 v004 组件契约内嵌自身 BoxShape3D 碰撞，\n'
    '\t# 因此 kit 不能再声明「设施纯视觉」。改为断言「声明值 == 实际启用形数」的一致性，\n'
    '\t# 并强制至少一件真的会挡 —— 0 样本 / 全不挡都必须变红，否则等于静默退化成纯装饰。\n'
    '\tif bool(facilities.get_meta("visual_only", false)):\n'
    '\t\t_fail("FACILITY_VISUAL_ONLY_STILL_TRUE")\n'
    '\t\treturn\n'
    '\tvar checked := 0\n'
    '\tvar blocking := 0\n'
    '\tfor child in facilities.get_children():\n'
    '\t\tchecked += 1\n'
    '\t\tvar declared := int(child.get_meta("collision_shape_count", -1))\n'
    '\t\tif declared < 0:\n'
    '\t\t\t_fail("FACILITY_COLLISION_COUNT_MISSING:%s" % child.name)\n'
    '\t\t\treturn\n'
    '\t\tvar actual := _count_enabled_shapes(child)\n'
    '\t\tif declared != actual:\n'
    '\t\t\t_fail("FACILITY_COLLISION_MISMATCH:%s declared=%d actual=%d" % [child.name, declared, actual])\n'
    '\t\t\treturn\n'
    '\t\tif actual > 0:\n'
    '\t\t\tblocking += 1\n'
    '\tif checked != 3:\n'
    '\t\t_fail("FACILITY_SAMPLE_MISSING checked=%d" % checked)\n'
    '\t\treturn\n'
    '\tif blocking == 0:\n'
    '\t\t_fail("FACILITY_NONE_BLOCKING checked=%d" % checked)\n'
    '\t\treturn\n'
    '\troot.free()\n'
    '\tprint("BATTLE_WALL_FLOOR_FACILITY_KIT_OK walls=12 floors=9 facilities=3 blocking=%d" % blocking)\n'
    '\tcall_deferred("_finish", 0)\n'
    '\n'
    'func _count_enabled_shapes(node: Node) -> int:\n'
    '\tvar count := 0\n'
    '\tif node is StaticBody3D:\n'
    '\t\tfor shape_holder in node.get_children():\n'
    '\t\t\tif shape_holder is CollisionShape3D and not shape_holder.disabled and shape_holder.shape != null:\n'
    '\t\t\t\tcount += 1\n'
    '\tfor descendant in node.get_children():\n'
    '\t\tcount += _count_enabled_shapes(descendant)\n'
    '\treturn count\n'
)

add(KIT_GD, [(OLD_GD, NEW_GD)])

# ------------------------------------------- 4. 清掉最后两处「幽灵结构代理」残留
for slug, zh in (("central_terminal_island", "中央四屏终端岛"),
                 ("west_glass_office", "西北玻璃办公室")):
    rt = ("assets/art/environments/tower_zones/battle/runtime/"
          "entry_safe_room/%s/%s_root_top3d.tscn" % (slug, slug))
    add(rt, [
        ("; 本包不含碰撞——玩法阻挡由引擎 0.30m 结构代理持有（见 asset_manifest.json 的\n"
         "; structural_geometry / collision_status / replacement_contract）。视觉资产不注册玩法组。\n",
         "; 本包不含碰撞，也不依赖任何外部结构代理（早期文档所称「引擎 0.30m 结构代理」从未实现）。\n"
         "; 2026-09-20：本包已移出安全房运行时消费（见 DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS），\n"
         "; 仅保留在库中备用；视觉资产不注册玩法组。\n"),
        ('metadata/collision_owner = "godot_0p30m_structural_proxy"\n'
         'metadata/collision_policy = "none_in_package"\n',
         'metadata/collision_owner = "none"\n'
         'metadata/collision_policy = "no_blocking_by_design"\n'
         'metadata/collision_exclusion_reason = "无内嵌碰撞，且已移出安全房运行时消费；不注册玩法组。"\n'),
    ])

    mf = ("assets/art/environments/tower_zones/battle/source/room_instances/"
          "entry_safe_room/v007/component_packages_v007/facilities/%s/asset_manifest.json" % slug)
    add(mf, [
        ('"collision_status": "未制作；玩法碰撞由 Godot 0.30m 结构代理负责"',
         '"collision_status": "no_blocking_by_design：无内嵌碰撞；早期文档所称 Godot 0.30m 结构代理从未实现。2026-09-20 起该包已移出安全房运行时消费，仅留在库中备用。"'),
    ])


def main():
    problems = []
    for path, pairs in EDITS:
        with open(path, "rb") as fh:
            data = fh.read()
        eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
        original = data
        for old, new in pairs:
            ob = old.replace("\n", "\n").encode("utf-8")
            nb = new.encode("utf-8")
            ob = ob.replace(b"\n", eol)
            nb = nb.replace(b"\n", eol)
            if data.count(ob) != 1:
                problems.append("%s: 命中 %d 次 -> %s" % (path, data.count(ob), old[:60]))
                continue
            data = data.replace(ob, nb)
        if data != original:
            with open(path, "wb") as fh:
                fh.write(data)
            print("PATCHED  %s  (%s)" % (path, "CRLF" if eol == b"\r\n" else "LF"))
        else:
            print("UNCHANGED %s" % path)
    if problems:
        print("\n!! 未命中/多命中：")
        for p in problems:
            print("   " + p)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
