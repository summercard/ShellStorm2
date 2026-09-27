"""给 Boss 房组件库清单标注显式 component_family / variant_axis。

02 规则要求组件族必须显式声明（脚本按 slug 猜族名会被 `r05_c05` 这类
色盘格记号切成 80 个伪族）。本脚本按源包名的规则前缀映射到语义族，
再交给 02 的 plan_components.py 做族内收敛与 50 预算门禁。
"""

from __future__ import annotations

import json
from pathlib import Path

SOURCE = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components/v001/component_catalog.json"
)
OUT = Path("_scratch/boss_plan/annotated_catalog.json")

## (匹配片段, 族名, 变体轴) —— 顺序敏感，先匹配先生效。
RULES = (
    ("-BASE-FLOOR-BASE", "floor_base", ""),
    ("-BASE-FLOOR-TILE-", "floor_tile_5m", "structure_state"),
    ("-BASE-WALL-", "wall_base_5m", ""),
    ("-WALL-SKIN-", "wall_skin_5m", "damage_state"),
    ("-MAIN-FAULT-SCREEN", "main_fault_screen", ""),
    ("-NORTH-COMPLETE-", "north_facility", "damage_state"),
    ("-NORTH-DAMAGED-", "north_facility", "damage_state"),
    ("-UNDER-SCREEN-", "under_screen", "damage_state"),
    ("-EAST-COMPLETE-", "east_facility", "damage_state"),
    ("-EAST-DAMAGED-", "east_facility", "damage_state"),
    ("-WEST-COMPLETE-", "west_facility", "damage_state"),
    ("-WEST-DAMAGED-", "west_facility", "damage_state"),
    ("-WORKSTATION-", "workstation", ""),
    ("-CHAIR-", "chair", ""),
    ("-PLANT-", "plant", ""),
    ("-ARCHIVE-SHELF-", "archive_shelf", ""),
    ("-DEBRIS-", "debris", ""),
    ("-HEAVY-CONDUITS", "heavy_conduits", ""),
    ("-NORTH-WALL-TYPOGRAPHY", "north_wall_typography", ""),
    ("-SOUTH-FLOOR-MARKING", "south_floor_marking", ""),
)


def family_for(component_id: str) -> tuple[str, str]:
    for token, family, axis in RULES:
        if token in component_id:
            return family, axis
    return "", ""


def main() -> None:
    catalog = json.loads(SOURCE.read_text(encoding="utf-8"))
    unmapped: list[str] = []
    for package in catalog["packages"]:
        family, axis = family_for(str(package["component_id"]))
        if not family:
            unmapped.append(str(package["component_id"]))
            continue
        package["component_family"] = family
        if axis:
            package["variant_axis"] = axis
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("已标注家族:", len(catalog["packages"]) - len(unmapped), "/", len(catalog["packages"]))
    if unmapped:
        print("!! 未映射:")
        for component_id in unmapped:
            print("   ", component_id)


if __name__ == "__main__":
    main()
