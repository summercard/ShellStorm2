import bpy
import bmesh
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v024.blend"
DERIVATIVE = ROOT / "source/art/blender/base_facility_layout/export/v024/base_facility_runtime_layout_hq-v024-corner_l_5m.blend"
OUTPUT_NAME = "基地5米L型转角墙_主体_金属哑光反光"
WORLD_DOWN_THRESHOLD = -0.65


def main():
    if not SOURCE.exists():
        raise RuntimeError(f"Latest v024 source is missing: {SOURCE}")
    DERIVATIVE.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    output = bpy.data.objects.get(OUTPUT_NAME)
    if output is None or output.type != "MESH":
        raise RuntimeError(f"Missing v024 game output mesh: {OUTPUT_NAME}")

    # The source root is the Godot inside-corner floor origin.  Work on a copied
    # mesh so this source file remains a reversible authoring master.
    visual = output.copy()
    visual.data = output.data.copy()
    visual.name = "env_base99_corner_l_5m_visual_top3d_v001"

    # Link the copy before removing the source scene objects; an unlinked copy
    # is purged when Blender removes its original collection users.
    export_collection = bpy.data.collections.new("02_游戏输出_整合模型")
    bpy.context.scene.collection.children.link(export_collection)
    export_collection.objects.link(visual)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in list(bpy.data.objects):
        if obj != visual:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection != export_collection:
            bpy.data.collections.remove(collection)
    bpy.context.view_layer.objects.active = visual
    visual.select_set(True)

    mesh = visual.data
    before_triangles = sum(len(face.vertices) - 2 for face in mesh.polygons)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    world_matrix = visual.matrix_world.copy()
    downward = [
        face for face in bm.faces
        if (world_matrix.to_3x3() @ face.normal).normalized().z < WORLD_DOWN_THRESHOLD
    ]
    bmesh.ops.delete(bm, geom=downward, context="FACES_ONLY")
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    after_triangles = len(mesh.polygons)

    # The material must stay palette-driven and export without packed images.
    if list(mesh.uv_layers.keys()) != ["PaletteUV"]:
        raise RuntimeError("Derivative must retain PaletteUV as its only UV channel")
    mesh.uv_layers.active = mesh.uv_layers["PaletteUV"]
    mesh.uv_layers["PaletteUV"].active_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(DERIVATIVE), check_existing=False)
    print("BASE99_CORNER_EXPORT_DERIVATIVE=" + json.dumps({
        "source": str(SOURCE),
        "derivative": str(DERIVATIVE),
        "removed_downward_faces": len(downward),
        "triangles_before": before_triangles,
        "triangles_after": after_triangles,
        "uv_layers": [layer.name for layer in mesh.uv_layers],
        "materials": [material.name for material in mesh.materials if material],
    }, ensure_ascii=False))


main()
