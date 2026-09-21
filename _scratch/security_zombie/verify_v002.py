# -*- coding: utf-8 -*-
"""独立验收 v002：重新打开保存的文件，逐条核对契约。"""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector

P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
SRC = P/'assets/art/weapons/weapon_3d/source/security_short_shotgun/wpn_security_short_shotgun_source_v002.blend'
OUT = P/'_scratch/security_zombie/verify_v002_report.json'

errs = []
def check(cond, msg):
    if not cond: errs.append(msg)
    print(('PASS' if cond else 'FAIL'), msg)

bpy.ops.wm.open_mainfile(filepath=str(SRC))

# 集合
ref = bpy.data.collections.get('SECURITY_SHOTGUN_REFERENCE')
check(ref is not None, '源集合 SECURITY_SHOTGUN_REFERENCE 存在')
check('02_游戏输出_整合模型' in ref.children, '含 02_游戏输出_整合模型 子集合')
check('80_挂点_交互接口' in ref.children, '含 80_挂点_交互接口 子集合')
# 不含相机/地面（整个文件无 camera/light）
check(not any(o.type=='CAMERA' for o in bpy.data.objects), '文件中无相机')
check(not any(o.type=='LIGHT' for o in bpy.data.objects), '文件中无灯光')
check(not any(o.type=='ARMATURE' for o in bpy.data.objects), '文件中无 armature（未碰角色骨架）')

# 根/对象
wr = bpy.data.objects.get('WeaponRoot')
check(wr is not None, 'WeaponRoot 存在')
check(wr.parent is None, 'WeaponRoot 无父级')
check(not (wr.animation_data and wr.animation_data.action), 'WeaponRoot 无位移动画(action)')
# 全场景逐帧检查 WeaponRoot 不位移
scene = bpy.context.scene
base_loc = wr.matrix_world.translation.copy()
for f in range(scene.frame_start, scene.frame_end+1):
    scene.frame_set(f)
    if (wr.matrix_world.translation - base_loc).length > 1e-5:
        check(False, 'WeaponRoot 在第%d帧发生位移' % f); break
else:
    check(True, 'WeaponRoot 在所有帧保持静止(无位移)')

# 几何 & 集合归属
meshes = [o for o in ref.all_objects if o.type=='MESH']
check(len(meshes)==11, '网格数量=11 (实际 %d)' % len(meshes))
for o in meshes:
    check(o.name.startswith('wpn_security_short_shotgun_'), '网格命名规范: '+o.name)
    check(all(abs(s-1.0)<1e-4 for s in o.scale), 'scale=1: '+o.name)
    # UV 仅 PaletteUV 且活动
    layers=[l.name for l in o.data.uv_layers]
    check(layers==['PaletteUV'], '仅 PaletteUV 层: '+o.name+' -> '+str(layers))
    check(o.data.uv_layers.active.name=='PaletteUV', 'PaletteUV 活动: '+o.name)
    # 所有 UV 落在单一色格安全内区
    uv=o.data.uv_layers['PaletteUV']
    cells=set()
    min_dist_edge=1.0
    for p in uv.data:
        u,v=p.uv
        cu=int(math.floor(u*10)); cv=int(math.floor(v*10))
        cells.add((cu,cv))
        # 距当前格边界
        min_dist_edge=min(min_dist_edge, (u-cu/10), ((cu+1)/10-u), (v-cv/10), ((cv+1)/10-v))
    check(len(cells)==1, 'UV 完整落在单一色格: %s -> %s' % (o.name, cells))
    check(min_dist_edge>=0.008, 'UV 在安全内区(距边界>=0.008): %s -> %.4f' % (o.name, min_dist_edge))

# 材质
mats=sorted(bpy.data.materials.keys())
exp=sorted(['01_精工金属_枪身骨架','02_细腻哑光_枪身大面','03_清漆反光_枪身点缀'])
check(mats==exp, '仅 3 个枪械材质角色: '+str(mats))
for m in bpy.data.materials:
    if m.use_nodes:
        bsdf=m.node_tree.nodes.get('Principled BSDF')
        es=bsdf.inputs['Emission Strength'].default_value if 'Emission Strength' in bsdf.inputs else 0
        check(es<=1e-4, '无自发光: '+m.name)
        # 色盘外链 & Closest
        tex=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE']
        check(len(tex)==1 and tex[0].image is not None, '材质含外链色盘纹理: '+m.name)
        check(tex[0].interpolation=='Closest', '色盘 Closest 采样: '+m.name)
        check(tex[0].image.packed_file is None, '色盘未内嵌: '+m.name)

# 枪口黑色凹口：muzzle_bore 用金属材质且 UV 落在深色格 (9,9)
bore=bpy.data.objects.get('wpn_security_short_shotgun_muzzle_bore')
check(bore is not None, '枪口凹口网格存在')
if bore:
    uv=bore.data.uv_layers['PaletteUV']
    cu=int(math.floor(uv.data[0].uv[0]*10)); cv=int(math.floor(uv.data[0].uv[1]*10))
    check((cu,cv)==(9,9), '枪口凹口落在深色格(9,9): %s' % str((cu,cv)))
    check(abs(bore.location.z - (-0.365))<1e-3, '枪口凹口位于枪口(缩进)')

# 动画：pump 独立 fire_pump_cycle 0->0.045->0；SupportHandSocket 随 pump
pump=bpy.data.objects.get('wpn_security_short_shotgun_pump')
check(pump is not None, 'pump 对象存在')
check(pump.animation_data and pump.animation_data.action and pump.animation_data.action.name=='fire_pump_cycle', 'pump 带 fire_pump_cycle 动作')
if pump and pump.animation_data:
    fcs={fc.array_index:fc for fc in pump.animation_data.action.fcurves if fc.data_path=='location'}
    zf=fcs.get(2)
    vals={kp.co[0]:kp.co[1] for kp in zf.keyframe_points}
    z_rest = vals.get(1, None)
    z_peak = vals.get(4, None)
    z_end = vals.get(8, None)
    check(z_rest is not None and abs(z_end - z_rest) < 1e-4, 'pump 静止帧与结束帧 z 一致(回到基准)')
    check(abs((z_peak - z_rest) - 0.045) < 1e-3, 'pump 相对基准后拉 +0.045m (frame4)')
    check(z_peak - z_rest > 0, '后拉方向为 +Z (朝枪托)')
    # 逐帧确认 pump 世界位置随动画变化（相对基准）
    scene.frame_set(4)
    z_peak_world = pump.matrix_world.translation.z
    scene.frame_set(1)
    z_rest_world = pump.matrix_world.translation.z
    check(abs((z_peak_world - z_rest_world) - 0.045) < 1e-3, 'pump 世界 z 帧4相对帧1 +0.045m')

sup=bpy.data.objects.get('SupportHandSocket')
check(sup is not None, 'SupportHandSocket 存在')
check(sup.parent==pump, 'SupportHandSocket 为 pump 子级(随 pump)')
# 副手距握把（静止帧）
scene.frame_set(scene.frame_start)
gs=bpy.data.objects.get('GripSocket')
rel=(sup.matrix_world.translation - gs.matrix_world.translation)
dist=rel.length
check(0.23<=dist<=0.26, '副手距握把 0.23~0.26m (实际 %.4f)' % dist)
check(gs.parent==wr and tuple(round(x,3) for x in gs.location)==(0,0,0), 'GripSocket 在原点=握把掌心')

# 真实 bbox（重新测量，非脚本硬编码）
def measure(objs):
    mn=Vector((1e9,)*3); mx=Vector((-1e9,)*3); any_=False
    for o in objs:
        if o.type!='MESH': continue
        any_=True
        for c in o.bound_box:
            v=o.matrix_world@Vector(c); mn=Vector(min(a,b) for a,b in zip(mn,v)); mx=Vector(max(a,b) for a,b in zip(mx,v))
    return mn,mx,any_
wmn,wmx,_=measure(meshes)
dims=[round(x,4) for x in (wmx-wmn)]
length=dims[2]
check(0.50<=length<=0.66, '真实总长 0.50~0.66m (实际 %.4f)' % length)

result={
    'source_collection':'SECURITY_SHOTGUN_REFERENCE',
    'weapon_root_parented': wr.parent is not None,
    'weapon_root_animated': bool(wr.animation_data and wr.animation_data.action),
    'mesh_count': len(meshes),
    'world_dims_m': dims,
    'measured_length_m': round(length,4),
    'support_hand_distance_m': round(dist,4),
    'materials': mats,
    'palette_embedded': any(tex[0].image.packed_file is not None for m in bpy.data.materials if m.use_nodes for tex in [[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE']] if tex),
    'armature_in_file': any(o.type=='ARMATURE' for o in bpy.data.objects),
    'camera_in_file': any(o.type=='CAMERA' for o in bpy.data.objects),
    'pump_action': 'fire_pump_cycle',
    'support_follows_pump': sup.parent==pump,
    'errors': errs,
}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print('VERIFY', json.dumps(result, ensure_ascii=False))
if errs:
    print('VERIFY_FAILED_COUNT', len(errs))
    sys.exit(1)
print('VERIFY_ALL_PASS')
