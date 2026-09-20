"""入口安全房 v007 房间包：补齐玩法阻挡（内嵌 BoxShape3D）。

背景：17 个房间包的 metadata 声明 `collision_owner = "godot_0p30m_structural_proxy"`、
`collision_policy = "none_in_package"`，但**全仓不存在该代理的任何实现**（grep 无命中）。
结果：设施全部可以穿模。本脚本按范例 B（模型 + 碰撞同包）补齐，写法逐字对齐
v004 通用组件 wall_standard_5m / floor_tile_5m / wall_door_5m。

规则（与姐妹件一致，可断言）：
  BoxShape3D.size        == metadata/bounds_size_m
  CollisionShape3D.pos   == Vector3(0, bounds_size_m.y / 2, 0)   # 原点 = 底面中心
  StaticBody3D           : collision_layer = 1, collision_mask = 0

按几何分类，不是一刀切：
  阻挡  = 落地/够得着的实体家具（碰撞盒底面 y 距走行面 < 0.10m 且高度穿进玩家身位）
  不阻挡 = ① 承重归 TowerFloorStage3D 的底板；② 底部高于玩家（1.5m）的悬空件；
           ③ 17mm 地面贴花
"""

import re
import sys
from pathlib import Path

ROOT = Path("assets/art/environments/tower_zones/battle/runtime/entry_safe_room")

# slug -> (是否阻挡, 不阻挡原因)
CLASSIFY: dict[str, tuple[bool, str]] = {
    "floor_base": (False, "承重底板，碰撞归 TowerFloorStage3D._build_support()，包内不持有"),
    "overhead_services": (False, "顶部管线灯带，底部离走行面 3.60m，玩家 1.5m 够不着"),
    "debris_papers": (False, "17mm 地面散落贴花，属地面装饰不属障碍"),
    "north_nexus_sign": (False, "北墙标识，底部离走行面 6.28m，超出玩家身位"),
    "north_server_00": (True, ""),
    "north_server_01": (True, ""),
    "north_server_02": (True, ""),
    "north_server_03": (True, ""),
    "north_server_04": (True, ""),
    "north_server_05": (True, ""),
    "north_broken_core": (True, ""),
    "east_repair_bay": (True, ""),
    "east_robot_arm": (True, ""),
    "office_planter": (True, ""),
    "maintenance_chair": (True, ""),
}

OLD_HEADER = (
    "; 范式 B：视觉 GLB + 稳定根；房间摆位与契约写在 metadata。\r\n"
    "; 本包不含碰撞——玩法阻挡由引擎 0.30m 结构代理持有（见 asset_manifest.json 的\r\n"
    "; structural_geometry / collision_status / replacement_contract）。视觉资产不注册玩法组。\r\n"
)

NEW_HEADER_BLOCKING = (
    "; 范式 B（自包含可替换组件）：视觉 GLB + 稳定根 + 内嵌玩法阻挡，逐实例化。\r\n"
    "; 2026-09-20 补齐阻挡：旧注释声称碰撞「由引擎 0.30m 结构代理持有」，\r\n"
    "; 但该代理全仓无实现 → 设施可穿模。现改为与 v004 通用组件同款内嵌写法：\r\n"
    ";   BoxShape3D.size = metadata/bounds_size_m；原点 = 底面中心 → 盒中心 y = +height/2；\r\n"
    ";   StaticBody3D collision_layer = 1（与墙/门墙/地砖同层）、collision_mask = 0。\r\n"
    "; 视觉几何仍可整体替换，但替换件必须保持 bounds_size_m 与同名碰撞盒，阻挡才不变。\r\n"
)

NEW_HEADER_EXCLUDED = (
    "; 范式 B：视觉 GLB + 稳定根；房间摆位与契约写在 metadata。\r\n"
    "; 2026-09-20 复核：本包**按设计不含玩法阻挡**（原因见 metadata/collision_exclusion_reason），\r\n"
    "; 不是漏做。旧注释「碰撞由引擎 0.30m 结构代理持有」不成立——全仓并无该代理实现。\r\n"
)

OLD_REPLACE_CONTRACT = (
    'metadata/replacement_contract = "decoration only; must not change room size, '
    '5m grid, collision layer or navigation"\r\n'
)
NEW_REPLACE_CONTRACT_BLOCKING = (
    'metadata/replacement_contract = "replaceable visual + embedded player blocker; '
    'a replacement must keep bounds_size_m, the BoxShape3D size and collision_layer 1 '
    'so blocking is unchanged; must not change room size, 5m grid or navigation"\r\n'
)

FLOOR_BASE_OLD_TAIL = " Godot keeps the 0.30 structural collision proxy."
FLOOR_BASE_NEW_TAIL = (
    " Player blocking for this package is external: TowerFloorStage3D._build_support() owns it;"
    " the package itself carries no shape."
)


def fmt(value: float) -> str:
    """与 .tscn 既有写法一致：整数不带小数位，其余去掉尾随零。"""
    if value == int(value):
        return str(int(value))
    text = ("%.6f" % value).rstrip("0").rstrip(".")
    return text


def patch(path: Path, slug: str, blocking: bool, reason: str) -> str:
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    crlf = "\r\n" in text
    if not crlf:
        return "SKIP(非 CRLF)"

    m = re.search(r"metadata/bounds_size_m = Vector3\(([\d., -]+)\)\r\n", text)
    if not m:
        return "SKIP(找不到 bounds_size_m)"
    size_literal = m.group(1)
    dims = [float(v) for v in size_literal.split(",")]
    if len(dims) != 3:
        return "SKIP(bounds_size_m 非三维)"

    root = re.search(r'\[node name="(\w+)" type="Node3D"\]\r\n', text)
    if not root:
        return "SKIP(找不到根节点)"
    body_name = "%sCollision" % re.sub(r"^Esr", "", root.group(1))

    note = (
        'metadata/collision_structure_note = "内嵌 BoxShape3D；尺寸 = bounds_size_m；'
        '原点 = 包围盒底面中心，故 shape.position.y = height/2。层次与 v004 通用组件一致。"\r\n'
    )

    if blocking:
        if 'type="StaticBody3D"' in text:
            return "SKIP(已有碰撞体)"
        text = text.replace("[gd_scene load_steps=2 format=3]", "[gd_scene load_steps=3 format=3]", 1)
        text = text.replace(OLD_HEADER, NEW_HEADER_BLOCKING, 1)

        ext = re.search(r"\[ext_resource [^\]]+\]\r\n", text)
        sub = (
            '\r\n[sub_resource type="BoxShape3D" id="BoxShape3D_%s_1"]\r\n'
            "size = Vector3(%s)\r\n" % (slug, size_literal)
        )
        text = text[: ext.end()] + sub + text[ext.end():]

        text = text.replace("metadata/visual_only = true\r\n", "metadata/visual_only = false\r\n", 1)
        text = text.replace(
            'metadata/collision_owner = "godot_0p30m_structural_proxy"\r\n',
            'metadata/collision_owner = "self"\r\n',
            1,
        )
        text = text.replace(
            'metadata/collision_policy = "none_in_package"\r\n',
            'metadata/collision_policy = "embedded_box_bottom_center"\r\n',
            1,
        )
        text = text.replace(
            "metadata/collision_shape_count = 0\r\n",
            "metadata/collision_shape_count = 1\r\n",
            1,
        )
        text = text.replace("metadata/runtime_instantiation", note + "metadata/runtime_instantiation", 1)
        text = text.replace(OLD_REPLACE_CONTRACT, NEW_REPLACE_CONTRACT_BLOCKING, 1)

        text = text.rstrip("\r\n") + (
            "\r\n\r\n[node name=\"%s\" type=\"StaticBody3D\" parent=\".\"]\r\n"
            "collision_layer = 1\r\n"
            "collision_mask = 0\r\n"
            "\r\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"%s\"]\r\n"
            "position = Vector3(0, %s, 0)\r\n"
            'shape = SubResource("BoxShape3D_%s_1")\r\n'
            % (body_name, body_name, fmt(dims[1] / 2.0), slug)
        )
        path.write_bytes(text.encode("utf-8"))
        return "BLOCK  size=(%s)  shape_y=%s  body=%s" % (size_literal, fmt(dims[1] / 2.0), body_name)

    # —— 不阻挡：只订正契约文字，不加碰撞
    if reason.startswith("承重底板"):
        owner = "TowerFloorStage3D._build_support"
        policy = "external_owner_no_shape_in_package"
    else:
        owner = "none"
        policy = "no_blocking_by_design"
    text = text.replace(OLD_HEADER, NEW_HEADER_EXCLUDED, 1)
    text = text.replace(
        'metadata/collision_owner = "godot_0p30m_structural_proxy"\r\n',
        'metadata/collision_owner = "%s"\r\n' % owner,
        1,
    )
    text = text.replace(
        'metadata/collision_policy = "none_in_package"\r\n',
        'metadata/collision_policy = "%s"\r\n' % policy,
        1,
    )
    text = text.replace(
        "metadata/collision_shape_count = 0\r\n",
        'metadata/collision_shape_count = 0\r\n'
        'metadata/collision_exclusion_reason = "%s"\r\n' % reason,
        1,
    )
    text = text.replace(FLOOR_BASE_OLD_TAIL, FLOOR_BASE_NEW_TAIL, 1)
    path.write_bytes(text.encode("utf-8"))
    return "EXCLUDE  owner=%s  policy=%s" % (owner, policy)


def main() -> int:
    seen = set()
    changed = 0
    for slug, (blocking, reason) in CLASSIFY.items():
        path = ROOT / slug / ("%s_root_top3d.tscn" % slug)
        if not path.exists():
            print("%-24s MISSING %s" % (slug, path))
            return 1
        seen.add(slug)
        print("%-24s %s" % (slug, patch(path, slug, blocking, reason)))
        changed += 1
    print("\n处理 %d 件（阻挡 %d / 不阻挡 %d）" % (
        changed,
        sum(1 for b, _ in CLASSIFY.values() if b),
        sum(1 for b, _ in CLASSIFY.values() if not b),
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
