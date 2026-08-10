"""Export the approved 5 m proportional facility revisions to Godot.

Only the locker station and retro TV station are touched.  The vending machine
and the already integrated interactive desks remain unchanged.
"""

from __future__ import annotations

import json
import math
import shutil
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from export_game_assets import (  # noqa: E402
    PROJECT,
    PROP_ROOT,
    duplicate_mesh,
    export_glb,
    godot_bounds,
    reset_to,
)
from generate_runtime_scenes import write_facility  # noqa: E402


LIBRARY = Path(r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3")
MANIFEST_PATH = PROJECT / "assets/art/asset_import_manifest_v001.json"

ASSETS = (
    {
        "slug": "locker_station",
        "cn": "赛博储物站",
        "source": "01_赛博储物站_体量强化源文件_v002.blend",
    },
    {
        "slug": "retro_tv_station",
        "cn": "复古游戏电视站",
        "source": "03_复古游戏电视站_体量强化源文件_v002.blend",
    },
)


def triangulate_export_copy(obj: bpy.types.Object) -> None:
    mesh = obj.data
    editable = bmesh.new()
    editable.from_mesh(mesh)
    bmesh.ops.triangulate(editable, faces=list(editable.faces))
    editable.to_mesh(mesh)
    editable.free()
    mesh.update()


def export_asset(data: dict, manifest: dict) -> None:
    source_file = LIBRARY / data["source"]
    bpy.ops.wm.open_mainfile(filepath=str(source_file))
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if output is None:
        raise RuntimeError(f"{source_file.name} 缺少游戏输出集合")
    sources = [obj for obj in output.objects if obj.type == "MESH"]
    if not sources:
        raise RuntimeError(f"{source_file.name} 没有游戏输出网格")

    # The v002 Blender files already author the final 5 m module size.  Keep a
    # 1:1 scale and only apply the established facility forward-axis rotation.
    axis_transform = Matrix.Rotation(math.pi, 4, "Z")
    copies = []
    for source in sources:
        is_emissive = "自发光" in source.name or "UI灯光" in source.name
        copy = duplicate_mesh(source, "Emissive" if is_emissive else "Body", is_emissive)
        copy.data.transform(axis_transform @ source.matrix_world)
        triangulate_export_copy(copy)
        copies.append(copy)
    reset_to(copies)

    source_dir = PROP_ROOT / "source" / data["slug"]
    component_dir = PROP_ROOT / "components" / data["slug"]
    source_dir.mkdir(parents=True, exist_ok=True)
    component_dir.mkdir(parents=True, exist_ok=True)
    project_source = source_dir / f"prp_base_{data['slug']}_source_v002.blend"
    glb_path = component_dir / f"prp_base_{data['slug']}_visual_top3d_v002.glb"
    shutil.copy2(source_file, project_source)
    export_glb(glb_path, copies)

    mins, maxs = zip(*(godot_bounds(obj) for obj in copies))
    bound_min = [min(value[index] for value in mins) for index in range(3)]
    bound_max = [max(value[index] for value in maxs) for index in range(3)]
    manifest["facilities"][data["slug"]] = {
        "name_cn": data["cn"],
        "glb": glb_path.relative_to(PROJECT).as_posix(),
        "source": project_source.relative_to(PROJECT).as_posix(),
        "bounds_min": bound_min,
        "bounds_max": bound_max,
        "presentation_scale_multiplier": 1.0,
        "authoring_target_width_m": 5.0,
        "revision_note": "整体等比例5米宽模数；保持附件与主体原始比例",
    }
    print(
        "EXPORTED",
        data["slug"],
        "BOUNDS",
        tuple(round(value, 4) for value in bound_min),
        tuple(round(value, 4) for value in bound_max),
    )


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    for data in ASSETS:
        export_asset(data, manifest)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    for data in ASSETS:
        write_facility(data["slug"], manifest["facilities"][data["slug"]])
    print("UPDATED MANIFEST AND TWO RUNTIME WRAPPERS")


if __name__ == "__main__":
    main()
