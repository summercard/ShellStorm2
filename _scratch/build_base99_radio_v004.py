import bpy, json, math, hashlib, struct
from pathlib import Path
from mathutils import Vector, Matrix
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
S=P/'assets/art/props/base_world_3d/source/base99_radio'
O=P/'outputs/base99_radio_v004'
SOURCE=S/'prp_base99_radio_source_v004.blend'
OPT=S/'export/v004/prp_base99_radio_optimized_v004.blend'
GLB=P/'assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'
PALETTE=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ROLES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if SOURCE.exists() or OPT.exists():
 previous=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
 assert sha(SOURCE)==previous['hashes_sha256']['source'] and sha(OPT)==previous['hashes_sha256']['optimized'], 'v004存在后续修改，禁止覆盖'
before=json.loads((O/'before_hashes.json').read_text(encoding='utf-8'))
old=S/'prp_base99_radio_source_v003.blend'
assert sha(old)==before[str(old.relative_to(P)).replace('\\','/')]
bpy.ops.wm.open_mainfile(filepath=str(old))
bpy.context.preferences.filepaths.save_version=0
root=bpy.data.objects['ItemRoot']
sc=bpy.data.collections['01_制作组件_已统一材质']
sc.hide_viewport=False;sc.hide_render=False
components=[o for o in sc.all_objects if o.type=='MESH']
def matrix(o):
 return o.matrix_basis if not o.parent else matrix(o.parent)@o.matrix_parent_inverse@o.matrix_basis
def bounds(objs):
 pts=[matrix(o)@v.co for o in objs for v in o.data.vertices]
 return Vector([min(v[i] for v in pts) for i in range(3)]),Vector([max(v[i] for v in pts) for i in range(3)])
lo,hi=bounds(components)
olo,ohi=bounds([o for o in root.children if o.type=='MESH'])
scale=Vector([(ohi[i]-olo[i])/(hi[i]-lo[i]) for i in range(3)])
for o in components:
 pts=[matrix(o)@v.co for v in o.data.vertices]
 o.parent=None; o.matrix_world=Matrix.Identity(4)
 for v,pt in zip(o.data.vertices,pts):
  v.co=Vector([olo[i]+(pt[i]-lo[i])*scale[i] for i in range(3)])
 o.data.update()
# 只重建本件的输出，当前制作组件先按实际输出归一化。
for o in list(root.children):
 if o.type=='MESH':bpy.data.objects.remove(o,do_unlink=True)
for o in list(components):
 if '天线' in o.name or 'StatusLight' in o.name:
  components.remove(o);bpy.data.objects.remove(o,do_unlink=True)
image=bpy.data.images.load(str(PALETTE),check_existing=True)
if image.packed_file:image.unpack(method='USE_ORIGINAL')
image.filepath=str(PALETTE)
materials=[]
settings=[(.88,.28,.15),(.04,.66,0),(.16,.16,.65),(0,.38,0)]
for name,(metal,rough,coat) in zip(ROLES,settings):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
 m.use_nodes=True;m['material_role']=name;m['palette_path']=str(PALETTE)
 nodes=m.node_tree.nodes;nodes.clear()
 out=nodes.new('ShaderNodeOutputMaterial');p=nodes.new('ShaderNodeBsdfPrincipled')
 uv=nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector'])
 m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 p.inputs['Coat Weight'].default_value=coat
 p.inputs['Emission Strength'].default_value=1.5 if name==ROLES[3] else 0
 if name==ROLES[3]:m.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color'])
 m.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface']);materials.append(m)
def uv_assign(o,cell):
 mesh=o.data
 for layer in list(mesh.uv_layers):mesh.uv_layers.remove(layer)
 uv=mesh.uv_layers.new(name='PaletteUV');mesh.uv_layers.active=uv;uv.active_render=True
 center=Vector(((cell[0]+.5)/10,(cell[1]+.5)/10))
 for f in mesh.polygons:
  for i,l in enumerate(f.loop_indices):
   a=2*math.pi*i/len(f.loop_indices)+.17
   uv.data[l].uv=center+Vector((.019*math.cos(a),.019*math.sin(a)))
 o['palette_cell']=list(cell)
def role(o,i,cell):
 o.data.materials.clear();o.data.materials.append(materials[i])
 for f in o.data.polygons:f.material_index=0
 o['material_role']=ROLES[i];uv_assign(o,cell)
for o in components:
 if '主体外壳' in o.name:role(o,1,(4,9))
 elif '侧面装甲' in o.name:role(o,1,(5,7))
 elif '扬声器栅格' in o.name:role(o,0,(9,8))
 elif '旋钮指示线' in o.name:role(o,1,(9,0))
 elif '调频玻璃' in o.name:role(o,2,(9,8))
 elif '旋钮_' in o.name:role(o,0,(9,1))
 elif '正面护框' in o.name or '护框螺栓' in o.name:role(o,0,(9,3))
 else:role(o,0,(9,5))
def move_collection(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 sc.objects.link(o)
def cylinder(name,a,b,r,n=10):
 a,b=Vector(a),Vector(b)
 bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=(b-a).length,location=(a+b)/2)
 o=bpy.context.object;o.name=name;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
 move_collection(o)
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 return o
a=Vector((.19,.066,.486));b=Vector((.376,.082,.814));d=b-a
parts=[]
for j,(u,v,r) in enumerate([(0,.38,.014),(.36,.73,.0105),(.71,1,.008)]):
 o=cylinder('天线伸缩节_'+str(j+1),a+u*d,a+v*d,r);role(o,0,(9,1));parts.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join()
ante=bpy.context.object;ante.name='斜金属伸缩天线_单根';ante['antenna_base']=list(a);ante['antenna_tip']=list(b)
antenna_top=max(v.co.z for v in ante.data.vertices)
z_factor=(.822-a.z)/(antenna_top-a.z)
for v in ante.data.vertices:v.co.z=a.z+(v.co.z-a.z)*z_factor
b.z=a.z+(b.z-a.z)*z_factor;d=b-a
ante['antenna_tip']=list(b)
ante['tilt_degrees']=math.degrees(math.atan2(math.hypot(d.x,d.y),d.z));components.append(ante)
bezel=cylinder('状态灯金属座',(-.13,-.170,.473),(-.13,-.170,.497),.031,12)
role(bezel,0,(9,3));components.append(bezel)
bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=1,location=(-.13,-.170,.499))
status=bpy.context.object;status.name='状态灯_Source';status.scale=(.023,.023,.015)
move_collection(status);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
role(status,3,(4,8));status['runtime_interface_name']='StatusLight';components.append(status)
# 新输出和源组件共用实际求值几何；主体三角色、灯独立、天线独立便于核验。
outcoll=bpy.data.collections.get('02_游戏输出_独立资产包_v003');outcoll.name='02_游戏输出_独立资产包_v004'
bodycoll=bpy.data.collections.get('01_主体_非自发光')
lightcoll=bpy.data.collections.get('02_状态灯_自发光')
def merged(name,objects,target):
 verts=[];faces=[];uvs=[];indices=[]
 used=[m for m in materials if any(m in list(o.data.materials) for o in objects)]
 for o in objects:
  mesh=o.data;offset=len(verts);verts.extend([matrix(o)@v.co for v in mesh.vertices])
  for f in mesh.polygons:
   faces.append([offset+i for i in f.vertices]);indices.append(used.index(mesh.materials[f.material_index]))
   uvs.extend([tuple(mesh.uv_layers['PaletteUV'].data[l].uv) for l in f.loop_indices])
 mesh=bpy.data.meshes.new(name+'_游戏网格');mesh.from_pydata(verts,[],faces);mesh.update()
 for m in used:mesh.materials.append(m)
 uv=mesh.uv_layers.new(name='PaletteUV');uv.active_render=True
 for f,i in zip(mesh.polygons,indices):f.material_index=i
 for l,value in zip(uv.data,uvs):l.uv=value
 o=bpy.data.objects.new(name,mesh);target.objects.link(o);o.parent=root
 return o
visual=merged('Visual',[o for o in components if o not in [ante,status]],bodycoll)
antenna=merged('Antenna',[ante],bodycoll)
light=merged('StatusLight',[status],lightcoll)
light['runtime_interface_name']='StatusLight'
antenna['antenna_base']=list(a);antenna['antenna_tip']=list(b);antenna['tilt_degrees']=ante['tilt_degrees']
for o in [visual,antenna,light]:o.hide_render=False;o.hide_set(False)
sc.hide_render=True;sc.hide_viewport=True
root['asset_version']='v004';root['status_palette_contract']='off=(4,8), a/b=(5,5), 0-based bottom-left; white factors; UV1 offset=(0.1,0.3) Godot; energy=1.5'
bpy.context.scene['asset_version']='v004';bpy.context.scene['palette_path']=str(PALETTE)
for m in list(bpy.data.materials):
 if m not in materials:bpy.data.materials.remove(m)
for im in list(bpy.data.images):
 if im!=image and im.type!='RENDER_RESULT' and im.users==0:bpy.data.images.remove(im)
outputs=[visual,antenna,light]
lo,hi=bounds(outputs);dimensions=[hi[i]-lo[i] for i in range(3)]
faces=sum(len(o.data.polygons) for o in outputs);tris=sum(len(f.vertices)-2 for o in outputs for f in o.data.polygons)
assert faces<800
assert abs(dimensions[0]-.828)<1e-6 and abs(dimensions[1]-.456)<1e-6
assert dimensions[2]<=.822001
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
source_hash=sha(SOURCE)
OPT.parent.mkdir(parents=True,exist_ok=True)
bpy.context.scene['optimized_source_sha256']=source_hash
bpy.context.scene['optimization_policy']='求值整合输出、单活动PaletteUV、3非发光角色/1灯角色、无展示导出、独立天线；已低于800不做破坏性减面'
bpy.ops.wm.save_as_mainfile(filepath=str(OPT))
bpy.ops.wm.open_mainfile(filepath=str(OPT))
bpy.ops.object.select_all(action='DESELECT')
for name in ['ItemRoot','Visual','Antenna','StatusLight']:bpy.data.objects[name].select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['ItemRoot']
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,export_apply=True,export_image_format='NONE',export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert sha(SOURCE)==source_hash and sha(old)==before[str(old.relative_to(P)).replace('\\','/')]
blob=GLB.read_bytes();length=struct.unpack_from('<I',blob,12)[0];gltf=json.loads(blob[20:20+length])
assert not gltf.get('images') and not gltf.get('textures')
assert len(gltf['materials'])==4
report={'asset_id':'PRP-BASE99-RADIO-3D','version':'v004','source_blend':SOURCE.as_posix(),'optimized_blend':OPT.as_posix(),'input_source_preserved':old.as_posix(),'component_glb':GLB.as_posix(),'runtime_prefab_target':'assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','faces':faces,'triangles':tris,'dimensions_width_depth_height_m':[dimensions[0],dimensions[1],dimensions[2]],'bounds_min_blender':list(lo),'bounds_max_blender':list(hi),'materials':{name:{'metallic':m,'roughness':r,'coat':c,'emission_energy':1.5 if i==3 else 0} for i,(name,(m,r,c)) in enumerate(zip(ROLES,settings))},'palette':{'path':PALETTE.as_posix(),'external':True,'interpolation':'Closest','uv_layer':'PaletteUV','body_cell':[4,9],'metal_frame_cell':[9,3],'antenna_knob_cell':[9,1],'status_off_cell':[4,8],'status_on_cell':[5,5],'cell_origin':'左下0-based','status_godot_uv1_offset_on':[.1,.3,0],'runtime_factor':'albedo/emission=white; EMISSION_OP_MULTIPLY'},'antenna':{'count':1,'telescopic_sections':3,'base_blender':list(a),'tip_blender':list(b),'tilt_degrees':math.degrees(math.atan2(math.hypot(d.x,d.y),d.z))},'output_meshes':['Visual','Antenna','StatusLight'],'hashes_sha256':{'source':sha(SOURCE),'optimized':sha(OPT),'glb':sha(GLB)},'source_unchanged_during_optimization':True,'glb_embedded_images':0,'glb_embedded_textures':0,'preserved_placement':[-1.95,6.97,-13.87143],'status_light':'小圆灯前上缘；off红色常亮，A/B同绿常亮；离楼仍红待机；音乐独立不变'}
(O/'asset_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V004_BUILD_OK',json.dumps(report,ensure_ascii=False))
