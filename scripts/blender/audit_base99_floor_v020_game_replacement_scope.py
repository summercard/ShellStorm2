"""Read-only source audit for the full Base99 floor replacement export."""

from __future__ import annotations

import json
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT = PROJECT_ROOT / "outputs/verification/base99_floor_v020_game_replacement_scope.json"
FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
REUSED_BASE_MARKERS = ("保留地板", "普通地板_主体", "带铆钉地板_主体", "输出根节点")


def is_base(obj: bpy.types.Object) -> bool:
    return any(marker in obj.name for marker in REUSED_BASE_MARKERS)


def bounds_for(objects: list[bpy.types.Object]) -> dict[str, object]:
    low = [float("inf")] * 3
    high = [float("-inf")] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ type(obj.location)(corner)
            for axis in range(3):
                low[axis] = min(low[axis], world[axis])
                high[axis] = max(high[axis], world[axis])
    return {"min": [round(value, 6) for value in low], "max": [round(value, 6) for value in high]}


def main() -> None:
    collections = sorted(
        [collection for collection in bpy.data.collections if collection.name.startswith("地砖_R") and collection.name.endswith(FLOOR_COLLECTION_SUFFIX)],
        key=lambda collection: collection.name,
    )
    if len(collections) != 36:
        raise RuntimeError(f"Expected 36 floor packages, got {len(collections)}")
    bases: list[bpy.types.Object] = []
    details: list[bpy.types.Object] = []
    for collection in collections:
        for obj in collection.objects:
            if obj.type != "MESH":
                continue
            (bases if is_base(obj) else details).append(obj)
    payload = {
        "source_blend": bpy.data.filepath,
        "base_mesh_count": len(bases),
        "detail_mesh_count": len(details),
        "base_bounds": bounds_for(bases),
        "detail_bounds": bounds_for(details),
        "combined_bounds": bounds_for(bases + details),
        "plain_base_count": sum("普通地板_主体" in obj.name for obj in bases),
        "rivet_base_count": sum("带铆钉地板_主体" in obj.name for obj in bases),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_FLOOR_REPLACEMENT_SCOPE:{OUTPUT}")
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
