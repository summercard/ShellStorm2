import bpy, json, hashlib, math, struct, shutil
from pathlib import Path
from mathutils import Vector, Matrix

P=Path('I:/工作项目/shellstrom2/ShellStorm2')
S=P/'assets/art/props/base_world_3d/source/base99_radio'
C=P/'assets/art/props/base_world_3d/components/base99_radio'
O=P/'outputs/base99_radio_v005'
OLD=S/'prp_base99_radio_source_v004.blend'
SOURCE=S/'prp_base99_radio_source_v005.blend'
OPT=S/'export/v005/prp_base99_radio_optimized_v005.blend'
GLB=C/'prp_base99_radio_visual_top3d.glb'
PALETTE=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ROLES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
ROLE_CELLS={ROLES[0]:(9,3),ROLES[1]:(4,9),ROLES[2]:(9,8),ROLES[3]:(4,8)}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
O.mkdir(parents=True,exist_ok=True); OPT.parent.mkdir(parents=True,exist_ok=True); C.mkdir(parents=True,exist_ok=True)
assert OLD.exists(), 'v004缺失'
if SOURCE.exists() or OPT.exists():
    from datetime import datetime
    backup=O/('repair_backup_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    backup.mkdir()
    for path in [SOURCE,OPT,GLB]:
        if path.exists(): shutil.copy2(path,backup/path.name)
old_sha=sha(OLD)
assert old_sha=='885ce2788a60d565eba7d53bd02e3560d01d6f5de2feda1f5e3cfdf71ed6ed03', old_sha
bpy.ops.wm.open_mainfile(filepath=str(OLD)); bpy.context.preferences.filepaths.save_version=0
root=bpy.data.objects['ItemRoot']; source_coll=bpy.data.collections['01_制作组件_已统一材质']; out_coll=bpy.data.collections.get('02_游戏输出_独立资产包_v004') or bpy.data.collections.get('02_游戏输出_独立资产包_v003')
assert root and source_coll and out_coll

def unlink_all(o):
    for c in list(o.users_collection): c.objects.unlink(o)
def link(o,c):
    unlink_all(o); c.objects.link(o)
def world_points(o): return [o.matrix_world@v.co for v in o.data.vertices]
def make_uv(o,cell):
    mesh=o.data
    for layer in list(mesh.uv_layers): mesh.uv_layers.remove(layer)
    uv=mesh.uv_layers.new(name='PaletteUV'); mesh.uv_layers.active=uv; uv.active_render=True
    center=Vector(((cell[0]+0.5)/10.0,(cell[1]+0.5)/10.0))
    for f in mesh.polygons:
        n=max(3,len(f.loop_indices))
        for i,l in enumerate(f.loop_indices):
            a=2*math.pi*i/n+0.17
            uv.data[l].uv=center+Vector((0.019*math.cos(a),0.019*math.sin(a)))
    o['palette_cell']=list(cell)
def role(o,idx):
    o.data.materials.clear(); o.data.materials.append(bpy.data.materials[ROLES[idx]])
    for f in o.data.polygons:f.material_index=0
    o['material_role']=ROLES[idx]; make_uv(o,ROLE_CELLS[ROLES[idx]])
def mesh_from(name,verts,faces,mat):
    me=bpy.data.meshes.new(name+'_游戏网格'); me.from_pydata(verts,[],faces); me.update(); me.materials.append(mat)
    uv=me.uv_layers.new(name='PaletteUV'); me.uv_layers.active=uv; uv.active_render=True
    center=Vector(((ROLE_CELLS[mat.name][0]+0.5)/10.0,(ROLE_CELLS[mat.name][1]+0.5)/10.0))
    for f in me.polygons:
        n=max(3,len(f.loop_indices))
        for i,l in enumerate(f.loop_indices):
            a=2*math.pi*i/n+0.17; uv.data[l].uv=center+Vector((0.019*math.cos(a),0.019*math.sin(a)))
    return me
def merged(name,objs,target):
    verts=[]; faces=[]; mats=[]; face_mats=[]; original_uvs=[]
    for o in objs:
        start=len(verts); verts.extend(o.matrix_world@v.co for v in o.data.vertices)
        for f in o.data.polygons:
            faces.append([start+i for i in f.vertices])
            src=o.data.materials[f.material_index] if f.material_index < len(o.data.materials) else None
            mat=bpy.data.materials.get(str(src.get('material_role',src.name) if src else ROLES[1])) or bpy.data.materials[ROLES[1]]
            if mat not in mats: mats.append(mat)
            face_mats.append(mats.index(mat))
            original_uvs.extend(tuple(o.data.uv_layers['PaletteUV'].data[l].uv) for l in f.loop_indices)
    me=bpy.data.meshes.new(name+'_游戏网格'); me.from_pydata(verts,[],faces); me.update()
    for mat in mats: me.materials.append(mat)
    for f,mi in zip(me.polygons,face_mats): f.material_index=mi
    uv=me.uv_layers.new(name='PaletteUV'); me.uv_layers.active=uv; uv.active_render=True
    for l,value in zip(uv.data,original_uvs): l.uv=value
    o=bpy.data.objects.new(name,me); target.objects.link(o); o.parent=root; o.matrix_parent_inverse=Matrix.Identity(4); return o
def locked_signature(o):
    uv=o.data.uv_layers['PaletteUV']
    record={'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,
            'matrix':[round(v,7) for row in o.matrix_world for v in row],
            'vertices':[[round(v,7) for v in p.co] for p in o.data.vertices],
            'edges':[list(e.vertices) for e in o.data.edges],
            'faces':[[list(f.vertices),f.material_index] for f in o.data.polygons],
            'uv':[[round(v,7) for v in l.uv] for l in uv.data],
            'materials':[m.name for m in o.data.materials],
            'modifiers':[(m.name,m.type) for m in o.modifiers],
            'animation':str(o.animation_data)}
    return hashlib.sha256(json.dumps(record,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
bpy.context.view_layer.update()
locked_before={o.name:locked_signature(o) for o in source_coll.objects if o.type=='MESH' and o.name not in ['状态灯金属座','状态灯_Source'] and o.get('runtime_interface_name')!='StatusLight'}
# 只替换旧状态灯与输出，锁定其余制作组件。
for o in list(source_coll.objects):
    if o.name in ['状态灯金属座','状态灯_Source'] or o.get('runtime_interface_name')=='StatusLight': bpy.data.objects.remove(o,do_unlink=True)
for o in list(bpy.data.objects):
    if o.parent==root and o.type=='MESH': bpy.data.objects.remove(o,do_unlink=True)
# Four standard role materials and external palette contract.
image=bpy.data.images.load(str(PALETTE),check_existing=True); image.filepath=str(PALETTE)
for m in bpy.data.materials:
    if m.name in ROLES:
        m['material_role']=m.name; m['palette_path']=str(PALETTE)
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type=='TEX_IMAGE': n.image=image; n.interpolation='Closest'
# 顶面偏前12边灯帽，仅扩大灯与灯座，不触及机身、提手和天线。
bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=0.107,depth=0.014,location=(-0.12,-0.105,0.4945))
base=bpy.context.object; base.name='状态灯顶面金属座'; link(base,source_coll); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); role(base,0)
# radial frustum/dome with bottom, shoulder, crown; 12 sides, faceted convex cap.
N=12; cx,cy=-0.12,-0.105; z0,z1,z2=0.5015,0.5455,0.5595; r0,r1=0.10,0.098
verts=[]
for z,r in [(z0,r0),(z1,r1)]:
    verts += [(cx+r*math.cos(2*math.pi*i/N),cy+r*math.sin(2*math.pi*i/N),z) for i in range(N)]
verts.append((cx,cy,z2)); apex=2*N
faces=[list(reversed(range(N)))]
for i in range(N):
    j=(i+1)%N; faces.append([i,j,N+j,N+i]); faces.append([N+i,N+j,apex])
me=bpy.data.meshes.new('StatusLight_v005_12边凸帽网格'); me.from_pydata(verts,[],faces); me.update()
cap=bpy.data.objects.new('状态灯顶面凸帽_UI灯光_柔和自发光_Source',me); source_coll.objects.link(cap); role(cap,3); cap['runtime_interface_name']='StatusLight'; cap['status_light_shape']='12-sided low-poly convex cap'; cap['diameter_m']=0.20; cap['center_blender']=[cx,cy,(z0+z2)/2]
# rebuild stable output objects from all source components; split non-emissive body, antenna and light.
source_meshes=[o for o in source_coll.objects if o.type=='MESH']
antenna_objs=[o for o in source_meshes if '天线' in o.name]
light_objs=[base,cap]
body_objs=[o for o in source_meshes if o not in antenna_objs and o not in light_objs]
out_coll.name='02_游戏输出_独立资产包_v005'
bpy.context.view_layer.update()
visual=merged('Visual',body_objs+[base],out_coll); antenna=merged('Antenna',antenna_objs,out_coll); status=merged('StatusLight',[cap],out_coll)
status.name='StatusLight_UI灯光_柔和自发光'; status['runtime_interface_name']='StatusLight'; status['status_light_shape']='12-sided low-poly convex cap'; status['diameter_m']=0.20; status['center_blender']=[cx,cy,(z0+z2)/2]
antenna['antenna_base']=list(bpy.data.objects.get('斜金属伸缩天线_单根').get('antenna_base',[])); antenna['antenna_tip']=list(bpy.data.objects.get('斜金属伸缩天线_单根').get('antenna_tip',[])); antenna['tilt_degrees']=29.34988279857398
for o in [visual,antenna,status]:
    o.hide_set(False); o.hide_render=False
source_coll.hide_viewport=True; source_coll.hide_render=True
root['asset_version']='v005'; root['status_light_contract']='顶面偏前侧12边低模凸帽，直径0.20m；off红常亮，A/B绿常亮；原ItemRoot/Visual/StatusLight接口；无billboard/UI/bloom'
root['status_palette_contract']='off=(4,8), a/b=(5,5), 0-based bottom-left; white factors; UV1 offset=(0.1,0.3) Godot; energy=1.5'
bpy.context.scene['asset_version']='v005'; bpy.context.scene['palette_path']=str(PALETTE); bpy.context.scene['glb_export_image_format']='NONE'
# Root must remain unit scale and bounds must retain original external size.
assert tuple(round(x,6) for x in root.scale)==(1.0,1.0,1.0)
def bounds(objs):
    pts=[p for o in objs for p in world_points(o)]
    lo=Vector((min(p[i] for p in pts) for i in range(3))); hi=Vector((max(p[i] for p in pts) for i in range(3))); return lo,hi
lo,hi=bounds([visual,antenna,status]); dims=hi-lo
faces=sum(len(o.data.polygons) for o in [visual,antenna,status]); tris=sum(sum(max(1,len(f.vertices)-2) for f in o.data.polygons) for o in [visual,antenna,status])
assert faces<800, faces
assert abs(dims.x-0.828)<1e-5 and abs(dims.y-0.456)<1e-5 and abs(dims.z-0.822)<1e-5, list(dims)
locked_after={name:locked_signature(bpy.data.objects[name]) for name in locked_before}
assert locked_before==locked_after, '范围外制作组件签名改变'
from mathutils.bvhtree import BVHTree
obstacles=[o for o in source_meshes if o not in light_objs]
ob_verts=[]; ob_faces=[]
for o in obstacles:
    start=len(ob_verts); ob_verts.extend(world_points(o))
    ob_faces.extend([start+i for i in f.vertices] for f in o.data.polygons)
bvh=BVHTree.FromPolygons(ob_verts,ob_faces)
samples=[Vector((cx,cy,z2))]
for i in range(N):
    a=2*math.pi*i/N; samples.append(Vector((cx+0.065*math.cos(a),cy+0.065*math.sin(a),z2)))
clear={}
for label,direction in [('top',Vector((0,0,1))),('native_angle',Vector((0,-0.423,0.906)).normalized())]:
    clear[label]=sum(bvh.ray_cast(p+direction*0.002,direction,10.0)[0] is None for p in samples)
assert all(n==len(samples) for n in clear.values()), clear
crown=[f for f in status.data.polygons if f.center.z>z1 and f.normal.z>0.0]
assert len(crown)==12 and min(f.normal.z for f in crown)>0.95
(O/'lamp_geometry_assertions.json').write_text(json.dumps({'passed':True,'diameter_m':0.20,'cap_height_m':z2-z0,'cap_faces':len(status.data.polygons),'crown_faces':len(crown),'min_crown_normal_up':min(f.normal.z for f in crown),'unblocked_samples':clear,'samples_per_view':len(samples),'faces':faces,'triangles':tris,'budget_faces':800,'root_scale':list(root.scale),'ray_obstacles':[o.name for o in obstacles]},ensure_ascii=False,indent=2),encoding='utf-8')
(O/'locked_geometry_current.json').write_text(json.dumps({'passed':True,'locked_match':True,'before_v004':locked_before,'after_v005':locked_after,'modified':['状态灯顶面金属座','状态灯顶面凸帽_UI灯光_柔和自发光_Source'],'cap_internal_shoulder_face_removed':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# 保存源与独立优化副本，随后从优化副本导出正式GLB。
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE)); source_hash=sha(SOURCE)
bpy.context.scene['optimized_source_sha256']=source_hash; bpy.context.scene['optimization_policy']='独立副本；求值整合输出；四标准材质；公共PaletteUV；StatusLight单一顶面凸帽；无展示环境'
bpy.ops.wm.save_as_mainfile(filepath=str(OPT)); opt_hash=sha(OPT)
bpy.ops.wm.open_mainfile(filepath=str(OPT)); root=bpy.data.objects['ItemRoot']; status_export=bpy.data.objects['StatusLight_UI灯光_柔和自发光'];
for o in [root,bpy.data.objects['Visual'],bpy.data.objects['Antenna'],status_export]: o.select_set(True)
bpy.context.view_layer.objects.active=root
status_export.name='StatusLight'
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
glb_hash=sha(GLB); blob=GLB.read_bytes(); total=struct.unpack_from('<I',blob,12)[0]; gltf=json.loads(blob[20:20+total]); assert len(gltf.get('images',[]))==0 and len(gltf.get('textures',[]))==0 and len(gltf.get('materials',[]))==4
report={'asset_id':'PRP-BASE99-RADIO-3D','version':'v005','source_blend':SOURCE.as_posix(),'optimized_blend':OPT.as_posix(),'input_source_preserved':OLD.as_posix(),'component_glb':GLB.as_posix(),'runtime_prefab_target':'assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','faces':faces,'triangles':tris,'dimensions_width_depth_height_m':[dims.x,dims.y,dims.z],'bounds_min_blender':list(lo),'bounds_max_blender':list(hi),'output_meshes':['Visual','Antenna','StatusLight'],'status_light':{'shape':'12-sided low-poly convex cap','diameter_m':0.20,'cap_height_m':z2-z0,'center_blender':[cx,cy,(z0+z2)/2],'base_top_z_m':z0,'top_z_m':z2,'replaced_old_status_light':True,'top_surface_forward_side':True,'occlusion_clearance':'center=(-0.12,-0.105); cap rear y=-0.005; handle starts y=0.0168; antenna base y=0.066'},'antenna':{'count':1,'tilt_degrees':29.34988279857398},'materials':ROLES,'palette':{'path':PALETTE.as_posix(),'external_only':True,'interpolation':'Closest','uv_layer':'PaletteUV','status_off_cell':[4,8],'status_on_cell':[5,5],'status_godot_uv1_offset_on':[0.1,0.3,0],'runtime_energy':1.5},'preserved_placement':[-1.95,6.97,-13.87143],'music_logic_untouched':True,'root_scale':[1,1,1],'glb_embedded_images':len(gltf.get('images',[])),'glb_embedded_textures':len(gltf.get('textures',[])),'hashes_sha256':{'source':source_hash,'optimized':opt_hash,'glb':glb_hash,'old_source_v004':old_sha}}
(O/'asset_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(O/'build_geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V005_BUILD_OK',json.dumps(report,ensure_ascii=False))
