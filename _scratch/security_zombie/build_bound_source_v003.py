import bpy, os, math, hashlib, json
from pathlib import Path
from mathutils import Vector, Matrix

P = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
FBX = P / "_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx"
JPG = P / "_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbm/安保警卫3d模型_basecolor.JPEG"
OUT = P / "assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v003.blend"
REPORT = P / "_scratch/security_zombie/bound_source_v003_report.json"
TARGET_H = 1.857143
R = Matrix.Rotation(math.radians(90.0), 3, 'Z')  # new FBX +X front -> contract +Y front

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(FBX))
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == 'ARMATURE')
mesh = next(o for o in scene.objects if o.type == 'MESH')

# Freeze imported object transforms before editing data. Mesh and armature may
# have different FBX object matrices; bake each one into its own data first.
mesh_mw = mesh.matrix_world.copy()
arm_mw = arm.matrix_world.copy()
# Remove the imported parent/inverse relationship only after capturing world space.
# This prevents baking the armature transform twice while preserving skin alignment.
mesh.parent = None
mesh.matrix_parent_inverse.identity()
mesh.matrix_world = mesh_mw
mesh.data.transform(mesh.matrix_world)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.head = arm_mw @ eb.head
    eb.tail = arm_mw @ eb.tail
bpy.ops.object.mode_set(mode='OBJECT')
mesh.matrix_world.identity()
arm.matrix_world.identity()

# Transform mesh and the imported rest skeleton together: this preserves the new FBX binding.
for v in mesh.data.vertices:
    v.co = R @ v.co
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.head = R @ eb.head
    eb.tail = R @ eb.tail
bpy.ops.object.mode_set(mode='OBJECT')

# Normalize world height and place feet at z=0, applying identical transforms to mesh and rest bones.
lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
for v in mesh.data.vertices:
    lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
    hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
s = TARGET_H / (hi.z - lo.z)
center_x = (lo.x + hi.x) * 0.5
center_y = (lo.y + hi.y) * 0.5
offset = Vector((center_x, center_y, lo.z))
for v in mesh.data.vertices:
    v.co = (v.co - offset) * s
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.head = (eb.head - offset) * s
    eb.tail = (eb.tail - offset) * s
bpy.ops.object.mode_set(mode='OBJECT')

# Add the missing finger bones to the new bound skeleton. Existing imported skeleton is retained.
# Hand-local directions are derived from each imported hand's palm axis and a stable spread basis.
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
ebones = arm.data.edit_bones
finger_specs = [('Thumb', -0.24, 0.030), ('Index', -0.10, 0.046), ('Middle', 0.00, 0.050), ('Pinky', 0.16, 0.040)]
for side, hand_name, sign in [('L', 'L_Hand', -1.0), ('R', 'R_Hand', 1.0)]:
    hand = ebones[hand_name]
    h = hand.head.copy(); t = hand.tail.copy()
    palm = (t - h).normalized()
    # For this imported rig, the fingers extend approximately along the hand tail direction.
    forward = palm
    side_axis = Vector((1, 0, 0)) * sign
    up = Vector((0, 0, 1))
    if abs(forward.dot(up)) > 0.9:
        up = Vector((0, 1, 0))
    across = up.cross(forward).normalized() * sign
    for finger, offset, length in finger_specs:
        base = h + forward * 0.012 + across * offset
        if finger == 'Thumb':
            base = h + forward * 0.004 + up * 0.014 + across * (-0.22)
            direction = (forward * 0.55 + up * 0.45 + across * (-0.35)).normalized()
        else:
            direction = (forward * 0.95 + up * (-0.10)).normalized()
        b1 = ebones.new(f'{side}_{finger}1')
        b1.head = base; b1.tail = base + direction * length; b1.parent = hand; b1.use_connect = False
        b2 = ebones.new(f'{side}_{finger}2')
        b2.head = b1.tail; b2.tail = b2.head + direction * (length * 0.78); b2.parent = b1; b2.use_connect = True
bpy.ops.object.mode_set(mode='OBJECT')

# Ensure armature modifier points to the retained imported armature.
mesh.parent = arm
for mod in mesh.modifiers:
    if mod.type == 'ARMATURE':
        mod.object = arm
        mod.use_vertex_groups = True
        break
else:
    mod = mesh.modifiers.new('Armature', 'ARMATURE'); mod.object = arm; mod.use_vertex_groups = True

# Internal names and packed source texture.
arm.name = 'enm_ranged_sporeshooter01_armature'
arm.data.name = 'enm_ranged_sporeshooter01_armature'
arm.data['skeleton_id'] = 'SKEL-MELEE-FUNGBOAR01-002-EXTENDED'
mesh.name = 'enm_ranged_sporeshooter01_mesh'
mesh.data.name = 'enm_ranged_sporeshooter01_mesh'
for mat in mesh.data.materials:
    if mat:
        mat.name = 'enm_ranged_sporeshooter01_mat'
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                try:
                    if node.image:
                        bpy.data.images.remove(node.image)
                except RuntimeError:
                    pass
                img = bpy.data.images.load(str(JPG), check_existing=False)
                img.name = 'enm_ranged_sporeshooter01_basecolor'
                img.colorspace_settings.name = 'sRGB'
                img.pack()
                img.filepath = '//textures/enm_ranged_sporeshooter01_basecolor_v002.jpeg'
                node.image = img

# Clean scene extras; retain only bound mesh and armature.
for o in list(scene.objects):
    if o not in (mesh, arm): bpy.data.objects.remove(o, do_unlink=True)
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
bpy.context.view_layer.update()

# Diagnostics.
lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
for v in mesh.data.vertices:
    w = mesh.matrix_world @ v.co
    lo = Vector((min(lo.x,w.x), min(lo.y,w.y), min(lo.z,w.z)))
    hi = Vector((max(hi.x,w.x), max(hi.y,w.y), max(hi.z,w.z)))
weights = []
for v in mesh.data.vertices:
    weights.append(sum(g.weight for g in v.groups))
report = {
    'source_fbx': str(FBX), 'output_blend': str(OUT),
    'armature': arm.name, 'mesh': mesh.name,
    'skeleton_id': arm.data.get('skeleton_id'),
    'bone_count': len(arm.data.bones), 'vertex_group_count': len(mesh.vertex_groups),
    'bones': [b.name for b in arm.data.bones],
    'bbox': [hi.x-lo.x, hi.y-lo.y, hi.z-lo.z], 'min': list(lo), 'max': list(hi),
    'unbound_vertices': sum(1 for x in weights if x < 1e-4),
    'weight_sum_bad': sum(1 for x in weights if abs(x-1.0) > 1e-3),
    'forward_contract': 'Blender +Y',
    'added_bones': ['L_Thumb1','L_Thumb2','L_Index1','L_Index2','L_Middle1','L_Middle2','L_Pinky1','L_Pinky2','R_Thumb1','R_Thumb2','R_Index1','R_Index2','R_Middle1','R_Middle2','R_Pinky1','R_Pinky2'],
}
if report['unbound_vertices'] or report['weight_sum_bad']:
    raise RuntimeError(report)
bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('BOUND_SOURCE_V003_OK', json.dumps(report, ensure_ascii=False))
