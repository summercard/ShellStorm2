import bpy, math, json
from pathlib import Path
from mathutils import Matrix, Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
FBX = P/'_scratch/security_zombie/police_source/tripo_convert_f72ff985-096a-4f37-8d40-5455761bf423.fbx'
JPG = P/'_scratch/security_zombie/police_source/tripo_convert_f72ff985-096a-4f37-8d40-5455761bf423.fbm/警察僵尸_basecolor.JPEG'
OUT = P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend'
REPORT = P/'_scratch/security_zombie/model_v005_report.json'
TARGET_H = 1.857143

# Mixamo -> melee contract. Applied AFTER the 180 deg yaw correction, because that
# rotation moves Mixamo's Left (raw +X) onto melee's L side (contract -X).
BONE_MAP = {
    'mixamorig:Hips': 'Hip',
    'mixamorig:Spine': 'Waist',
    'mixamorig:Spine2': 'Spine02',
    'mixamorig:Neck': 'Neck',
    'mixamorig:Head': 'Head',
    'mixamorig:LeftShoulder': 'L_Clavicle',
    'mixamorig:LeftArm': 'L_Upperarm',
    'mixamorig:LeftForeArm': 'L_Forearm',
    'mixamorig:LeftHand': 'L_Hand',
    'mixamorig:RightShoulder': 'R_Clavicle',
    'mixamorig:RightArm': 'R_Upperarm',
    'mixamorig:RightForeArm': 'R_Forearm',
    'mixamorig:RightHand': 'R_Hand',
    'mixamorig:LeftUpLeg': 'L_Thigh',
    'mixamorig:LeftLeg': 'L_Calf',
    'mixamorig:LeftFoot': 'L_Foot',
    'mixamorig:RightUpLeg': 'R_Thigh',
    'mixamorig:RightLeg': 'R_Calf',
    'mixamorig:RightFoot': 'R_Foot',
    'mixamorig:LeftHandThumb1': 'L_Thumb1',
    'mixamorig:LeftHandThumb2': 'L_Thumb2',
    'mixamorig:LeftHandIndex1': 'L_Index1',
    'mixamorig:LeftHandIndex2': 'L_Index2',
    'mixamorig:LeftHandMiddle1': 'L_Middle1',
    'mixamorig:LeftHandMiddle2': 'L_Middle2',
    'mixamorig:LeftHandPinky1': 'L_Pinky1',
    'mixamorig:LeftHandPinky2': 'L_Pinky2',
    'mixamorig:RightHandThumb1': 'R_Thumb1',
    'mixamorig:RightHandThumb2': 'R_Thumb2',
    'mixamorig:RightHandIndex1': 'R_Index1',
    'mixamorig:RightHandIndex2': 'R_Index2',
    'mixamorig:RightHandMiddle1': 'R_Middle1',
    'mixamorig:RightHandMiddle2': 'R_Middle2',
    'mixamorig:RightHandPinky1': 'R_Pinky1',
    'mixamorig:RightHandPinky2': 'R_Pinky2',
}
# Bones with no melee counterpart stay on the rig (binding untouched) under a clean
# non-contract name, so nothing silently looks like a contract bone.
EXTRA_MAP = {
    'mixamorig:Spine1': 'Spine01',
    'mixamorig:HeadTop_End': 'HeadTop_End',
    'mixamorig:LeftToeBase': 'L_ToeBase',
    'mixamorig:RightToeBase': 'R_ToeBase',
    'mixamorig:LeftToe_End': 'L_Toe_End',
    'mixamorig:RightToe_End': 'R_Toe_End',
}
for side in ('Left', 'Right'):
    s = 'L' if side == 'Left' else 'R'
    for f, n in (('Thumb', (3, 4)), ('Index', (3, 4)), ('Middle', (3, 4)), ('Pinky', (3, 4)), ('Ring', (1, 2, 3, 4))):
        for i in n:
            EXTRA_MAP['mixamorig:%sHand%s%d' % (side, f, i)] = '%s_%s%d' % (s, f, i)
NAME_MAP = dict(BONE_MAP); NAME_MAP.update(EXTRA_MAP)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(FBX))
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == 'ARMATURE')
mesh = next(o for o in scene.objects if o.type == 'MESH')

if mesh.parent is not arm:
    raise RuntimeError('unexpected mesh parent')

# Bake object matrices into data, then drop the parenting temporarily so the mesh
# does not absorb the armature transform twice.
mesh_mw = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_parent_inverse.identity()
mesh.matrix_world = mesh_mw
mesh.data.transform(mesh.matrix_world)
mesh.matrix_world.identity()

arm_mw = arm.matrix_world.copy()
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.matrix = arm_mw @ eb.matrix
bpy.ops.object.mode_set(mode='OBJECT')
arm.matrix_world.identity()

# --- orientation: raw front is -Y, contract front is +Y ---
R = Matrix.Rotation(math.pi, 3, 'Z')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
snap = {eb.name: eb.matrix.copy() for eb in arm.data.edit_bones}
for eb in arm.data.edit_bones:
    eb.matrix = R.to_4x4() @ snap[eb.name]
bpy.ops.object.mode_set(mode='OBJECT')
for v in mesh.data.vertices:
    v.co = R @ v.co
mesh.data.update()

# --- size calibration: uniform scale to contract source height, feet on z=0, centred ---
lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
for v in mesh.data.vertices:
    for i in range(3):
        lo[i] = min(lo[i], v.co[i]); hi[i] = max(hi[i], v.co[i])
scale = TARGET_H / (hi.z - lo.z)
offset = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
FIT = Matrix.Scale(scale, 4) @ Matrix.Translation(-offset)
bpy.ops.object.mode_set(mode='EDIT')
snap = {eb.name: eb.matrix.copy() for eb in arm.data.edit_bones}
for eb in arm.data.edit_bones:
    eb.matrix = FIT @ snap[eb.name]
# add melee's Root bone (origin, pointing up) as the parent of Hip
root = arm.data.edit_bones.new('Root')
root.head = Vector((0.0, 0.0, 0.0))
root.tail = Vector((0.0, 0.0, 0.12))
root.roll = math.pi
arm.data.edit_bones['mixamorig:Hips'].parent = root
arm.data.edit_bones['mixamorig:Hips'].use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
for v in mesh.data.vertices:
    v.co = FIT @ v.co
mesh.data.update()

# --- rename bones AND vertex groups: the armature modifier matches by name ---
renamed_bones, renamed_groups = 0, 0
for old, new in NAME_MAP.items():
    b = arm.data.bones.get(old)
    if b is not None:
        b.name = new
        renamed_bones += 1
for g in mesh.vertex_groups:
    if g.name in NAME_MAP:
        g.name = NAME_MAP[g.name]
        renamed_groups += 1

# --- texture: pack the source JPEG into the file ---
for mat in mesh.data.materials:
    if not mat or not mat.node_tree:
        continue
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            img = bpy.data.images.load(str(JPG), check_existing=False)
            img.name = 'enm_ranged_sporeshooter01_basecolor'
            img.colorspace_settings.name = 'sRGB'
            img.pack()
            img.filepath = '//textures/enm_ranged_sporeshooter01_basecolor_v003.jpeg'
            node.image = img

arm.name = 'enm_ranged_sporeshooter01_armature'
arm.data.name = 'enm_ranged_sporeshooter01_armature'
arm.data['skeleton_id'] = 'SKEL-MELEE-FUNGBOAR01-002'
arm.data['bone_contract'] = 'melee_chaser redirect'
mesh.name = 'enm_ranged_sporeshooter01_mesh'
mesh.data.name = 'enm_ranged_sporeshooter01_mesh'
for mat in mesh.data.materials:
    if mat:
        mat.name = 'enm_ranged_sporeshooter01_mat'

mesh.parent = arm
mesh.matrix_parent_inverse.identity()
for o in list(scene.objects):
    if o not in (arm, mesh):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()

# --- verification: binding intact, names aligned, animation actually deforms ---
bone_names = [b.name for b in arm.data.bones]
contract = ['Root','Hip','Waist','Spine02','Neck','Head',
            'L_Clavicle','L_Upperarm','L_Forearm','L_Hand',
            'L_Thumb1','L_Thumb2','L_Index1','L_Index2','L_Middle1','L_Middle2','L_Pinky1','L_Pinky2',
            'R_Clavicle','R_Upperarm','R_Forearm','R_Hand',
            'R_Thumb1','R_Thumb2','R_Index1','R_Index2','R_Middle1','R_Middle2','R_Pinky1','R_Pinky2',
            'L_Thigh','L_Calf','L_Foot','R_Thigh','R_Calf','R_Foot']
missing = [n for n in contract if n not in bone_names]
group_names = [g.name for g in mesh.vertex_groups]
bad_groups = [g for g in group_names if g not in bone_names]
weights = [sum(g.weight for g in v.groups) for v in mesh.data.vertices]
unbound = sum(1 for w in weights if w < 1e-4)
bad_sum = sum(1 for w in weights if abs(w - 1.0) > 1e-3)

# deformation probe: rotating an arm bone must move the mesh
dg = bpy.context.evaluated_depsgraph_get()
before = [v.co.copy() for v in mesh.evaluated_get(dg).data.vertices]
arm.pose.bones['L_Upperarm'].rotation_mode = 'QUATERNION'
arm.pose.bones['L_Upperarm'].rotation_quaternion = (0.9239, 0.3827, 0.0, 0.0)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
after = [v.co.copy() for v in mesh.evaluated_get(dg).data.vertices]
moved = sum(1 for a, b2 in zip(before, after) if (a - b2).length > 1e-4)
arm.pose.bones['L_Upperarm'].rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
bpy.context.view_layer.update()

final_lo = Vector((1e9,)*3); final_hi = Vector((-1e9,)*3)
for v in mesh.data.vertices:
    w = mesh.matrix_world @ v.co
    for i in range(3):
        final_lo[i] = min(final_lo[i], w[i]); final_hi[i] = max(final_hi[i], w[i])

report = {
    'source_fbx': str(FBX), 'output_blend': str(OUT),
    'armature': arm.name, 'mesh': mesh.name,
    'skeleton_id': arm.data.get('skeleton_id'),
    'bone_count': len(bone_names), 'bones': bone_names,
    'vertex_group_count': len(group_names),
    'contract_missing': missing,
    'unbound_vertices': unbound, 'weight_sum_bad': bad_sum,
    'groups_not_matching_bone': bad_groups,
    'renamed_bones': renamed_bones, 'renamed_groups': renamed_groups,
    'pose_probe_moved_vertices': moved,
    'scale_applied': scale,
    'bbox_size': [round(final_hi[i]-final_lo[i], 4) for i in range(3)],
    'bbox_min': [round(c, 4) for c in final_lo],
    'bbox_max': [round(c, 4) for c in final_hi],
    'forward_contract': 'Blender +Y',
}
fails = []
if missing: fails.append('contract bones missing: %s' % missing)
if unbound: fails.append('unbound vertices: %d' % unbound)
if bad_sum: fails.append('weight sum bad: %d' % bad_sum)
if bad_groups: fails.append('groups without bone: %s' % bad_groups)
if moved < 50: fails.append('pose probe moved only %d vertices' % moved)
if abs(report['bbox_size'][2] - TARGET_H) > 1e-3: fails.append('height off')
report['failures'] = fails
if fails:
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    raise RuntimeError(fails)

bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('MODEL_V005_OK bones=%d groups=%d height=%.4f moved=%d' % (
    len(bone_names), len(group_names), report['bbox_size'][2], moved))
