"""Replace the workshop's dominant teal palette cell with structured cool-gray variety."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
import re
import sys
import zlib
from pathlib import Path

import bpy


SOURCE_CELL = (2, 4)
# UV rows map bottom-to-top; these correspond to #263242 .. #718195 in column 10.
TARGET_ROWS = (8, 7, 6, 5, 4, 3)


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glb", type=Path)
    parser.add_argument("--palette", required=True, type=Path)
    return parser.parse_args(values)


def palette_cell(mesh: bpy.types.Mesh, polygon: bpy.types.MeshPolygon) -> tuple[int, int]:
    layer = mesh.uv_layers["PaletteUV"]
    values = [layer.data[index].uv for index in polygon.loop_indices]
    u = sum(value.x for value in values) / len(values)
    v = sum(value.y for value in values) / len(values)
    return min(9, max(0, int(u * 10))), min(9, max(0, int(v * 10)))


def target_row(name: str) -> int:
    clean = re.sub(r"\.\d+$", "", name)
    if "WorkSurface" in clean:
        return 6  # #3F4F62，主体桌面
    if any(token in clean for token in ("WorkMatBorder", "SurfaceInlay", "CornerArmor", "FaceLayer")):
        return 4  # #5D6E82，亮一档的边框/嵌条
    if any(token in clean for token in ("Grid", "VentSlot", "Foot", "Seal")):
        return 8  # #263242，缝隙、脚架和暗部
    if any(token in clean for token in ("DrawerFace", "Door", "FrontPanel", "TrayWall", "SidePanel")):
        return 7  # #324052，次级面板
    if any(token in clean for token in ("Joint", "Pivot", "Ring", "Hub", "Canister")):
        return (5, 6, 7)[zlib.crc32(clean.encode("utf-8")) % 3]
    return TARGET_ROWS[zlib.crc32(clean.encode("utf-8")) % len(TARGET_ROWS)]


def remap_object(obj: bpy.types.Object) -> tuple[int, int | None]:
    mesh = obj.data
    layer = mesh.uv_layers.get("PaletteUV")
    if layer is None:
        return 0, None
    row = target_row(obj.name)
    changed = 0
    delta_u = (9 - SOURCE_CELL[0]) / 10.0
    delta_v = (row - SOURCE_CELL[1]) / 10.0
    for polygon in mesh.polygons:
        if palette_cell(mesh, polygon) != SOURCE_CELL:
            continue
        for loop_index in polygon.loop_indices:
            layer.data[loop_index].uv.x += delta_u
            layer.data[loop_index].uv.y += delta_v
        changed += 1
    if changed:
        mesh.uv_layers.active = layer
        layer.active_render = True
        mesh.update()
    return changed, row if changed else None


def remap_integrated_body(obj: bpy.types.Object) -> dict[int, int]:
    """Color disconnected joined components coherently, preserving the approved output geometry."""
    mesh = obj.data
    layer = mesh.uv_layers.get("PaletteUV")
    if layer is None:
        raise RuntimeError(f"{obj.name} 缺少 PaletteUV")
    candidates = {polygon.index for polygon in mesh.polygons if palette_cell(mesh, polygon) == SOURCE_CELL}
    vertex_faces: dict[int, list[int]] = defaultdict(list)
    for polygon_index in candidates:
        for vertex_index in mesh.polygons[polygon_index].vertices:
            vertex_faces[vertex_index].append(polygon_index)
    remaining = set(candidates)
    components: list[list[int]] = []
    while remaining:
        start = remaining.pop()
        queue = deque([start])
        component = [start]
        while queue:
            polygon_index = queue.popleft()
            for vertex_index in mesh.polygons[polygon_index].vertices:
                for neighbor in vertex_faces[vertex_index]:
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        queue.append(neighbor)
                        component.append(neighbor)
        components.append(component)
    components.sort(
        key=lambda indices: (
            -sum(mesh.polygons[index].area for index in indices),
            round(sum(mesh.polygons[index].center.z for index in indices) / len(indices), 4),
            round(sum(mesh.polygons[index].center.x for index in indices) / len(indices), 4),
        )
    )
    usage: dict[int, int] = {}
    for component_index, polygon_indices in enumerate(components):
        row = 6 if component_index == 0 else TARGET_ROWS[(component_index - 1) % len(TARGET_ROWS)]
        delta_u = (9 - SOURCE_CELL[0]) / 10.0
        delta_v = (row - SOURCE_CELL[1]) / 10.0
        for polygon_index in polygon_indices:
            polygon = mesh.polygons[polygon_index]
            for loop_index in polygon.loop_indices:
                layer.data[loop_index].uv.x += delta_u
                layer.data[loop_index].uv.y += delta_v
        usage[row] = usage.get(row, 0) + len(polygon_indices)
    mesh.uv_layers.active = layer
    layer.active_render = True
    mesh.update()
    return usage


def clear_collection(collection: bpy.types.Collection) -> None:
    for obj in list(collection.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def evaluated_copy(source: bpy.types.Object, collection: bpy.types.Collection, depsgraph) -> bpy.types.Object:
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    mesh.transform(source.matrix_world)
    copy = bpy.data.objects.new(source.name.removesuffix(".001"), mesh)
    collection.objects.link(copy)
    return copy


def remove_unused_material_slots(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.material_slot_remove_unused()


def is_emissive(material: bpy.types.Material | None) -> bool:
    return material is not None and (
        "自发光" in material.name or "UI灯光" in material.name or material.name.startswith("mat_emissive")
    )


def rebuild_output(source_objects: list[bpy.types.Object], output: bpy.types.Collection) -> list[bpy.types.Object]:
    clear_collection(output)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    copies = [evaluated_copy(obj, output, depsgraph) for obj in source_objects]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in copies:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "枪械工坊_主体_金属哑光反光"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for polygon in body.data.polygons:
        material = body.data.materials[polygon.material_index] if polygon.material_index < len(body.data.materials) else None
        polygon.select = is_emissive(material)
    before = set(output.objects)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    emissive = next((obj for obj in output.objects if obj not in before and obj != body), None)
    if emissive is not None:
        emissive.name = "枪械工坊_UI灯光_柔和自发光"
    remove_unused_material_slots(body)
    if emissive is not None:
        remove_unused_material_slots(emissive)
    output.hide_viewport = False
    output.hide_render = False
    return [obj for obj in (body, emissive) if obj is not None]


def pack_palette(path: Path) -> None:
    for image in bpy.data.images:
        if image.source != "FILE" or "色盘" not in image.name:
            continue
        image.filepath = str(path)
        image.reload()
        image.pack()


def export_glb(path: Path, objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=True
    )


def main() -> None:
    options = parse_args()
    bpy.context.preferences.filepaths.save_version = 0
    source = bpy.data.collections.get("01_制作组件_已统一材质")
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if source is None or output is None:
        raise RuntimeError("缺少标准源组件或游戏输出集合")
    source_objects = [obj for obj in source.all_objects if obj.type == "MESH"]
    usage: dict[int, int] = {}
    changed = 0
    for obj in source_objects:
        count, row = remap_object(obj)
        if row is not None:
            usage[row] = usage.get(row, 0) + count
            changed += count
    if changed == 0:
        raise RuntimeError("未找到需要替换的蓝绿色色格")
    output_objects = [obj for obj in output.all_objects if obj.type == "MESH"]
    body = next((obj for obj in output_objects if "主体" in obj.name), None)
    if body is None:
        raise RuntimeError("整合输出中缺少主体网格")
    output_usage = remap_integrated_body(body)
    source.hide_viewport = True
    source.hide_render = True
    pack_palette(options.palette)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    if options.glb:
        export_glb(options.glb, output_objects)
    print("WORKSHOP_COOL_GRAY_REMAP", changed, sorted(usage.items()), "OUTPUT", sorted(output_usage.items()))


if __name__ == "__main__":
    main()
