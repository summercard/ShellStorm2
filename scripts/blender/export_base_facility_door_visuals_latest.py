"""Export the shared Base99 door visuals from the highest versioned layout source.

114/12 are the west/east instances of one wall-door visual contract; 115/71
are the west/east instances of one lift-door visual contract. Runtime keeps
those two AssetIDs shared so RoomDoor3D behaviour is never duplicated.
"""
import bpy
import bmesh
import hashlib
import json
import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
LAYOUT = PROJECT / "source/art/blender/base_facility_layout"
sources = sorted(LAYOUT.joinpath("source").glob("base_facility_runtime_layout_hq_v*.blend"))
SOURCE = max(sources, key=lambda p: int(re.search(r"v(\d{3})", p.name).group(1)))
VERSION = "v" + re.search(r"v(\d{3})", SOURCE.name).group(1)
EXPORT_DIR = LAYOUT / "export" / VERSION
DERIVED = EXPORT_DIR / f"base_facility_runtime_layout_hq-{VERSION}-door_visuals.blend"
MANIFEST = EXPORT_DIR / "door_visuals_export_manifest.json"
COMPONENTS = PROJECT / "assets/art/environments/base_facility_3d/components"
TARGETS = {
    "wall_door": {
        "root": "ENV-BASE99-WALL-DOOR-5X9_WEST_输出根节点",
        "glb": COMPONENTS / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v002.glb",
        "packages": [("west_door_wall_module", "114_西墙带门墙模块_资产包"), ("east_door_wall_module", "12_东墙带门墙模块_资产包")],
    },
    "door_lift": {
        "root": "ENV-BASE99-DOOR-LIFT-22X25_WEST_输出根节点",
        "glb": COMPONENTS / "env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v002.glb",
        "packages": [("west_door_lift_instance", "115_西侧滑升门运行时实例_资产包"), ("east_personnel_security_door", "71_正式人员安全门_资产包")],
    },
}

def descendants(root):
    result, pending = [], list(root.children)
    while pending:
        item = pending.pop(); result.append(item); pending.extend(item.children)
    return result

def down_cull_and_triangulate(obj, source_world):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    normal = source_world.to_3x3()
    down = [face for face in bm.faces if (normal @ face.normal).normalized().z < -0.5]
    if down: bmesh.ops.delete(bm, geom=down, context="FACES")
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return len(down)

def make_derived():
    for obj in list(bpy.data.objects): bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections): bpy.data.collections.remove(collection)
    root_out = bpy.data.collections.new(f"00_导出优化资产包_{VERSION}_door_visuals")
    bpy.context.scene.collection.children.link(root_out)
    metrics = {}
    # Reopen source after cleanup is impossible, so source objects are captured before cleanup by caller.
    return root_out, metrics

def build():
    captures = {}
    for key, spec in TARGETS.items():
        root = bpy.data.objects.get(spec["root"])
        if root is None: raise RuntimeError(f"Missing source root: {spec['root']}")
        # Copy mesh data before clearing the source scene. Object RNA handles become
        # invalid after removal, while copied Mesh datablocks retain the material and
        # PaletteUV assignments required by the runtime visual.
        captures[key] = (
            root.matrix_world.copy(),
            [(obj.name, obj.data.copy(), obj.matrix_world.copy()) for obj in descendants(root) if obj.type == "MESH"],
        )
    for obj in list(bpy.data.objects): bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections): bpy.data.collections.remove(collection)
    export_root = bpy.data.collections.new(f"00_导出优化资产包_{VERSION}_door_visuals")
    bpy.context.scene.collection.children.link(export_root)
    metrics = {}
    for key, (root_matrix, meshes) in captures.items():
        collection = bpy.data.collections.new(f"{key}_02_游戏输出_整合模型")
        export_root.children.link(collection)
        removed = 0; before = 0; clones = []
        for source_name, source_mesh, source_world in meshes:
            clone = bpy.data.objects.new(f"{key}_{source_name}", source_mesh)
            before += sum(len(poly.vertices) - 2 for poly in clone.data.polygons)
            removed += down_cull_and_triangulate(clone, source_world)
            clone.matrix_world = root_matrix.inverted() @ source_world
            collection.objects.link(clone); clones.append(clone)
        for clone in clones:
            uv = clone.data.uv_layers.get("PaletteUV")
            if uv is None: raise RuntimeError(f"{key} missing PaletteUV")
            clone.data.uv_layers.active = uv; uv.active_render = True
        metrics[key] = {"triangles_before": before, "triangles_after": sum(len(o.data.polygons) for o in clones), "downward_triangles_removed": removed}
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED))
    return metrics

def export(metrics):
    bpy.ops.wm.open_mainfile(filepath=str(DERIVED))
    for key, spec in TARGETS.items():
        collection = bpy.data.collections[f"{key}_02_游戏输出_整合模型"]
        bpy.ops.object.select_all(action="DESELECT")
        meshes = [o for o in collection.objects if o.type == "MESH"]
        for obj in meshes: obj.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        spec["glb"].parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(spec["glb"]), export_format="GLB", use_selection=True, export_apply=True,
            export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True, export_materials="EXPORT",
            export_image_format="NONE", export_lights=False, export_cameras=False, export_animations=False)
        metrics[key]["visual_glb"] = str(spec["glb"].relative_to(PROJECT))
        metrics[key]["visual_glb_sha256"] = hashlib.sha256(spec["glb"].read_bytes()).hexdigest()
    entries=[]
    for key, spec in TARGETS.items():
        for slug, collection in spec["packages"]:
            entries.append({"slug":slug,"collection":collection,"shared_visual_key":key,**metrics[key]})
    data={"version":VERSION,"source_blend":str(SOURCE.relative_to(PROJECT)),"source_blend_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"derived_blend":str(DERIVED.relative_to(PROJECT)),"packages":entries}
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    print(f"BASE99_DOOR_VISUALS_EXPORTED:version={VERSION}:packages=4")

metrics = build()
export(metrics)
