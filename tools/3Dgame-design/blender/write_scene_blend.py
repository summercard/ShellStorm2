import json
import math
import os
import sys

import bpy
sys.path.insert(0, os.path.dirname(__file__))
from stair_profile import profile_parts


def args_after_separator():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


scene_json, output_blend = args_after_separator()
with open(scene_json, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

for record in payload.get('components', []):
    if not (record.get('surfaceSettings') or record.get('stairwellSettings') or record.get('stairSettings')): continue
    group = next((g for g in payload.get('groups',[]) if g['name']==record.get('group')), {})
    if any(abs(item.get('scale',{}).get(axis,1)-1)>1e-6 for item in (record,group) for axis in 'xyz'):
        raise RuntimeError('固定组件禁止缩放，请拼接组件或调整楼梯高度/坡度：'+record['name'])

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection != bpy.context.scene.collection:
        bpy.data.collections.remove(collection)


def material(name, color):
    value = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.roughness = 0.7
    return value


MATERIALS = {
    "建筑": material("白模_建筑", (0.52, 0.62, 0.64)),
    "家具": material("白模_家具", (0.52, 0.31, 0.19)),
    "办公": material("白模_办公", (0.24, 0.40, 0.48)),
    "角色": material("白模_角色", (0.74, 0.55, 0.24)),
    "道具": material("白模_道具", (0.62, 0.44, 0.18)),
}


def category(component_type):
    if "角色" in component_type:
        return "角色"
    if component_type in {"墙壁", "地板", "拐角柱", "楼梯间下层楼板", "楼梯间中层楼板", "楼梯间上层楼板", "楼梯间楼梯", "门", "窗", "楼梯"}:
        return "建筑"
    if component_type in {"办公桌", "办公椅", "显示器", "笔记本电脑", "文件柜", "书架", "打印机", "饮水机", "会议桌", "白板"}:
        return "办公"
    if component_type in {"路灯", "箱子"}:
        return "道具"
    return "家具"


def link_only(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def add_box(name, size, location, collection, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    link_only(obj, collection)
    return obj


def add_component_geometry(record, root, collection):
    component_type = record.get("type", "组件")
    mat = MATERIALS[category(component_type)]
    parts = []
    surface = record.get("surfaceSettings") or {}
    if component_type == "墙壁":
        parts.append(add_box("墙体", (surface.get("width", 5), surface.get("thickness", .2), surface.get("height", 3)), (0, 0, surface.get("height", 3) / 2), collection, mat))
    elif component_type in {"地板", "楼梯间下层楼板", "楼梯间中层楼板", "楼梯间上层楼板"}:
        thickness = surface.get("thickness", .1)
        center_z = surface.get("topOffset", thickness) - thickness / 2
        parts.append(add_box("地板", (surface.get("length", 5), surface.get("width", 5), thickness), (0, 0, center_z), collection, mat))
    elif component_type == "拐角柱":
        parts.append(add_box("拐角柱", (surface.get("length", .5), surface.get("width", .5), surface.get("thickness", 12.9)), (0, 0, surface.get("thickness", 12.9) / 2), collection, mat))
    elif component_type == "楼梯间楼梯" and (record.get('stairwellSettings') or {}).get('profile') == 'original-v013':
        for part in profile_parts(record['stairwellSettings']):
            mesh = bpy.data.meshes.new(part['name'])
            mesh.from_pydata(part['vertices'], [], part['faces']); mesh.update()
            obj = bpy.data.objects.new(part['name'], mesh)
            collection.objects.link(obj); obj.data.materials.append(mat); parts.append(obj)
    elif component_type == "楼梯间楼梯":
        settings = record.get("stairwellSettings") or {}
        steps = max(1, int(settings.get("stepCount", 20)))
        width, run = settings.get("width", 6), settings.get("runLength", 15)
        angle = math.radians(max(5, min(60, settings.get("slopeDeg", 21.8014))))
        total, tread = math.tan(angle) * run, run / steps
        rise = total / steps
        for index in range(steps):
            parts.append(add_box(f"踏步_{index + 1:02d}", (width, tread, rise), (0, -(index + .5) * tread, (index + .5) * rise), collection, mat))
    elif component_type == "楼梯":
        settings = record.get("stairSettings") or {}
        steps = max(1, int(settings.get("steps", 10)))
        width, tread, rise = settings.get("width", 1.5), .3, .18
        for index in range(steps):
            parts.append(add_box(f"踏步_{index + 1:02d}", (width, tread, rise), (0, -(index + .5) * tread, (index + .5) * rise), collection, mat))
    elif "角色" in component_type:
        settings = record.get("characterSettings") or {}
        leg, body, head = settings.get("legLength", .6), settings.get("bodyLength", .6), settings.get("headSize", .4)
        parts.extend([
            add_box("身体", (settings.get("bodyThickness", .34), settings.get("bodyThickness", .34), body), (0, 0, leg + body / 2), collection, mat),
            add_box("头部", (head, head, head), (0, 0, leg + body + head / 2), collection, mat),
        ])
    else:
        sizes = {
            "门": (1.25, .13, 2.35), "窗": (2, .12, 1.55), "桌子": (2.2, 1.3, 1.3), "柜子": (1.4, .55, 1.65),
            "衣柜": (2.4, .65, 2.35), "电视柜": (2.25, .5, .62), "椅子": (.8, .8, 1.45), "沙发": (2.2, .92, 1.08),
            "懒人沙发": (1.3, 1.3, 1.1), "床": (2.25, 1.35, 1.0), "办公桌": (1.6, .75, .8), "办公椅": (.62, .62, 1.23),
            "显示器": (.9, .25, 1.48), "笔记本电脑": (.9, .6, .55), "文件柜": (.75, .55, 1.45), "书架": (1.2, .38, 1.85),
            "打印机": (.7, .55, .42), "饮水机": (.52, .5, 1.35), "会议桌": (3.0, 1.25, .85), "白板": (2.1, .12, 1.45),
            "路灯": (.45, .45, 3.2), "箱子": (1.0, .8, .75),
        }
        size = sizes.get(component_type, (1, 1, 1))
        parts.append(add_box(component_type, size, (0, 0, size[2] / 2), collection, mat))
    for part in parts:
        part.parent = root


block_name = (payload.get("project") or {}).get("blockName") or (payload.get("projectMetadata") or {}).get("blockId") or "未归类区块"
scene_name = payload.get("name") or "未命名场景"
block_collection = bpy.data.collections.new(block_name)
bpy.context.scene.collection.children.link(block_collection)

group_roots = {}
group_collections = {}
for group in payload.get("groups", []):
    group_collection = bpy.data.collections.new(group.get('name','分组'))
    block_collection.children.link(group_collection)
    group_collections[group['name']] = group_collection
    root = bpy.data.objects.new(group.get("name", "分组"), None)
    group_collection.objects.link(root)
    pos, rot, scale = group.get("position", {}), group.get("rotation", {}), group.get("scale", {})
    root.location = (pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
    root.rotation_euler = tuple(math.radians(rot.get(axis, 0)) for axis in ("x", "y", "z"))
    root.scale = tuple(scale.get(axis, 1) for axis in ("x", "y", "z"))
    group_roots[group.get("name")] = root

shared_meshes = {}
for record in payload.get("components", []):
    component_collection = bpy.data.collections.new(record.get("name", "组件"))
    group_collections.get(record.get('group'),block_collection).children.link(component_collection)
    root = bpy.data.objects.new(record.get("name", "组件"), None)
    component_collection.objects.link(root)
    pos, rot, scale = record.get("position", {}), record.get("rotation", {}), record.get("scale", {})
    root.location = (pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
    root.rotation_euler = tuple(math.radians(rot.get(axis, 0)) for axis in ("x", "y", "z"))
    root.scale = tuple(scale.get(axis, 1) for axis in ("x", "y", "z"))
    if record.get("group") in group_roots:
        root.parent = group_roots[record["group"]]
    root["component_type"] = record.get("type", "")
    root["asset_id"] = record.get("assetId", "")
    root["source"] = "3Dgame-design"
    add_component_geometry(record, root, component_collection)
    if record.get('stairwellSettings'):
        for index,child in enumerate(root.children):
            mesh_key=(tuple(tuple(v.co) for v in child.data.vertices),tuple(tuple(p.vertices) for p in child.data.polygons))
            if mesh_key in shared_meshes:
                old=child.data; child.data=shared_meshes[mesh_key]; bpy.data.meshes.remove(old)
            else: shared_meshes[mesh_key]=child.data

# Native scenes round-trip from this embedded contract; no GLB baking is needed.
embedded = bpy.data.texts.get('3Dgame-design.scene.json') or bpy.data.texts.new('3Dgame-design.scene.json')
embedded.clear(); embedded.write(json.dumps(payload,ensure_ascii=False))

if any(r.get('stairwellSettings',{}).get('profile')=='original-v013' for r in payload.get('components',[])):
    from pathlib import Path
    palette_path=Path(__file__).resolve().parents[3]/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
    shared=MATERIALS['建筑']; shared.name='02_细腻哑光_青绿大面'; shared.use_nodes=True
    nodes=shared.node_tree.nodes
    shader=nodes.get('Principled BSDF'); shader.inputs['Roughness'].default_value=.7
    uvnode=nodes.new('ShaderNodeUVMap'); uvnode.uv_map='PaletteUV'
    texture=nodes.new('ShaderNodeTexImage'); texture.image=bpy.data.images.load(str(palette_path),check_existing=True); texture.interpolation='Closest'
    shared.node_tree.links.new(uvnode.outputs['UV'],texture.inputs['Vector'])
    shared.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    for mesh in set(o.data for o in bpy.context.scene.objects if o.type=='MESH'):
        while mesh.uv_layers: mesh.uv_layers.remove(mesh.uv_layers[0])
        uv=mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active=uv; uv.active_render=True
        for face in mesh.polygons:
            for i,index in enumerate(face.loop_indices):
                angle=2*math.pi*i/face.loop_total
                uv.data[index].uv=(.45+.022*math.cos(angle),.65+.022*math.sin(angle))
    used={mat for obj in bpy.context.scene.objects if obj.type=='MESH' for mat in obj.data.materials}
    for mat in list(bpy.data.materials):
        if mat not in used: bpy.data.materials.remove(mat)

bpy.context.scene["3dgame_design_scene"] = scene_name
bpy.context.scene["3dgame_design_schema_version"] = payload.get("version", 3)
bpy.context.scene["coordinate_system"] = "blender-z-up"
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(output_blend), check_existing=False)
print(json.dumps({"blend": os.path.abspath(output_blend), "components": len(payload.get("components", []))}, ensure_ascii=False))
