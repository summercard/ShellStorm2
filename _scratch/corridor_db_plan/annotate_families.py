"""给走廊(l_corridor v002 库) / 数据库房(db v013 库)标注显式 component_family / variant_axis。

02 规则：族必须显式声明（按 slug 猜族会被 `TILE_R00_C06` 这类格号切成几十个伪族）。
本脚本按源包名的语义片段映射到族；墙件再按几何高度区分结构状态变体。

走廊走旧库 v002（121 包，源＝`l_corridor/v003`）；数据库房按业主裁定改用房间种类源
**v002** 重新拆解出的旧库 **v013**（86 包）—— 历史上那套 v003 只 37 包、源是 db 源 v001，
包集合与现源不一致，不可复用。

产出：_scratch/corridor_db_plan/<room>/plan_input/component_catalog.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path("I:/工作项目/shellstrom2/ShellStorm2")
SRC = ROOT / "assets/art/environments/tower_zones/expedition/source/common_components"
WORK = ROOT / "_scratch/corridor_db_plan"

# ---------------------------------------------------------------- 走廊规则
CORRIDOR_RULES = (
    ("-CUTAWAY_WALL_CONTRACT_", "cutaway_reference", ""),
    ("-WALL_X_", "wall_5m", "structure_state"),
    ("-WALL_Y_", "wall_5m", "structure_state"),
    ("-WALL_LABEL_", "wall_label", ""),
    ("-TILE_R", "floor_tile_5m", ""),
    ("-SERVER_GALLERY", "server_gallery", ""),
    ("-SERVER_", "server_rack", ""),
    ("-SERVICE_CART_", "service_cart", ""),
    ("-CONSOLE_", "access_console", ""),
    ("-CRATE_", "crate", ""),
    ("-PLANTER_", "planter", ""),
    ("-HIGH_PIPE_", "high_pipe", ""),
    ("-PIPE_RISER_", "pipe_riser", ""),
    ("-HANGING_CABLE_", "hanging_cable", ""),
)

# 数据库房：按业主裁定改用**房间种类源 v002 重新拆解**出的旧库 v013（86 包）。
# 规则**按 v013 的 component_id 前缀写**（`ENV-EXPEDITION-L01-DB-<SLUG 大写>`）；
# 命中是「前缀包含」且**首个命中生效**，故更具体的 token 必须排在更泛的前面
# （例：`-REAR_SERVER_BUS` 必须早于 `-REAR_SERVER_`，否则母排被并进机柜族）。
DB_RULES = (
    ("-CEILING_DECK_", "ceiling_deck", ""),
    ("-CEILING_LIGHTING", "ceiling_lighting", ""),
    ("-CEILING_RING_BEAM", "ceiling_ring_beam", ""),
    ("-CEILING_SERVICE_", "ceiling_service", ""),
    ("-DERIVED_TILE_", "floor_tile_5m", ""),
    ("-FLOOR_CONDUIT_RUN", "floor_detail", ""),
    ("-FLOOR_HAZARD_EDGING", "floor_detail", ""),
    ("-REAR_SERVER_BUS", "server_bus", ""),
    ("-REAR_SERVER_", "server_rack", ""),
    ("-REAR_SERVICE_CART_", "service_cart", ""),
    ("-ISLAND_CART_", "island_cart", ""),
    ("-CENTER_DOUBLE_SIDED_REPAIR_ISLAND", "repair_island", ""),
    ("-RAISED_SERVICE_GANTRY", "raised_service", ""),
    ("-RAISED_SERVICE_PLATFORM", "raised_service", ""),
    ("-RIGHT_FRONT_CABLE_REEL_", "cable_reel", ""),
    ("-RIGHT_FRONT_SERVICE_TERMINAL", "service_terminal", ""),
    ("-RIGHT_FRONT_SHELF_", "shelf", ""),
    ("-WORKBENCH_L_EAST", "workbench", ""),
    ("-WORKBENCH_WEST", "workbench", ""),
    ("-CABLE_COIL_WALL", "cable_coil", ""),
    ("-CORNER_GUARD", "corner_guard", ""),
    ("-EQUIPMENT_RACK_NE", "equipment_rack", ""),
    ("-SHELVING_HEAVY_NORTH", "shelving", ""),
    ("-WALL_LIGHT_PYLON", "wall_light_pylon", ""),
    ("-WALL_SCREEN_BANK", "wall_screen", ""),
    ("-WALL_SERVICE_RUN", "wall_service", ""),
    ("-WALL_TOP_SERVICE", "wall_top_service", ""),
)

WALL_TALL_Z_M = 10.0


def match(component_id: str, rules) -> tuple[str, str]:
    for token, family, axis in rules:
        if token in component_id:
            return family, axis
    return "", ""


def annotate(room: str, lib_version: str, rules) -> int:
    src_catalog = SRC / lib_version / "component_catalog.json"
    catalog = json.loads(src_catalog.read_text(encoding="utf-8"))
    packages = catalog["packages"]
    unmapped: list[str] = []
    for package in packages:
        cid = str(package["component_id"])
        family, axis = match(cid, rules)
        if not family:
            unmapped.append(cid)
            continue
        package["component_family"] = family
        package["variant_axis"] = ""
        package["variant_value"] = ""
        package["variant_reason"] = ""
        if family == "wall_5m":
            z = float((package.get("bounds_size_m") or [0, 0, 0])[2])
            if z >= WALL_TALL_Z_M:
                package["variant_axis"] = "structure_state"
                package["variant_value"] = "standard"
                package["variant_reason"] = "全高 11.90m 结构墙（本关房间外壳）"
            else:
                package["variant_axis"] = "structure_state"
                package["variant_value"] = "cutaway_low"
                package["variant_reason"] = (
                    "源为出图剖切把该边压低至 %.2fm；owner 裁定保留为独立变体，不并回全高墙" % z
                )
        elif axis:
            package["variant_axis"] = axis

    out_dir = WORK / room / "plan_input"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "component_catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("[%s] %s 包 %d ｜ 已标注 %d ｜ 未映射 %d" % (
        room, lib_version, len(packages), len(packages) - len(unmapped), len(unmapped)))
    for cid in unmapped:
        print("   !! 未映射:", cid)
    return len(unmapped)


def main() -> int:
    bad = 0
    bad += annotate("corridor", "v002", CORRIDOR_RULES)
    bad += annotate("db", "v013", DB_RULES)
    print("ANNOTATE_%s" % ("OK" if not bad else "UNMAPPED"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
