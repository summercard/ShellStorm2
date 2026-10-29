"""Author v002 interactive clutter: v001 geometry scaled per user instruction.

User 2026-10-29: chair +50%, jar +50%, crate +30%, books unchanged, vase unchanged.
Scaling is applied to vertices before origin shift, so triangle counts and topology
stay identical to v001 (pure uniform scale, no re-mesh).
"""
import bpy
import bmesh
import math
import json
import sys
import hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from workspace_paths import work_path

LIB = ROOT / "art_source/environments/tower_zones/battle/source/common_components/v002_interactive_clutter"
WORK = work_path("sessions/2026-10-29_clutter_v002")
WORK.mkdir(parents=True, exist_ok=True)
PLAN = json.loads((LIB / "component_plan.json").read_text(encoding="utf-8"))
assert PLAN["library"] == "v002_interactive_clutter"
assert len(PLAN["components"]) == 5
SOURCE = LIB / "battle_interactive_clutter_v002.blend"
OPTIMIZED = LIB / "export/v002/battle_interactive_clutter_optimized_v002.blend"
OPTIMIZED.parent.mkdir(parents=True, exist_ok=True)
assert not SOURCE.exists() and not OPTIMIZED.exists(), "Use a new source version; do not overwrite."
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
SCALE = {c["slug"]: float(c["scale_from_v001"]) for c in PLAN["components"]}
MAX_DIM = {c["slug"]: float(c["max_dimension_m"]) for c in PLAN["components"]}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "战局易碎小物件_独立组件库_v002"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x = 1400
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.world = bpy.data.worlds.new("组件预览世界")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.17, 0.21, 0.27, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
scene.view_settings.view_transform = "AgX"


def collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


master = collection("战局易碎小物件_中文资产管理", scene.collection)
source_col = collection("01_制作组件_按组件拆分", master)
out_col = collection("02_游戏输出_独立资产包_v002", master)
source_col.hide_render = True
source_col.hide_viewport = True
show_col = collection("90_展示与验收_灯光相机", master)

image = bpy.data.images.load(str(PALETTE))
image.filepath = str(PALETTE)
materials = []
material_names = []
for name, metal, rough, coat in [
    ("01_精工金属_紫色骨架", 0.86, 0.29, 0.16),
    ("02_细腻哑光_青绿大面", 0.025, 0.72, 0.0),
    ("03_清漆反光_紫粉点缀", 0.18, 0.15, 0.65),
]:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Coat Weight"].default_value = coat
    uv = mat.node_tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    mat.node_tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    materials.append(mat)
    material_names.append(name)


class Geometry:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.styles = []

    def add(self, vertices, faces, cell, role=1):
        start = len(self.vertices)
        self.vertices.extend([tuple(v) for v in vertices])
        self.faces.extend([tuple(start + i for i in f) for f in faces])
        self.styles.extend([(cell, role)] * len(faces))

    def box(self, center, size, cell, role=1, angle=0.0):
        c = Vector(center)
        transform = Matrix.Translation(c) @ Matrix.Rotation(angle, 4, "Z")
        vertices = [transform @ Vector((x * size[0] / 2, y * size[1] / 2, z * size[2] / 2))
                    for x, y, z in [(-1, -1, -1), (-1, -1, 1), (-1, 1, -1), (-1, 1, 1),
                                    (1, -1, -1), (1, -1, 1), (1, 1, -1), (1, 1, 1)]]
        faces = [(0, 4, 6, 2), (1, 3, 7, 5), (0, 1, 5, 4), (2, 6, 7, 3), (0, 2, 3, 1), (4, 5, 7, 6)]
        self.add(vertices, faces, cell, role)

    def lathe(self, profile, sides, cell, role=1, cap_bottom=True):
        vertices = []
        for radius, height in profile:
            for i in range(sides):
                a = i * math.tau / sides
                vertices.append((math.cos(a) * radius, math.sin(a) * radius, height))
        faces = []
        for ring in range(len(profile) - 1):
            for i in range(sides):
                j = (i + 1) % sides
                faces.append((ring * sides + i, ring * sides + j,
                              (ring + 1) * sides + j, (ring + 1) * sides + i))
        if cap_bottom:
            faces.append(tuple(reversed(range(sides))))
        self.add(vertices, faces, cell, role)

    def disk(self, radius, height, sides, cell, role=1):
        vertices = [(math.cos(i * math.tau / sides) * radius,
                     math.sin(i * math.tau / sides) * radius, height) for i in range(sides)]
        self.add(vertices, [tuple(range(sides))], cell, role)


records = {}
for spec in PLAN["components"]:
    slug = spec["slug"]
    g = Geometry()
    if slug == "breakable_jar":
        g.lathe([(0.145, 0.0), (0.205, 0.055), (0.215, 0.28), (0.148, 0.43), (0.102, 0.50)], 8, (6, 3), 2)
        g.disk(0.084, 0.478, 8, (0, 0))
        g.lathe([(0.102, 0.50), (0.119, 0.54)], 8, (8, 4), 2, False)
        for sign in (-1, 1):
            g.add([(sign * 0.18, -0.035, 0.34), (sign * 0.22, -0.035, 0.36),
                   (sign * 0.19, -0.035, 0.42), (sign * 0.18, -0.045, 0.34)],
                  [(0, 1, 2), (2, 1, 3)], (8, 4), 2)
    elif slug == "breakable_book_stack":
        for i, (z, width, depth, angle, cell) in enumerate([(0.048, 0.58, 0.42, -0.08, (4, 5)),
                                                            (0.155, 0.54, 0.39, 0.09, (7, 2)),
                                                            (0.262, 0.49, 0.36, -0.10, (3, 6))]):
            def p(x, y, h):
                return (x * math.cos(angle) - y * math.sin(angle),
                        x * math.sin(angle) + y * math.cos(angle), h)
            base = z - 0.038
            corners = [p(x, y, base) for x, y in [(-width / 2, -depth / 2), (width / 2, -depth / 2),
                                                  (width / 2, depth / 2), (-width / 2, depth / 2)]]
            top = [(x, y, z + 0.038) for x, y, _ in corners]
            g.add(corners + top,
                  [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
                  (8, 7))
            for h in (base - 0.009, z + 0.047):
                v = [p(-width / 2 - 0.012, -depth / 2 - 0.012, h), p(width / 2 + 0.012, -depth / 2 - 0.012, h),
                     p(width / 2 + 0.012, depth / 2 + 0.012, h), p(-width / 2 - 0.012, depth / 2 + 0.012, h)]
                g.add(v, [(0, 1, 2, 3)], cell)
            spine_center = p(0, -depth / 2 - 0.013, z)
            g.box(spine_center, (width + 0.018, 0.023, 0.10), cell, 1, angle)
    elif slug == "breakable_vase":
        g.lathe([(0.135, 0.0), (0.195, 0.10), (0.215, 0.32), (0.125, 0.55), (0.087, 0.66)], 8, (2, 6), 2)
        g.lathe([(0.087, 0.66), (0.112, 0.73)], 8, (8, 4), 2, False)
        g.disk(0.088, 0.716, 8, (0, 0))
    elif slug == "breakable_chair":
        for x in (-0.19, 0.19):
            for y in (-0.19, 0.19):
                g.box((x, y, 0.225), (0.055, 0.055, 0.45), (4, 2))
        g.box((0, 0, 0.46), (0.50, 0.50, 0.065), (5, 2))
        for x in (-0.20, 0.20):
            g.box((x, 0.205, 0.63), (0.055, 0.055, 0.40), (4, 2), 0)
        g.box((0, 0.205, 0.79), (0.48, 0.065, 0.14), (2, 6), 2)
    elif slug == "breakable_crate":
        g.box((0, 0, 0.30), (0.60, 0.60, 0.60), (5, 2))
        for x in (-0.285, 0.285):
            for y in (-0.285, 0.285):
                g.box((x, y, 0.30), (0.075, 0.075, 0.64), (7, 2), 0)
        for x in (-0.255, 0.255):
            g.box((x, 0, 0.635), (0.09, 0.66, 0.05), (6, 2), 0)
        a, b = Vector((-0.23, -0.325, 0.08)), Vector((0.23, -0.325, 0.53))
        direction = b - a
        rotation = direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
        length = direction.length
        brace = Geometry()
        brace.box((0, 0, 0), (0.075, 0.045, length), (7, 2), 0)
        verts = [Matrix.Translation((a + b) * 0.5) @ rotation @ Vector(v) for v in brace.vertices]
        g.add(verts, brace.faces, (7, 2), 0)
        g.add([(-0.09, -0.334, 0.26), (0.09, -0.334, 0.26),
               (0.09, -0.334, 0.40), (-0.09, -0.334, 0.40)], [(0, 1, 2, 3)], (8, 7))
    else:
        raise ValueError(slug)

    # 纯统一缩放：先缩放顶点，再按缩放后的包围盒重新做「底部中心」原点对齐。
    factor = SCALE[slug]
    g.vertices = [(v[0] * factor, v[1] * factor, v[2] * factor) for v in g.vertices]
    low = Vector(tuple(min(v[i] for v in g.vertices) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in g.vertices) for i in range(3)))
    shift = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    vertices = [Vector(v) + shift for v in g.vertices]
    bounds = high - low
    assert max(bounds) <= MAX_DIM[slug] + 1e-6, (slug, list(bounds), MAX_DIM[slug])

    mesh = bpy.data.meshes.new(slug + "_Mesh")
    mesh.from_pydata(vertices, [], g.faces)
    mesh.update()
    for mat in materials:
        mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name="PaletteUV")
    uv.active_render = True
    for polygon, (cell, role) in zip(mesh.polygons, g.styles):
        polygon.material_index = role
        n = len(polygon.loop_indices)
        cx, cy = (cell[0] + 0.5) / 10, 1 - (cell[1] + 0.5) / 10
        for j, loop_index in enumerate(polygon.loop_indices):
            uv.data[loop_index].uv = (cx + 0.026 * math.cos(j * math.tau / n),
                                      cy + 0.026 * math.sin(j * math.tau / n))
    pack = collection(spec["collection"], out_col)
    pack.instance_offset = (0, 0, 0)
    root = bpy.data.objects.new(spec["root_object"], None)
    root.empty_display_size = 0.12
    pack.objects.link(root)
    obj = bpy.data.objects.new(spec["name_zh"] + "_主体", mesh)
    pack.objects.link(obj)
    obj.parent = root
    obj["asset_id"] = spec["asset_id"]
    obj["component_id"] = spec["component_id"]
    obj["block_id"] = "battle"
    obj["scale_from_v001"] = factor
    source_copy = obj.copy()
    source_copy.data = mesh.copy()
    source_col.objects.link(source_copy)
    triangles = sum(len(p.vertices) - 2 for p in mesh.polygons)
    assert triangles <= 100, (slug, triangles)
    records[slug] = {
        "spec": spec, "object": obj.name, "collection": pack.name, "root": root.name,
        "bounds": [float(v) for v in bounds], "triangles_before": triangles,
        "vertices": len(mesh.vertices), "scale": factor,
    }
    print("V002_GEOM", slug, "scale=", factor, "tris=", triangles, "bounds=", [round(v, 4) for v in bounds])

# 预览画廊
for index, record in enumerate(records.values()):
    obj = bpy.data.objects[record["object"]]
    gallery = obj.copy()
    gallery.data = obj.data
    gallery.name = "预览_" + record["spec"]["slug"]
    gallery.parent = None
    gallery.location = ((index - 2) * 1.55, 0, 0)
    show_col.objects.link(gallery)
    obj.hide_render = True
    obj.hide_set(True)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


cam_data = bpy.data.cameras.new("五件组件验收相机")
cam = bpy.data.objects.new("五件组件验收相机", cam_data)
show_col.objects.link(cam)
cam.location = (4.6, -9.6, 4.0)
cam_data.type = "ORTHO"
cam_data.ortho_scale = 8.4
aim(cam, (0, 0, 0.42))
scene.camera = cam
for name, position, energy, size, color in [
    ("主光", (-3, -4, 6), 1150, 5.0, (0.80, 0.90, 1.0)),
    ("暖补光", (4, -1, 3), 800, 4.0, (1.0, 0.82, 0.63)),
    ("轮廓光", (0, 4, 5), 1300, 3.0, (0.60, 0.78, 1.0)),
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    show_col.objects.link(light)
    light.location = position
    aim(light, (0, 0, 0.45))

scene.render.filepath = str(WORK / "blender_component_gallery_v002.png")
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
source_sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.render.render(write_still=True)

# 独立优化文件
bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED))
for obj in list(source_col.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for obj in list(show_col.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for slug, record in records.items():
    obj = bpy.data.objects[record["object"]]
    obj.hide_set(False)
    obj.hide_render = False
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    isolated = [v for v in bm.verts if not v.link_faces]
    zero = [f for f in bm.faces if f.calc_area() < 1e-10]
    if isolated:
        bmesh.ops.delete(bm, geom=isolated, context="VERTS")
    if zero:
        bmesh.ops.delete(bm, geom=zero, context="FACES")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    tri = obj.modifiers.new("ExportTriangulation", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri.name)
    obj.select_set(False)
    record["triangles_after"] = len(obj.data.polygons)
    record["reduction_ratio"] = (
        (record["triangles_before"] - record["triangles_after"]) / record["triangles_before"]
        if record["triangles_before"] else None
    )
    record["optimization"] = {
        "isolated_vertices_removed": len(isolated),
        "zero_area_faces_removed": len(zero),
        "merge_distance": 0,
        "decimation": "none; uniform scale only, topology identical to v001",
        "preserved": "all silhouette, bottom/back faces, material boundaries and PaletteUV islands",
        "triangle_budget": 100,
        "budget_source": "user_request (per-piece <=100 triangles)",
        "scale_from_v001": record["scale"],
    }
    assert record["triangles_after"] <= 100
bpy.ops.wm.save_as_mainfile(filepath=str(OPTIMIZED))
bpy.ops.wm.open_mainfile(filepath=str(OPTIMIZED))

manifests = []
for slug, record in records.items():
    spec = record["spec"]
    obj = bpy.data.objects[record["object"]]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    destination = WORK / (slug + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=str(destination), export_format="GLB", use_selection=True,
        export_image_format="NONE", export_yup=True, export_animations=False,
        export_cameras=False, export_lights=False, export_extras=True)
    package = LIB / "component_packages" / slug
    package.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "shellstorm2.component_asset_manifest",
        "asset_id": spec["asset_id"], "component_id": spec["component_id"],
        "slug": slug, "name_zh": spec["name_zh"], "version": "v002",
        "supersedes_version": "v001",
        "block_id": "battle", "level_id": "tower_entry_safe_room",
        "component_family": spec["component_family"],
        "category": "scene_interactive_object", "scope": "shared",
        "serves_room_types": spec["serves_room_types"],
        "variant_axis": None, "variant_value": None, "variant_reason": None,
        "instance_count": 1,
        "source_blend": str(SOURCE.relative_to(ROOT)),
        "optimized_blend": str(OPTIMIZED.relative_to(ROOT)),
        "collection": record["collection"], "root_object": record["root"],
        "object": obj.name,
        "bounds_size_m": record["bounds"],
        "scale_from_v001": record["scale"],
        "max_dimension_m": MAX_DIM[slug],
        "local_origin": [0, 0, 0], "origin_contract": "bottom_center",
        "front_axis": "-Z", "allowed_rotations_y_deg": [0, 90, 180, 270],
        "collision_owner": "godot_wrapper",
        "palette_uv_layer": "PaletteUV", "material_roles": material_names,
        "triangles_before": record["triangles_before"],
        "triangles_after": record["triangles_after"],
        "reduction_ratio": record["reduction_ratio"],
        "optimization": record["optimization"],
        "source_sha256_before": source_sha,
        "source_sha256_after": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "optimized_sha256": hashlib.sha256(OPTIMIZED.read_bytes()).hexdigest(),
        "glb_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        "staged_glb": str(destination),
        "glb": "assets/art/environments/tower_zones/battle/components/common_components/" + slug + "/" + slug + "_visual_top3d.glb",
        "prefab": "assets/art/environments/tower_zones/battle/runtime/common_components/" + slug + "/" + slug + "_root_top3d.tscn",
        "asset_ledger": "resolved_by_ledger_index", "room_owned_geometry": False,
        "chair_embedded": False, "exported": False, "runtime_integrated": False,
        "visual_acceptance": {
            "gallery": "blender_component_gallery_v002.png",
            "status": "pending_godot_and_human_review"},
    }
    assert manifest["source_sha256_before"] == manifest["source_sha256_after"]
    (package / "asset_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    manifests.append(manifest)

(LIB / "component_catalog.json").write_text(json.dumps(manifests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(LIB / "export/v002/import_manifest.json").write_text(json.dumps(manifests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(WORK / "build.json").write_text(json.dumps(manifests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("CLUTTER_V002_BUILD_OK", [(m["slug"], m["triangles_after"],
                                 [round(v, 3) for v in m["bounds_size_m"]],
                                 m["scale_from_v001"]) for m in manifests])
