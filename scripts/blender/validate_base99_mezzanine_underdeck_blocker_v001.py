"""Strict source validation for ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER."""

from __future__ import annotations

import bpy


OUTPUT_COLLECTION = "02_游戏输出_整合模型"
EXPECTED_MATERIALS = {
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
}


def uv_cell(value: float) -> int:
    return max(0, min(9, int(value * 10.0)))


def uv_area(points) -> float:
    return abs(sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )) * 0.5


def main() -> None:
    collection = bpy.data.collections.get(OUTPUT_COLLECTION)
    assert collection is not None, "Missing game output collection"
    meshes = [obj for obj in collection.objects if obj.type == "MESH"]
    assert len(meshes) == 1, "Expected one merged body mesh, found %d" % len(meshes)
    body = meshes[0]
    assert set(material.name for material in body.data.materials) == EXPECTED_MATERIALS
    assert set(material.name for material in bpy.data.materials) == EXPECTED_MATERIALS
    uv = body.data.uv_layers.get("PaletteUV")
    assert uv is not None and body.data.uv_layers.active == uv and uv.active_render
    assert len(body.data.uv_layers) == 1, "Output contains undeclared extra UV layers"
    for polygon in body.data.polygons:
        loops = [uv.data[index].uv.copy() for index in polygon.loop_indices]
        assert uv_area(loops) > 0.000001, "Found zero-area PaletteUV island"
        columns = {uv_cell(point.x) for point in loops}
        rows = {uv_cell(point.y) for point in loops}
        assert len(columns) == 1 and len(rows) == 1, "PaletteUV polygon crosses color cells"
    for material in body.data.materials:
        nodes = material.node_tree.nodes
        uv_nodes = [node for node in nodes if node.type == "UVMAP"]
        image_nodes = [node for node in nodes if node.type == "TEX_IMAGE"]
        assert len(uv_nodes) == 1 and uv_nodes[0].uv_map == "PaletteUV"
        assert len(image_nodes) == 1 and image_nodes[0].interpolation == "Closest"
    output_root = body.parent
    assert output_root is not None, "Output body has no asset root"
    root_inverse = output_root.matrix_world.inverted()
    root_vertices = [root_inverse @ body.matrix_world @ vertex.co for vertex in body.data.vertices]
    minimum = [min(vertex[index] for vertex in root_vertices) for index in range(3)]
    assert abs(minimum[2]) <= 0.0001, "Output bottom is not Z=0"
    print("BASE99_UNDERDECK_BLOCKER_BLEND_VALID: faces=%d materials=%d uv=PaletteUV" % (
        len(body.data.polygons), len(body.data.materials)
    ))


if __name__ == "__main__":
    main()
