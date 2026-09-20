"""订正 15 份 asset_manifest.json 里名不副实的碰撞字段。

原文写的是：
  "structural_geometry": "none: no wall/floor module, no collision shape"
  "collision_status":   "未制作；玩法碰撞由 Godot 0.30m 结构代理负责"
但那个「Godot 0.30m 结构代理」全仓并不存在，设施因此可穿模。2026-09-20 已把阻挡
改成运行时 prefab 内嵌 BoxShape3D。这里同步源清单的说法。

只做**逐行值替换**，不整体 re-dump：保证除目标两行外一个字节都不动。
"""

import re
import sys
from pathlib import Path

BASE = Path(
    "assets/art/environments/tower_zones/battle/source/room_instances/"
    "entry_safe_room/v007/component_packages_v007"
)

BLOCKING = {
    "north_server_00", "north_server_01", "north_server_02", "north_server_03",
    "north_server_04", "north_server_05", "north_broken_core", "east_repair_bay",
    "east_robot_arm", "office_planter", "maintenance_chair",
}
EXCLUDED_REASON = {
    "floor_base": "不适用：玩法阻挡归 TowerFloorStage3D._build_support()，包内不持有碰撞",
    "overhead_services": "按设计不阻挡：顶部管线灯带，底部离走行面 3.60m，玩家 1.5m 够不着",
    "debris_papers": "按设计不阻挡：17mm 地面散落贴花，属地面装饰不属障碍",
    "north_nexus_sign": "按设计不阻挡：北墙标识，底部离走行面 6.28m，超出玩家身位",
}

STRUCT_BLOCKING = (
    "none: no wall/floor module; player blocking is an embedded BoxShape3D in the "
    "runtime prefab, sized from bounds_size_m with the bottom-centre origin"
)
COLLISION_BLOCKING = (
    "已补（2026-09-20）：运行时 prefab 内嵌 BoxShape3D（layer 1，尺寸 = bounds_size_m）。"
    "旧的「Godot 0.30m 结构代理」全仓无实现，设施当时全部可穿模"
)


def patch_line(text: str, key: str, value: str) -> tuple[str, bool]:
    pattern = re.compile(r'^(  "%s": )"[^"]*"(,?)$' % re.escape(key), re.MULTILINE)
    new, count = pattern.subn(lambda m: '%s"%s"%s' % (m.group(1), value, m.group(2)), text)
    return new, count == 1


def main() -> int:
    changed = 0
    for path in sorted(BASE.rglob("asset_manifest.json")):
        slug = path.parent.name
        if slug not in BLOCKING and slug not in EXCLUDED_REASON:
            continue
        text = path.read_text(encoding="utf-8")
        if slug in BLOCKING:
            struct_value = STRUCT_BLOCKING
            coll_value = COLLISION_BLOCKING
        else:
            struct_value = None
            coll_value = EXCLUDED_REASON[slug]
        if struct_value is None:
            ok_struct = True
        else:
            text, ok_struct = patch_line(text, "structural_geometry", struct_value)
        text, ok_coll = patch_line(text, "collision_status", coll_value)
        if not (ok_struct and ok_coll):
            print("!! %-22s 行替换失败 (struct=%s coll=%s)" % (slug, ok_struct, ok_coll))
            return 1
        path.write_text(text, encoding="utf-8")
        changed += 1
        print("%-22s %s" % (slug, "阻挡" if slug in BLOCKING else "不阻挡"))
    print("\n订正 %d 份清单" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
