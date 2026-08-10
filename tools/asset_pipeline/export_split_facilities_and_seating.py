"""Replace embedded-chair facilities and export both chairs as decor props."""

from __future__ import annotations

import bmesh
import json
import math
import shutil
import sys
from pathlib import Path

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

FACILITIES = (
    {
        "slug": "weapon_workshop",
        "cn": "赛博维修工作台",
        "source": "02_赛博维修工作台_体量强化源文件_v002.blend",
        "version": "v003",
    },
    {
        "slug": "mission_operations",
        "cn": "战术情报指挥桌",
        "source": "04_战术指挥桌_体量强化源文件_v002.blend",
        "version": "v003",
    },
)

SEATING = (
    {
        "slug": "workshop_stool",
        "cn": "赛博维修圆凳",
        "source": "07_赛博维修圆凳_独立源文件_v001.blend",
        "version": "v001",
    },
    {
        "slug": "mission_command_chair",
        "cn": "战术指挥椅",
        "source": "08_战术指挥椅_独立源文件_v001.blend",
        "version": "v001",
    },
)


def triangulate(obj: bpy.types.Object) -> None:
    editable = bmesh.new()
    editable.from_mesh(obj.data)
    bmesh.ops.triangulate(editable, faces=list(editable.faces))
    editable.to_mesh(obj.data)
    editable.free()
    obj.data.update()


def prepare_export(source_file: Path) -> list[bpy.types.Object]:
    bpy.ops.wm.open_mainfile(filepath=str(source_file))
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if output is None:
        raise RuntimeError(f"{source_file.name} 缺少 02_游戏输出_整合模型")
    sources = [obj for obj in output.objects if obj.type == "MESH"]
    if not sources:
        raise RuntimeError(f"{source_file.name} 没有游戏输出网格")
    axis_transform = Matrix.Rotation(math.pi, 4, "Z")
    copies = []
    for source in sources:
        is_emissive = "自发光" in source.name or "UI灯光" in source.name
        copy = duplicate_mesh(source, "Emissive" if is_emissive else "Body", is_emissive)
        copy.data.transform(axis_transform @ source.matrix_world)
        triangulate(copy)
        copies.append(copy)
    reset_to(copies)
    return copies


def calculate_bounds(objects: list[bpy.types.Object]) -> tuple[list[float], list[float]]:
    mins, maxs = zip(*(godot_bounds(obj) for obj in objects))
    minimum = [min(value[index] for value in mins) for index in range(3)]
    maximum = [max(value[index] for value in maxs) for index in range(3)]
    return minimum, maximum


def export_facility(data: dict, manifest: dict) -> None:
    source_file = LIBRARY / data["source"]
    copies = prepare_export(source_file)
    source_dir = PROP_ROOT / "source" / data["slug"]
    component_dir = PROP_ROOT / "components" / data["slug"]
    source_dir.mkdir(parents=True, exist_ok=True)
    component_dir.mkdir(parents=True, exist_ok=True)
    project_source = source_dir / f"prp_base_{data['slug']}_source_{data['version']}.blend"
    glb_path = component_dir / f"prp_base_{data['slug']}_visual_top3d_{data['version']}.glb"
    shutil.copy2(source_file, project_source)
    export_glb(glb_path, copies)
    minimum, maximum = calculate_bounds(copies)
    manifest["facilities"][data["slug"]] = {
        "name_cn": data["cn"],
        "glb": glb_path.relative_to(PROJECT).as_posix(),
        "source": project_source.relative_to(PROJECT).as_posix(),
        "bounds_min": minimum,
        "bounds_max": maximum,
        "presentation_scale_multiplier": 1.0,
        "authoring_target_width_m": 5.0,
        "chair_embedded": False,
        "revision_note": "体量强化设施主体；座椅已拆为独立装饰资产",
    }
    print("EXPORTED FACILITY", data["slug"], minimum, maximum)


def write_decor_scene(data: dict, record: dict) -> None:
    runtime_dir = PROP_ROOT / "runtime" / data["slug"]
    runtime_dir.mkdir(parents=True, exist_ok=True)
    scene_path = runtime_dir / f"prp_base_{data['slug']}_root_top3d_{data['version']}.tscn"
    scene_path.write_text(
        f'''[gd_scene load_steps=2 format=3]\n\n'''
        f'''[ext_resource type="PackedScene" path="res://{record['glb']}" id="1_visual"]\n\n'''
        f'''[node name="{data['cn']}" type="Node3D"]\n'''
        f'''metadata/asset_name_cn = "{data['cn']}"\n'''
        f'''metadata/asset_category = "decor_prop"\n'''
        f'''metadata/asset_source = "res://{record['source']}"\n'''
        f'''metadata/forward_axis = "-Z"\n'''
        f'''metadata/interactive = false\n\n'''
        f'''[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]\n''',
        encoding="utf-8",
    )


def export_seating(data: dict, manifest: dict) -> None:
    source_file = LIBRARY / data["source"]
    copies = prepare_export(source_file)
    source_dir = PROP_ROOT / "source" / data["slug"]
    component_dir = PROP_ROOT / "components" / data["slug"]
    source_dir.mkdir(parents=True, exist_ok=True)
    component_dir.mkdir(parents=True, exist_ok=True)
    project_source = source_dir / f"prp_base_{data['slug']}_source_{data['version']}.blend"
    glb_path = component_dir / f"prp_base_{data['slug']}_visual_top3d_{data['version']}.glb"
    shutil.copy2(source_file, project_source)
    export_glb(glb_path, copies)
    minimum, maximum = calculate_bounds(copies)
    record = {
        "name_cn": data["cn"],
        "category": "decor_prop",
        "glb": glb_path.relative_to(PROJECT).as_posix(),
        "source": project_source.relative_to(PROJECT).as_posix(),
        "runtime": (
            PROP_ROOT / "runtime" / data["slug"]
            / f"prp_base_{data['slug']}_root_top3d_{data['version']}.tscn"
        ).relative_to(PROJECT).as_posix(),
        "bounds_min": minimum,
        "bounds_max": maximum,
        "presentation_scale_multiplier": 1.0,
        "interactive": False,
        "standalone": True,
    }
    manifest.setdefault("decor_props", {})[data["slug"]] = record
    write_decor_scene(data, record)
    print("EXPORTED DECOR", data["slug"], minimum, maximum)


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    for data in FACILITIES:
        export_facility(data, manifest)
    for data in SEATING:
        export_seating(data, manifest)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    for data in FACILITIES:
        write_facility(data["slug"], manifest["facilities"][data["slug"]])
    print("UPDATED MANIFEST, FACILITY WRAPPERS, AND STANDALONE SEATING SCENES")


if __name__ == "__main__":
    main()
