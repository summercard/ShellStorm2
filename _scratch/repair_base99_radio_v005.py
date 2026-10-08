import bpy, hashlib, json, math, struct
from pathlib import Path
from mathutils import Vector, Matrix

P=Path('I:/工作项目/shellstrom2/ShellStorm2')
S=P/'assets/art/props/base_world_3d/source/base99_radio'
C=P/'assets/art/props/base_world_3d/components/base99_radio'
O=P/'outputs/base99_radio_v005'
SOURCE=S/'prp_base99_radio_source_v005.blend'
OPT=S/'export/v005/prp_base99_radio_optimized_v005.blend'
GLB=C/'prp_base99_radio_visual_top3d.glb'
PALETTE=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ROLES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
ROLE_CELLS={ROLES[0]:(9,3),ROLES[1]:(4,9),ROLES[2]:(9,8),ROLES[3]:(4,8)}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def unlink_all(o):
    for c in list(o.users_collection): c.objects.unlink(o)
def world_points(o): return [o.matrix_world@v.co for v in o.data.vertices]
def mat_role(src):
    return str(src.get('material_role',src.name)) if src else ROLES[1]
def source_uv_layer(o):
    return o.data.uv_layers.get('PaletteUV')

def merged_preserve_uv(name, objs, target, root):
    verts=[]; faces=[]; face_mats=[]; uv_values=[]; mats=[]
    for o in objs:
        start=len(verts)
        verts.extend(o.matrix_world@v.co for v in o.data.vertices)
        uv=source_uv_layer(o)
        for f in o.data.polygons:
            faces.append([start+i for i in f.vertices])
            src=o.data.materials[f.material_index] if f.material_index < len(o.data.materials) else None
            role=mat_role(src)
            mat=bpy.data.materials.get(role) or bpy.data.materials[ROLES[1]]
            if mat not in mats: mats.append(mat)
            face_mats.append(mats.index(mat))
            if uv:
                uv_values.extend([tuple(uv.data[l].uv) for l in f.loop_indices])
            else:
                uv_values.extend([(0.45,0.95)]*len(f.loop_indices))
    me=bpy.data.meshes.new(name+'_游戏网格'); me.from_pydata(verts,[],faces); me.update()
    for mat in mats: me.materials.append(mat)
    for f,mi in zip(me.polygons,face_mats): f.material_index=mi
    layer=me.uv_layers.new(name='PaletteUV'); me.uv_layers.active=layer; layer.active_render=True
    cursor=0
    for f in me.polygons:
        for l in f.loop_indices:
            layer.data[l].uv=uv_values[cursor]; cursor+=1
    out=bpy.data.objects.new(name,me); target.objects.link(out); out.parent=root; out.matrix_parent_inverse=Matrix.Identity(4)
    return out

def bounds(objs):
    pts=[p for o in objs for p in world_points(o)]
    lo=Vector((min(p[i] for p in pts) for i in range(3))); hi=Vector((max(p[i] for p in pts) for i in range(3)))
    return lo,hi

bpy.ops.wm.open_mainfile(filepath=str(SOURCE)); bpy.context.preferences.filepaths.save_version=0
bpy.context.view_layer.update()
root=bpy.data.objects['ItemRoot']; source_coll=bpy.data.collections['01_制作组件_已统一材质']; out_coll=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
# Preserve source meshes and replace only integrated output meshes.
for o in list(out_coll.objects):
    if o.type=='MESH': bpy.data.objects.remove(o,do_unlink=True)
source_meshes=[o for o in source_coll.objects if o.type=='MESH']
antenna_objs=[o for o in source_meshes if '天线' in o.name]
base_objs=[o for o in source_meshes if o.name=='状态灯顶面金属座']
cap_objs=[o for o in source_meshes if o.name=='状态灯顶面凸帽_Source']
assert len(base_objs)==1 and len(cap_objs)==1 and len(antenna_objs)==1
light_base=base_objs[0]; cap=cap_objs[0]
# 旧构建把金属座的对象位移写在未进入场景依赖图的 location 上；将座体顶点归一到与凸帽一致的 ItemRoot 局部坐标，避免输出丢座或双重偏移。
for vertex in light_base.data.vertices:
    vertex.co += Vector((-0.13, -0.09, 0.4945))
light_base.location = Vector((0.0, 0.0, 0.0))
light_base.rotation_euler = (0.0, 0.0, 0.0)
light_base.scale = Vector((1.0, 1.0, 1.0))
body_objs=[o for o in source_meshes if o not in antenna_objs and o not in base_objs and o not in cap_objs]
visual=merged_preserve_uv('Visual',body_objs+base_objs,out_coll,root)
antenna=merged_preserve_uv('Antenna',antenna_objs,out_coll,root)
status=merged_preserve_uv('StatusLight',cap_objs,out_coll,root)
status['runtime_interface_name']='StatusLight'; status['status_light_shape']='12-sided low-poly convex cap'; status['diameter_m']=0.14; status['center_blender']=[-0.13,-0.09,0.5225]
antenna['antenna_base']=list(bpy.data.objects.get('斜金属伸缩天线_单根').get('antenna_base',[])); antenna['antenna_tip']=list(bpy.data.objects.get('斜金属伸缩天线_单根').get('antenna_tip',[])); antenna['tilt_degrees']=29.34988279857398
for o in [visual,antenna,status]: o.hide_set(False); o.hide_render=False
out_coll.name='02_游戏输出_独立资产包_v005'; source_coll.hide_viewport=True; source_coll.hide_render=True
root['asset_version']='v005'; root['status_light_contract']='顶面偏前侧12边低模凸帽，直径0.14m；off红常亮，A/B绿常亮；原ItemRoot/Visual/StatusLight接口；无billboard/UI/bloom'
bpy.context.scene['asset_version']='v005'; bpy.context.scene['palette_path']=str(PALETTE); bpy.context.scene['glb_export_image_format']='NONE'
lo,hi=bounds([visual,antenna,status]); dims=hi-lo
faces=sum(len(o.data.polygons) for o in [visual,antenna,status]); tris=sum(sum(max(1,len(f.vertices)-2) for f in o.data.polygons) for o in [visual,antenna,status])
assert faces==600 and faces<800, faces
assert abs(dims.x-0.828)<1e-5 and abs(dims.y-0.456)<1e-5 and abs(dims.z-0.822)<1e-5, list(dims)
assert root.scale==Vector((1,1,1))
# Save source and independent optimized copy, then export GLB.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE)); source_hash=sha(SOURCE)
bpy.context.scene['optimized_source_sha256']=source_hash; bpy.context.scene['optimization_policy']='独立副本；求值整合输出；原PaletteUV逐面复制；四标准材质；StatusLight单一顶面凸帽；无展示环境'
bpy.ops.wm.save_as_mainfile(filepath=str(OPT)); opt_hash=sha(OPT)
bpy.ops.wm.open_mainfile(filepath=str(OPT)); root=bpy.data.objects['ItemRoot']; bpy.ops.object.select_all(action='DESELECT')
for o in [root,bpy.data.objects['Visual'],bpy.data.objects['Antenna'],bpy.data.objects['StatusLight']]: o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
glb_hash=sha(GLB); blob=GLB.read_bytes(); total=struct.unpack_from('<I',blob,12)[0]; gltf=json.loads(blob[20:20+total]); assert len(gltf.get('images',[]))==0 and len(gltf.get('textures',[]))==0 and len(gltf.get('materials',[]))==4
report={'asset_id':'PRP-BASE99-RADIO-3D','version':'v005','source_blend':SOURCE.as_posix(),'optimized_blend':OPT.as_posix(),'component_glb':GLB.as_posix(),'faces':faces,'triangles':tris,'dimensions_width_depth_height_m':[dims.x,dims.y,dims.z],'bounds_min_blender':list(lo),'bounds_max_blender':list(hi),'output_meshes':['Visual','Antenna','StatusLight'],'status_light':{'shape':'12-sided low-poly convex cap','diameter_m':0.14,'cap_height_m':0.042,'center_blender':[-0.13,-0.09,0.5225],'base_top_z_m':0.5015,'top_z_m':0.5435,'metal_base_in_visual':True,'replaced_old_status_light':True,'top_surface_forward_side':True,'occlusion_clearance':'y=-0.09; handle starts y=0.0168; antenna base y=0.066'},'materials':ROLES,'palette':{'path':PALETTE.as_posix(),'external_only':True,'interpolation':'Closest','uv_layer':'PaletteUV','status_off_cell':[4,8],'status_on_cell':[5,5],'status_godot_uv1_offset_on':[0.1,0.3,0],'runtime_energy':1.5},'root_scale':[1,1,1],'glb_embedded_images':len(gltf.get('images',[])),'glb_embedded_textures':len(gltf.get('textures',[])),'hashes_sha256':{'source':source_hash,'optimized':opt_hash,'glb':glb_hash}}
(O/'asset_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); (O/'build_geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V005_REPAIR_OK',json.dumps(report,ensure_ascii=False))
