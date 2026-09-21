# -*- coding: utf-8 -*-
"""
refine_security_shotgun_v002.py
生成 wpn_security_short_shotgun_source_v002.blend
目标：警察僵尸双手持短霰弹枪（独立敌人道具，不碰角色脚本/源，不改动玩法）。
改进相对 v001：
  - 真实几何总长约 0.60m（v001 标 0.80 实际 1.025）
  - WeaponRoot/GripSocket 原点在握把掌心，局部 -Z 前 / +Y 上
  - GripSocket 在握把掌心，SupportHandSocket 在前护木（距握把约 0.24m），尺寸按 1.857m 角色小手
  - 3 个枪械材质角色、外链公共色盘、PaletteUV 唯一活动层
  - 移除整根 WeaponRoot 位移动画；tier1 pump 独立对象动作 fire_pump_cycle（0->+0.045 后拉->0）
  - SupportHandSocket 随 pump（pump 子级）
  - 无自发光、所有 scale=1、枪口黑色凹口视觉
  - 真实测量 bbox 并记录（非固定字符串）
  - 独立可供角色链接的集合 SECURITY_SHOTGUN_REFERENCE（含网格/根/挂点，无相机地面），根无父级，动画默认停 1 帧
运行：blender --factory-startup --background --python-exit-code 1 refine_security_shotgun_v002.py
"""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector, Matrix

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
OUT = P/'assets/art/weapons/weapon_3d/source/security_short_shotgun/wpn_security_short_shotgun_source_v002.blend'
PALETTE = P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
REPORT = P/'_scratch/security_zombie/security_short_shotgun_v002_report.json'

V002_COLLECTION = 'SECURITY_SHOTGUN_REFERENCE'

def fail(msg):
    print('REFINE_FAIL:', msg)
    sys.exit(1)

# ---------- 场景基础 ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'BLENDER_WORKBENCH'
scene.frame_start = 1
scene.frame_end = 8
scene.frame_set(1)
scene.render.fps = 30

# 清掉 factory 默认对象（cube/camera/light），参考集合不含相机地面
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

# ---------- 外链公共色盘 ----------
if not PALETTE.exists():
    fail('palette missing: %s' % PALETTE)
palette_img = bpy.data.images.load(str(PALETTE).replace('\\','/'))
palette_img.alpha_mode = 'NONE'

# 色盘安全内区：cell=0.1，留边 0.012
CELL = 0.1
MARGIN = 0.012
def safe_rect(col, row):
    u0 = col*CELL + MARGIN
    v0 = row*CELL + MARGIN
    w = CELL - 2*MARGIN
    return u0, v0, w

# 选格（来自 sample_palette.py 实测）
# steel  (9,4)=0.36,0.43,0.51 ; matte dark-blue (0,3)=0.02,0.07,0.16
# accent blue (4,3)=0.07,0.18,0.42 ; muzzle dark (9,9)=0.11,0.14,0.20
CELLS = {
    'steel': (9,4), 'matte': (0,3), 'accent': (4,3), 'muzzle_dark': (9,9),
}
CELL_RGB = {
    'steel': (0.36,0.43,0.51), 'matte': (0.02,0.07,0.16),
    'accent': (0.07,0.18,0.42), 'muzzle_dark': (0.11,0.14,0.20),
}

MAT_NAMES = {1:'01_精工金属_枪身骨架', 2:'02_细腻哑光_枪身大面', 3:'03_清漆反光_枪身点缀'}

def make_material(role, key, metallic, roughness, clearcoat=0.0):
    m = bpy.data.materials.new(MAT_NAMES[role])
    m.use_nodes = True
    m.use_fake_user = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = palette_img
    tex.interpolation = 'Closest'
    uv = nt.nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'PaletteUV'
    nt.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if clearcoat > 0:
        bsdf.inputs['Coat Weight'].default_value = clearcoat
        bsdf.inputs['Coat Roughness'].default_value = 0.08
    # 无自发光
    bsdf.inputs['Emission Color'].default_value = (0.0,0.0,0.0,1.0)
    bsdf.inputs['Emission Strength'].default_value = 0.0
    col = CELL_RGB[key]
    m.diffuse_color = (col[0], col[1], col[2], 1.0)
    return m

mat_metal = make_material(1, 'steel', metallic=0.82, roughness=0.30)
mat_matte = make_material(2, 'matte', metallic=0.12, roughness=0.62)
mat_clear = make_material(3, 'accent', metallic=0.45, roughness=0.26, clearcoat=1.0)
# 枪口凹口复用金属材质，仅 UV 落深色格 -> 不新增材质球
mat_muzzle = mat_metal

# ---------- 参考集合结构（供角色链接） ----------
root_coll = bpy.data.collections.new(V002_COLLECTION)
scene.collection.children.link(root_coll)
coll_components = bpy.data.collections.new('01_制作组件_已统一材质'); root_coll.children.link(coll_components); coll_components.hide_viewport = True; coll_components.hide_render = True
coll_output = bpy.data.collections.new('02_游戏输出_整合模型'); root_coll.children.link(coll_output)
coll_sockets = bpy.data.collections.new('80_挂点_交互接口'); root_coll.children.link(coll_sockets)

# ---------- 几何辅助 ----------
def set_world_loc(o, parent, loc):
    # 显式设定子级的世界位置（直接写 matrix_local），重载后稳定
    bpy.context.view_layer.update()
    t = Matrix.Translation(loc)
    if parent is not None:
        o.matrix_local = parent.matrix_world.inverted() @ t
    else:
        o.matrix_local = t

def add_cube(name, loc, size, mat, coll, parent=None, bevel=0.012):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('边缘倒角', 'BEVEL'); mod.width = bevel; mod.segments = 2; mod.harden_normals = True
    o.data.materials.append(mat)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    if parent: o.parent = parent
    set_world_loc(o, parent, loc)
    return o

def add_cyl(name, loc, radius, depth, mat, coll, rot=(0,0,0), verts=28, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.materials.append(mat)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    if parent: o.parent = parent
    set_world_loc(o, parent, loc)
    return o

def add_socket(name, loc, parent, coll=coll_sockets, rot=(0,0,0)):
    o = bpy.data.objects.new(name, None); coll.objects.link(o)
    o.empty_display_type = 'ARROWS'; o.empty_display_size = 0.05
    o.rotation_euler = rot
    if parent: o.parent = parent
    set_world_loc(o, parent, loc)
    return o

# ---------- WeaponRoot（无父级，原点=握把掌心） ----------
weapon_root = bpy.data.objects.new('WeaponRoot', None)
coll_output.objects.link(weapon_root)
weapon_root.empty_display_type = 'ARROWS'; weapon_root.empty_display_size = 0.06
weapon_root.location = (0,0,0)
assert weapon_root.parent is None, 'WeaponRoot 必须无父级'

# 局部坐标：+X 右，+Y 上，-Z 前（枪口方向），+Z 后（枪托方向）
# 总体目标 ~0.60m：枪托后端 +0.21，枪口前端 -0.38

# 1) 握把（哑光，主手握持）掌心处即原点
grip = add_cube('wpn_security_short_shotgun_grip', (0, -0.05, 0.01), (0.045, 0.13, 0.05), mat_matte, coll_output, parent=weapon_root, bevel=0.012)
# 2) 机匣/主体（金属，钢色）位于握把前方
receiver = add_cube('wpn_security_short_shotgun_receiver', (0, 0.04, -0.08), (0.05, 0.105, 0.20), mat_metal, coll_output, parent=weapon_root, bevel=0.014)
# 3) 枪托（哑光，后端抵肩）位于握把后上方
stock = add_cube('wpn_security_short_shotgun_stock', (0, 0.05, 0.12), (0.045, 0.085, 0.18), mat_matte, coll_output, parent=weapon_root, bevel=0.014)
# 4) 短枪管（金属，钢色）位于机匣前方、上方
barrel = add_cyl('wpn_security_short_shotgun_barrel', (0, 0.075, -0.26), 0.022, 0.20, mat_metal, coll_output, rot=(0,0,0), verts=28, parent=weapon_root)
# 5) 枪口环（清漆点缀，蓝色）枪口外圈
muzzle_ring = add_cyl('wpn_security_short_shotgun_muzzle_ring', (0, 0.075, -0.355), 0.033, 0.03, mat_clear, coll_output, rot=(0,0,0), verts=28, parent=weapon_root)
# 6) 枪口凹口（金属材质，UV 落深色格 -> 黑色视觉）略缩进
muzzle_bore = add_cyl('wpn_security_short_shotgun_muzzle_bore', (0, 0.075, -0.365), 0.016, 0.04, mat_muzzle, coll_output, rot=(0,0,0), verts=24, parent=weapon_root)
# 7) 准星（清漆点缀）
front_sight = add_cube('wpn_security_short_shotgun_front_sight', (0, 0.13, -0.30), (0.02, 0.05, 0.06), mat_clear, coll_output, parent=weapon_root, bevel=0.004)
# 8) 侧面弹架（清漆点缀，左右各一）
for i, sx in enumerate((-0.06, 0.06)):
    add_cyl('wpn_security_short_shotgun_shell_%d' % i, (sx, 0.03, -0.05), 0.013, 0.09, mat_clear, coll_output, rot=(math.pi/2,0,0), verts=16, parent=weapon_root)
# 9) 扳机护圈（清漆点缀）
trigger = add_cube('wpn_security_short_shotgun_trigger_guard', (0, -0.005, -0.02), (0.03, 0.035, 0.045), mat_clear, coll_output, parent=weapon_root, bevel=0.006)

# 10) 泵/前护木（哑光）—— 独立可动对象，前护木，副手扶握处
pump = add_cube('wpn_security_short_shotgun_pump', (0, -0.01, -0.24), (0.06, 0.08, 0.15), mat_matte, coll_output, parent=weapon_root, bevel=0.012)

# ---------- PaletteUV（唯一活动层，逐面盒投影，整岛落在单格安全内区，皆有面积） ----------
def apply_palette_uv(obj, key):
    if obj.type != 'MESH': return
    me = obj.data
    # 仅保留 PaletteUV
    if 'PaletteUV' not in me.uv_layers:
        me.uv_layers.new(name='PaletteUV')
    for l in list(me.uv_layers):
        if l.name != 'PaletteUV':
            me.uv_layers.remove(l)
    layer = me.uv_layers['PaletteUV']
    me.uv_layers.active = layer
    col, row = CELLS[key]
    u0, v0, w = safe_rect(col, row)
    uv_out = [(u0 + w*0.5, v0 + w*0.5)] * len(me.loops)
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [i for i in (0, 1, 2) if i != ax]
        coords = [(me.vertices[vi].co[a], me.vertices[vi].co[b]) for vi in poly.vertices]
        mn0 = min(c[0] for c in coords); mx0 = max(c[0] for c in coords)
        mn1 = min(c[1] for c in coords); mx1 = max(c[1] for c in coords)
        d0 = (mx0 - mn0) or 1.0; d1 = (mx1 - mn1) or 1.0
        face_uv = {}
        for vi, c in zip(poly.vertices, coords):
            face_uv[vi] = (u0 + (c[0]-mn0)/d0*w, v0 + (c[1]-mn1)/d1*w)
        for li in poly.loop_indices:
            vid = me.loops[li].vertex_index
            uv_out[li] = face_uv[vid]
    for li, uv in enumerate(uv_out):
        layer.data[li].uv = uv
    # 再次确认唯一 & 活动
    for l in list(me.uv_layers):
        if l.name != 'PaletteUV':
            me.uv_layers.remove(l)
    me.uv_layers['PaletteUV'].active = True

# 各网格 -> 材质角色对应色格
uv_map = {
    'wpn_security_short_shotgun_grip':'matte',
    'wpn_security_short_shotgun_receiver':'steel',
    'wpn_security_short_shotgun_stock':'matte',
    'wpn_security_short_shotgun_barrel':'steel',
    'wpn_security_short_shotgun_muzzle_ring':'accent',
    'wpn_security_short_shotgun_muzzle_bore':'muzzle_dark',
    'wpn_security_short_shotgun_front_sight':'accent',
    'wpn_security_short_shotgun_shell_0':'accent',
    'wpn_security_short_shotgun_shell_1':'accent',
    'wpn_security_short_shotgun_trigger_guard':'accent',
    'wpn_security_short_shotgun_pump':'matte',
}
for name, key in uv_map.items():
    apply_palette_uv(bpy.data.objects[name], key)

# ---------- 挂点 ----------
# GripSocket 与主手同 transform（原点=握把掌心）
grip_socket = add_socket('GripSocket', (0,0,0), weapon_root)
grip_socket['contract'] = 'main hand palm; same transform as WeaponRoot'
# SupportHandSocket 在前护木可扶握处（世界坐标，随 pump 父化后保留世界变换）
support_socket = add_socket('SupportHandSocket', (0, 0.04, -0.24), pump, coll=coll_sockets)
support_socket['contract'] = 'off hand on fore-end/pump; follows pump'
# 其余玩法接口挂点（与运行时契约对齐，不改玩法）
add_socket('MuzzleSocket', (0, 0.075, -0.375), weapon_root)
add_socket('MuzzleAttachmentSocket', (0, 0.075, -0.37), weapon_root)
add_socket('ScopeSocket', (0, 0.13, -0.10), weapon_root)
add_socket('MagazineSocket', (0, -0.04, -0.05), weapon_root)
add_socket('StockSocket', (0, 0.05, 0.21), weapon_root)
add_socket('TacticalSocket', (0.06, 0.03, -0.18), weapon_root)
add_socket('MutatorSocket', (0, -0.02, -0.30), weapon_root)

# ---------- 元数据 ----------
weapon_root['asset_id'] = 'WPN-GUN-SECURITY-SHORT-SHOTGUN'
weapon_root['logic_id'] = 'security_short_shotgun'
weapon_root['display_name_zh'] = '警察短霰弹枪'
weapon_root['weapon_class'] = 'shotgun'
weapon_root['forward'] = 'local -Z'
weapon_root['animation_tier'] = 'tier_1_articulated'
weapon_root['authoring_note'] = '独立敌人道具；不复制玩家双管炮；不包含角色手臂与玩法数值。'
weapon_root['source_collection'] = V002_COLLECTION

# ---------- tier1 动画：pump 独立对象 fire_pump_cycle（0->+0.045 后拉->0） ----------
scene.frame_start = 1; scene.frame_end = 8; scene.frame_set(1)
pump.animation_data_create()
act = bpy.data.actions.new('fire_pump_cycle'); act.use_fake_user = True
pump.animation_data.action = act
# 后拉 = +Z（朝枪托方向），相对 pump 基准位置偏移峰值 +0.045m 后回 0
base = pump.location.copy()   # 基准局部位置 (0,-0.01,-0.24)；动画为相对偏移
for f, dz in [(1,0.0),(2,0.0),(4,0.045),(6,0.012),(8,0.0)]:
    pump.location = (base.x, base.y, base.z + dz)
    pump.keyframe_insert('location', frame=f)
pump.location = (base.x, base.y, base.z)   # 复位到基准
for fc in act.fcurves:
    for kp in fc.keyframe_points:
        kp.interpolation = 'BEZIER'
# 整根 WeaponRoot 不得有任何动画
if weapon_root.animation_data and weapon_root.animation_data.action:
    fail('WeaponRoot 不应带位移动画')
weapon_root.animation_data_clear() if weapon_root.animation_data else None

# ---------- 校验 ----------
# 1) 所有对象 scale==1
for o in list(coll_output.objects) + list(coll_sockets.objects):
    if any(abs(s-1.0) > 1e-4 for s in o.scale):
        fail('对象 scale 不为 1: %s' % o.name)
# 2) 仅 3 个材质角色 & 无自发光
mat_names = sorted(bpy.data.materials.keys())
expected = sorted(['01_精工金属_枪身骨架','02_细腻哑光_枪身大面','03_清漆反光_枪身点缀'])
if mat_names != expected:
    fail('材质角色集合不符: %s' % mat_names)
for m in bpy.data.materials:
    if m.use_nodes:
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        if bsdf and bsdf.inputs['Emission Strength'].default_value > 1e-4:
            fail('存在自发光材质: %s' % m.name)
# 3) PaletteUV 唯一且活动
for o in coll_output.objects:
    if o.type == 'MESH':
        layers = [l.name for l in o.data.uv_layers]
        if layers != ['PaletteUV']:
            fail('UV 层非唯一 PaletteUV: %s %s' % (o.name, layers))
        if o.data.uv_layers.active.name != 'PaletteUV':
            fail('PaletteUV 非活动层: %s' % o.name)
# 4) WeaponRoot 无父级、无动画
if weapon_root.parent is not None: fail('WeaponRoot 有父级')
if weapon_root.animation_data and weapon_root.animation_data.action: fail('WeaponRoot 带动作')
# 5) pump 独立动作 & SupportHandSocket 为 pump 子级
if not (pump.animation_data and pump.animation_data.action and pump.animation_data.action.name=='fire_pump_cycle'):
    fail('pump 缺少 fire_pump_cycle 动作')
if support_socket.parent != pump:
    fail('SupportHandSocket 必须随 pump')
# 6) 无 armature / 无相机 / 无灯光（不碰角色，参考集合不含相机地面）
for o in bpy.data.objects:
    if o.type == 'ARMATURE': fail('文件含 armature（不应出现）')
    if o.type == 'CAMERA' or o.type == 'LIGHT': fail('文件含相机/灯光')
# 7) 色盘外链（不内嵌）
if palette_img.packed_file is not None: fail('色盘被内嵌')

# ---------- 真实 bbox 测量（世界 & 相对 WeaponRoot） ----------
def measure(objs):
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3); any_=False
    for o in objs:
        if o.type != 'MESH': continue
        any_=True
        for c in o.bound_box:
            v = o.matrix_world @ Vector(c)
            mn = Vector(min(a,b) for a,b in zip(mn,v)); mx = Vector(max(a,b) for a,b in zip(mx,v))
    return mn, mx, any_

meshes = [o for o in coll_output.objects if o.type=='MESH']
wmn, wmx, _ = measure(meshes)
world_dims = [round(x,4) for x in (wmx - wmn)]
# 相对 WeaponRoot
lmn = Vector((1e9,)*3); lmx = Vector((-1e9,)*3)
for o in meshes:
    for c in o.bound_box:
        v = weapon_root.matrix_world.inverted() @ (o.matrix_world @ Vector(c))
        lmn = Vector(min(a,b) for a,b in zip(lmn,v)); lmx = Vector(max(a,b) for a,b in zip(lmx,v))
local_dims = [round(x,4) for x in (lmx - lmn)]
length_z = local_dims[2]
if not (0.50 <= length_z <= 0.66):
    fail('真实长度不在 0.50~0.66m 区间: %.4f' % length_z)

grip_local = [round(x,4) for x in grip_socket.location]
support_local = [round(x,4) for x in support_socket.matrix_world.to_translation() - weapon_root.matrix_world.to_translation()]
support_dist = round(math.sqrt(sum(x*x for x in support_local)),4)
if not (0.23 <= support_dist <= 0.26):
    fail('副手距握把不在 0.23~0.26m: %.4f' % support_dist)

# ---------- 保存 ----------
bpy.context.preferences.filepaths.save_version = 0
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))

report = {
    'output': str(OUT),
    'source_collection': V002_COLLECTION,
    'asset_id': weapon_root['asset_id'],
    'logic_id': weapon_root['logic_id'],
    'display_name_zh': weapon_root['display_name_zh'],
    'forward': 'local -Z',
    'world_bbox_min': [round(x,4) for x in wmn],
    'world_bbox_max': [round(x,4) for x in wmx],
    'world_dims_m': world_dims,
    'local_dims_m': local_dims,
    'measured_length_m': round(length_z,4),
    'grip_socket_local': grip_local,
    'support_hand_socket_local': support_local,
    'support_hand_distance_m': support_dist,
    'materials': mat_names,
    'palette': str(PALETTE),
    'palette_embedded': palette_img.packed_file is not None,
    'uv_layer_per_mesh': 'PaletteUV (only/active)',
    'mesh_count': len(meshes),
    'sockets': [s.name for s in coll_sockets.objects],
    'actions': [act.name],
    'animated_object': 'pump (independent, not WeaponRoot)',
    'support_follows_pump': True,
    'weapon_root_parented': False,
    'armature_in_file': False,
    'camera_in_file': False,
    'all_scale_one': True,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('REFINE_OK', json.dumps(report, ensure_ascii=False))
