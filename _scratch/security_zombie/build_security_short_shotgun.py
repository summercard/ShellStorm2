import bpy, math, json, shutil
from pathlib import Path
from mathutils import Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
OUT = P/'assets/art/weapons/weapon_3d/source/security_short_shotgun/wpn_security_short_shotgun_source_v001.blend'
REPORT = P/'_scratch/security_zombie/security_short_shotgun_report.json'

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'BLENDER_WORKBENCH'

# Collections: source components, game output, sockets, display environment.
root = bpy.data.collections.new('WPN_SECURITY_SHORT_SHOTGUN_警察短霰弹枪_中文资产管理')
scene.collection.children.link(root)
components = bpy.data.collections.new('01_制作组件_已统一材质'); root.children.link(components)
output = bpy.data.collections.new('02_游戏输出_整合模型'); root.children.link(output)
sockets = bpy.data.collections.new('80_挂点_交互接口'); root.children.link(sockets)
env = bpy.data.collections.new('90_展示环境_灯光相机'); root.children.link(env)

# Materials: three weapon roles only.
def mat(name, color, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.metallic = metallic
    m.roughness = rough
    return m
metal = mat('01_精工金属_枪身骨架', (0.10, 0.13, 0.15), 0.82, 0.28)
matte = mat('02_细腻哑光_枪身大面', (0.22, 0.25, 0.23), 0.12, 0.58)
clear = mat('03_清漆反光_枪身点缀', (0.42, 0.16, 0.08), 0.45, 0.24)

# Helpers; gun local -Z points forward. X width, Y up, Z along body.
def cube(name, loc, scale, material, coll=output, bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name
    o.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('边缘倒角', 'BEVEL'); mod.width = bevel; mod.segments = 2
    o.data.materials.append(material)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    return o

def cyl(name, loc, radius, depth, material, coll=output, rot=(math.pi/2,0,0), vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; o.data.materials.append(material)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    return o

def uv_sphere(name, loc, scale, material, coll=output):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    return o

def socket(name, loc, rot=(0,0,0)):
    o = bpy.data.objects.new(name, None); sockets.objects.link(o)
    o.empty_display_type = 'ARROWS'; o.empty_display_size = 0.07
    o.location = loc; o.rotation_euler = rot
    return o

# WeaponRoot at main hand grip. Barrel points local -Z; model is authored around this root.
root_obj = bpy.data.objects.new('WeaponRoot', None); output.objects.link(root_obj)
root_obj.empty_display_type = 'CUBE'; root_obj.empty_display_size = 0.08
# Compact tactical shotgun: 0.72m overall, stock to muzzle along -Z.
# Grip at origin, receiver extends forward (negative Z), muzzle at -0.60.
cube('wpn_security_short_shotgun_receiver', (0, 0.02, -0.16), (0.15, 0.18, 0.28), metal, output, 0.025)
cube('wpn_security_short_shotgun_stock', (0, 0.03, 0.13), (0.11, 0.15, 0.28), matte, output, 0.025)
cube('wpn_security_short_shotgun_grip', (0, -0.07, 0.035), (0.10, 0.22, 0.10), matte, output, 0.02)
# short pump and barrel
cyl('wpn_security_short_shotgun_barrel', (0, 0.07, -0.48), 0.045, 0.55, metal, output, rot=(0,0,0), vertices=20)
cube('wpn_security_short_shotgun_pump', (0, -0.01, -0.30), (0.14, 0.11, 0.19), clear, output, 0.018)
cyl('wpn_security_short_shotgun_muzzle_ring', (0, 0.07, -0.73), 0.065, 0.045, clear, output, rot=(0,0,0), vertices=20)
# side shells and sight
for x in (-0.09, 0.09):
    cyl('wpn_security_short_shotgun_shell_%s' % ('L' if x < 0 else 'R'), (x, 0.02, -0.10), 0.028, 0.12, clear, output, rot=(math.pi/2,0,0), vertices=16)
cube('wpn_security_short_shotgun_front_sight', (0, 0.15, -0.50), (0.025, 0.045, 0.07), clear, output, 0.005)

# Parent all geometry to WeaponRoot while preserving transforms.
for o in [x for x in output.objects if x != root_obj and x.type == 'MESH']:
    mw = o.matrix_world.copy(); o.parent = root_obj; o.matrix_world = mw

# Sockets are children of root; local -Z is barrel direction.
grip = socket('GripSocket', (0, 0, 0), (0,0,0)); grip.parent = root_obj
grip['contract'] = 'main hand palm; same transform as WeaponRoot'
support = socket('SupportHandSocket', (0, 0.0, -0.31), (0,0,0)); support.parent = root_obj
support['contract'] = 'off hand under pump / fore-end'
muzzle = socket('MuzzleSocket', (0, 0.07, -0.755), (0,0,0)); muzzle.parent = root_obj
muzzle['contract'] = 'true muzzle; local -Z trajectory'
for name, loc in [('MuzzleAttachmentSocket',(0,0.07,-0.75)),('ScopeSocket',(0,0.15,-0.30)),('MagazineSocket',(0,-0.08,-0.12)),('StockSocket',(0,0.03,0.27)),('TacticalSocket',(0.09,0.02,-0.20)),('MutatorSocket',(0,-0.02,-0.42))]:
    s = socket(name, loc); s.parent = root_obj

# Metadata on root.
root_obj['asset_id'] = 'WPN-GUN-SECURITY-SHORT-SHOTGUN'
root_obj['logic_id'] = 'security_short_shotgun'
root_obj['display_name_zh'] = '警察短霰弹枪'
root_obj['weapon_class'] = 'shotgun'
root_obj['dimensions_m'] = '0.18×0.18×0.80m'
root_obj['forward'] = 'local -Z'
root_obj['animation_tier'] = 'tier_1_articulated'
root_obj['authoring_note'] = '独立敌人道具；不复制玩家双管炮；不包含角色手臂与玩法数值。'

# Simple action for pump/receiver recoil, local presentation only.
scene.frame_start = 1; scene.frame_end = 8; scene.render.fps = 30
root_obj.animation_data_create()
act = bpy.data.actions.new('fire_pump_cycle'); act.use_fake_user = True
root_obj.animation_data.action = act
for f, z in [(1,0.0),(2,0.018),(4,0.035),(6,0.012),(8,0.0)]:
    root_obj.location.z = z; root_obj.keyframe_insert('location', frame=f)
root_obj.location.z = 0.0
for fc in act.fcurves:
    for kp in fc.keyframe_points: kp.interpolation = 'BEZIER'

# Hide display environment from export.
bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))

report = {'output': str(OUT), 'asset_id': root_obj['asset_id'], 'logic_id': root_obj['logic_id'],
          'display_name_zh': root_obj['display_name_zh'], 'dimensions_m': root_obj['dimensions_m'],
          'forward': root_obj['forward'], 'sockets': [x.name for x in sockets.objects],
          'materials': [metal.name, matte.name, clear.name], 'actions': [act.name],
          'mesh_count': len([o for o in output.objects if o.type == 'MESH'])}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('SECURITY_SHORT_SHOTGUN_OK', json.dumps(report, ensure_ascii=False))
