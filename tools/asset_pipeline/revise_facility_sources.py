"""Apply the approved low-luminance facility art pass to the V3 Blender sources."""

from __future__ import annotations

from pathlib import Path

import bpy
import bmesh


LIBRARY = Path(r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3")
PALETTE_SOURCE = LIBRARY / "多巴胺色盘_10x10_512.png"
PALETTE_TARGET = LIBRARY / "设施低亮多巴胺色盘_10x10_512.png"
FACILITY_FILES = sorted(LIBRARY.glob("0[1-5]_*_风格统一源文件.blend"))
GUIDE_NAMES = {"GUIDE_1m_Cube", "GUIDE_1m_Cube.001", "Cube", "Cube.001"}


def create_dark_palette() -> None:
    image = bpy.data.images.load(str(PALETTE_SOURCE), check_existing=False)
    image.colorspace_settings.name = "sRGB"
    pixels = list(image.pixels)
    # Keep the large matte colors around 20–30% perceived brightness.  This is
    # dark enough for UI emission to lead, without turning the facility silhouette
    # into near-black under the base lighting.
    for index in range(0, len(pixels), 4):
        for channel in range(3):
            pixels[index + channel] *= 0.45
    image.pixels[:] = pixels
    image.filepath_raw = str(PALETTE_TARGET)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def connected_components(mesh: bpy.types.Mesh) -> list[set[int]]:
    adjacency = {index: set() for index in range(len(mesh.vertices))}
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(adjacency)
    result = []
    while unseen:
        root = unseen.pop()
        todo = [root]
        component = {root}
        while todo:
            current = todo.pop()
            for other in adjacency[current]:
                if other in unseen:
                    unseen.remove(other)
                    component.add(other)
                    todo.append(other)
        result.append(component)
    return result


def remove_baked_default_cube(obj: bpy.types.Object) -> int:
    mesh = obj.data
    remove_indices: set[int] = set()
    for component in connected_components(mesh):
        if len(component) != 8:
            continue
        faces = [poly for poly in mesh.polygons if all(v in component for v in poly.vertices)]
        if len(faces) != 6:
            continue
        coords = [mesh.vertices[index].co for index in component]
        size = [max(co[axis] for co in coords) - min(co[axis] for co in coords) for axis in range(3)]
        if all(abs(value - 1.0) < 0.002 for value in size):
            remove_indices.update(component)
    if not remove_indices:
        return 0
    bm = bmesh.new()
    bm.from_mesh(mesh)
    targets = [vertex for vertex in bm.verts if vertex.index in remove_indices]
    bmesh.ops.delete(bm, geom=targets, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(remove_indices)


def assign_palette_and_materials() -> None:
    palette = bpy.data.images.load(str(PALETTE_TARGET), check_existing=True)
    palette.name = "设施低亮多巴胺色盘_10x10_512"
    palette.colorspace_settings.name = "sRGB"
    for material in bpy.data.materials:
        if not material.use_nodes or material.node_tree is None:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                node.image = palette
                node.interpolation = "Closest"
                node.extension = "EXTEND"
        bsdf = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        if material.name.startswith("01_"):
            bsdf.inputs["Metallic"].default_value = 0.86
            bsdf.inputs["Roughness"].default_value = 0.30
        elif material.name.startswith("02_"):
            bsdf.inputs["Metallic"].default_value = 0.02
            bsdf.inputs["Roughness"].default_value = 0.76
        elif material.name.startswith("03_"):
            bsdf.inputs["Metallic"].default_value = 0.14
            bsdf.inputs["Roughness"].default_value = 0.18
            if "Coat Weight" in bsdf.inputs:
                bsdf.inputs["Coat Weight"].default_value = 0.62
        elif material.name.startswith("04_"):
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.38
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = 1.0


def revise(path: Path) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    removed_source = []
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name in GUIDE_NAMES and len(obj.data.vertices) == 8 and len(obj.data.polygons) == 6:
            removed_source.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
    removed_baked = 0
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if output:
        for obj in output.objects:
            if obj.type == "MESH" and "自发光" not in obj.name and "UI灯光" not in obj.name:
                removed_baked += remove_baked_default_cube(obj)
    assign_palette_and_materials()
    bpy.context.scene["美术修订"] = "设施低亮度配色；默认1米立方体已清理"
    bpy.context.scene["主体亮度策略"] = "主表面约20%至30%明度；高饱和亮色限小面积；UI独立自发光"
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    print(f"REVISED {path.name}: source={removed_source}, baked_vertices={removed_baked}")


if __name__ == "__main__":
    create_dark_palette()
    for facility_path in FACILITY_FILES:
        revise(facility_path)
