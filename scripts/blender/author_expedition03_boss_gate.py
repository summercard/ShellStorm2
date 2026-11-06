"""Build the manor gate components and export from their optimized Blend copies."""

import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[2]
VERSION = "v020"
SOURCE = ROOT / "art_source/environments/tower_zones/expedition/source/common_components" / VERSION
ASSETS = ROOT / "assets/art/environments/tower_zones/expedition"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
STEEL, CHARCOAL, BRASS, GOLD, LIGHT = (7, 3), (0, 3), (5, 6), (7, 6), (8, 6)


def material(name, metallic, roughness, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(PALETTE), check_existing=True)
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emission > 0.0:
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.surfaces = [], [], []

    def prism(self, profile, depth, y, surface):
        count = len(profile)
        start = len(self.vertices)
        self.vertices.extend((x, y + dy, z) for dy in (-depth / 2, depth / 2) for x, z in profile)
        faces = [tuple(range(count)), tuple(reversed(range(count, 2 * count)))]
        for index in range(count):
            next_index = (index + 1) % count
            faces.append((index, index + count, next_index + count, next_index))
        self.faces.extend(tuple(start + i for i in face) for face in faces)
        self.surfaces.extend([surface] * len(faces))

    def box(self, x, y, z, width, depth, height, surface):
        left, right = x - width / 2, x + width / 2
        low, high = z - height / 2, z + height / 2
        self.prism([(left, low), (right, low), (right, high), (left, high)], depth, y, surface)

    def lozenge(self, x, y, z, width, depth, height, surface):
        self.prism([(x, z - height / 2), (x + width / 2, z),
                    (x, z + height / 2), (x - width / 2, z)], depth, y, surface)

    def mesh(self, name, mats):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        for mat in mats:
            mesh.materials.append(mat)
        uv = mesh.uv_layers.new(name="PaletteUV")
        for polygon, (role, cell) in zip(mesh.polygons, self.surfaces):
            polygon.material_index = role
            for j, loop_index in enumerate(polygon.loop_indices):
                # Every polygon's samples stay inside its own constant-color cell.
                angle = math.tau * j / len(polygon.loop_indices)
                uv.data[loop_index].uv = ((cell[0] + 0.5 + math.cos(angle) * 0.22) / 10,
                                          (cell[1] + 0.5 + math.sin(angle) * 0.22) / 10)
        mesh.update()
        return mesh


def panel():
    geo = Geometry()
    geo.box(0, 0, 1.25, 3, 0.15, 2.5, (0, CHARCOAL))
    for side in (-1, 1):
        geo.box(0, side * 0.079, 1.25, 2.78, 0.016, 2.26, (0, STEEL))
        for x in (-1.38, 1.38):
            geo.box(x, side * 0.093, 1.25, 0.07, 0.018, 2.29, (1, BRASS))
            for z in (0.31, 0.83, 1.67, 2.19):
                geo.lozenge(x * 0.84, side * 0.093, z, 0.11, 0.022, 0.075, (1, GOLD))
        for z in (0.19, 2.31):
            geo.box(0, side * 0.095, z, 2.74, 0.024, 0.11, (1, GOLD))
        geo.lozenge(0, side * 0.099, 1.25, 1.12, 0.035, 0.87, (1, BRASS))
        geo.lozenge(0, side * 0.123, 1.25, 0.68, 0.025, 0.59, (0, CHARCOAL))
        geo.lozenge(0, side * 0.140, 1.25, 0.35, 0.021, 0.34, (1, LIGHT))
    geo.vertices = [(x, y * 0.8, z) for x, y, z in geo.vertices]
    return geo


def frame():
    geo = Geometry()
    for side in (-1, 1):
        geo.box(side * 2, 0, 1.4, 1, 0.30, 2.8, (0, CHARCOAL))
        for face in (-1, 1):
            geo.box(side * 1.76, face * 0.275, 0.16, 0.52, 0.33, 0.32, (1, BRASS))
            geo.box(side * 1.74, face * 0.24, 1.45, 0.42, 0.26, 2.37, (1, GOLD))
            geo.box(side * 1.74, face * 0.39, 1.46, 0.16, 0.08, 2.18, (1, LIGHT))
            geo.box(side * 1.74, face * 0.285, 2.52, 0.48, 0.35, 0.25, (1, BRASS))
    geo.box(0, 0, 2.69, 4.02, 0.68, 0.38, (1, BRASS))
    geo.box(0, 0, 2.90, 4.16, 0.96, 0.16, (1, GOLD))
    geo.prism([(-1.13, 2.97), (1.13, 2.97), (0.66, 3.33),
               (0, 3.67), (-0.66, 3.33)], 0.86, 0, (1, BRASS))
    for face in (-1, 1):
        geo.lozenge(0, face * 0.46, 3.26, 0.63, 0.09, 0.60, (1, GOLD))
        geo.lozenge(0, face * 0.52, 3.26, 0.29, 0.05, 0.30, (1, LIGHT))
    return geo


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def author(entry):
    slug = entry["slug"]
    package = SOURCE / "component_packages" / slug
    source = package / f"{slug}_source_{VERSION}.blend"
    optimized = package / "export" / VERSION / f"{slug}_optimized_{VERSION}.blend"
    glb = ASSETS / "components/common_components" / slug / f"env_{slug}_visual_top3d.glb"
    prefab = ASSETS / "runtime/common_components" / slug / f"env_{slug}_root_top3d.tscn"
    for path in (source, optimized, glb, prefab):
        path.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.unit_settings.system = "METRIC"
    mats = [material("01_精工金属_黑钢", 0.76, 0.47),
            material("BrassMetal", 0.63, 0.34, 0.18)]
    collection = bpy.data.collections.new(slug)
    bpy.context.scene.collection.children.link(collection)
    obj = bpy.data.objects.new(slug, (panel() if entry["family"] == "door" else frame()).mesh(slug, mats))
    collection.objects.link(obj)
    obj["asset_id"] = entry["asset_id"]
    obj["asset_version"] = VERSION
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    source_sha = sha(source)
    bpy.ops.wm.save_as_mainfile(filepath=str(optimized))

    obj.data.calc_loop_triangles()
    before = len(obj.data.loop_triangles)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(optimized))
    bpy.ops.wm.open_mainfile(filepath=str(optimized))
    obj = bpy.data.objects[slug]
    obj.data.calc_loop_triangles()
    after = len(obj.data.loop_triangles)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", export_image_format="NONE",
                              use_selection=True, export_materials="EXPORT", export_apply=True,
                              export_cameras=False, export_lights=False)
    assert sha(source) == source_sha
    manifest = {
        **entry, "component_id": entry["asset_id"], "asset_version": VERSION,
        "block_id": "expedition", "level_id": "expedition_03", "room_owned_geometry": False,
        "coordinate_mapping": "(bx, by, bz) -> (bx, bz, -by)", "origin_contract": "bottom_center",
        "palette_uv_layer": "PaletteUV", "palette": relative(PALETTE),
        "bounds_size_m": [round(obj.dimensions.x, 4), round(obj.dimensions.z, 4), round(obj.dimensions.y, 4)],
        "component_blend": relative(source), "component_blend_sha256": source_sha,
        "source_sha256_after": sha(source), "optimized_blend": relative(optimized), "optimized_blend_sha256": sha(optimized),
        "optimization": "Merge coincident vertices, dissolve degenerate edges, recalculate normals, triangulate. Visible hard edges retained.",
        "triangles_before": before, "triangles_after": after, "reduction_ratio": 1 - after / before,
        "visual_glb": relative(glb), "glb_sha256": sha(glb), "prefab_path": relative(prefab),
        "runtime_integrated": False,
    }
    (package / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("GATE_ASSET", slug, manifest["bounds_size_m"], before, after, flush=True)
    return manifest


plan = json.loads((SOURCE / "component_plan.json").read_text(encoding="utf-8"))
assert plan["frozen"] and len(plan["components"]) == 2
catalog = {"components": [author(entry) for entry in plan["components"]]}
(SOURCE / "component_catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
