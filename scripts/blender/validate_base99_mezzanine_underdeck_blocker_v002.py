"""Strict validation for the grey horizontal-panel Base99 blocker v002."""

from __future__ import annotations

import bpy


EXPECTED_MATERIALS = {
    "01_精工金属_冷灰骨架",
    "02_细腻哑光_中灰横向板",
    "03_清漆反光_浅灰边条",
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
    collection = bpy.data.collections.get("02_游戏输出_整合模型")
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
        assert len({uv_cell(point.x) for point in loops}) == 1
        assert len({uv_cell(point.y) for point in loops}) == 1
    for material in body.data.materials:
        nodes = material.node_tree.nodes
        uv_nodes = [node for node in nodes if node.type == "UVMAP"]
        image_nodes = [node for node in nodes if node.type == "TEX_IMAGE"]
        assert len(uv_nodes) == 1 and uv_nodes[0].uv_map == "PaletteUV"
        assert len(image_nodes) == 1 and image_nodes[0].interpolation == "Closest"
        assert material["palette_cell"][0] == 9, "v002 material is not in the grey palette column"
    root = body.parent
    assert root is not None and root.name.endswith("v002")
    vertices = [root.matrix_world.inverted() @ body.matrix_world @ vertex.co for vertex in body.data.vertices]
    assert abs(min(vertex.z for vertex in vertices)) <= 0.0001, "Output bottom is not Z=0"
    print("BASE99_UNDERDECK_BLOCKER_V002_BLEND_VALID: faces=%d materials=%d grey_column=9" % (len(body.data.polygons), len(body.data.materials)))


if __name__ == "__main__":
    main()
