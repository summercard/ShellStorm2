import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Matrix, Vector
p=Path(__file__).parent; project=p.parents[1]
pkg=project/'assets/art/enemies/normal_enemy_3d/fat_zombie03'; prefix='enm_normal_fat_zombie03'
out=pkg/'source/model'/f'{prefix}_model_v002.blend'
backup=p/'v002_backup'; backup.mkdir(exist_ok=True)
glb=pkg/'components'/f'{prefix}_visual_top3d.glb'
if not (backup/glb.name).exists():shutil.copy2(glb,backup/glb.name)
bpy.ops.wm.open_mainfile(filepath=str(p/'raw_import.blend'))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
assert len(bpy.data.actions)==0
mapping={'Hips':'Hip','Spine':'Waist','Spine1':'Spine01','Spine2':'Spine02','Neck':'Neck','Head':'Head','HeadTop_End':'HeadTop_End'}
for side,short in [('Left','L'),('Right','R')]:
 for src,dst in [('Shoulder','Clavicle'),('Arm','Upperarm'),('ForeArm','Forearm'),('Hand','Hand'),('UpLeg','Thigh'),('Leg','Calf'),('Foot','Foot'),('ToeBase','ToeBase'),('Toe_End','Toe_End')]:mapping[side+src]=short+'_'+dst
 for finger in ['Thumb','Index','Middle','Pinky','Ring']:
  for i in range(1,5):mapping[f'{side}Hand{finger}{i}']=f'{short}_{finger}{i}'
mapping={'mixamorig:'+src:dst for src,dst in mapping.items()}
assert set(b.name for b in arm.data.bones)==set(mapping)
core=['Root','Hip','Waist','Spine02','Neck','Head']
for side in ['L','R']:
 core += [side+'_'+n for n in ['Clavicle','Upperarm','Forearm','Hand','Thumb1','Thumb2','Index1','Index2','Middle1','Middle2','Pinky1','Pinky2','Thigh','Calf','Foot']]
weights_before=[[(g.group,g.weight) for g in v.groups] for v in mesh.data.vertices]
def points():
 arm.update_tag(refresh={'OBJECT','DATA','TIME'}); mesh.update_tag(refresh={'OBJECT','DATA','TIME'})
 bpy.context.scene.frame_set(bpy.context.scene.frame_current+1)
 bpy.context.view_layer.update(); deps=bpy.context.evaluated_depsgraph_get(); deps.update(); ev=mesh.evaluated_get(deps); em=ev.to_mesh(); result=[mesh.matrix_world@v.co for v in em.vertices]; ev.to_mesh_clear(); return result
rest_before=points(); source_height=max(v.z for v in rest_before)-min(v.z for v in rest_before); factor=(2.2/.7)/source_height
fit=Matrix.Rotation(math.pi,4,'Z')@Matrix.Scale(factor,4)@Matrix.Translation((0,0,-min(v.z for v in rest_before)))
pose_snap={}
pose_matrices={}
for bone in ['mixamorig:Head','mixamorig:LeftForeArm','mixamorig:RightLeg']:
 pb=arm.pose.bones[bone]; pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=(math.cos(math.radians(15)/2),math.sin(math.radians(15)/2),0,0)
 pose_snap[bone]=points(); pb.rotation_quaternion=(1,0,0,0)
 pose_matrices[bone]=[list(r) for r in arm.pose.bones[bone].matrix]
 print('SOURCE_PROBE',bone,'moved',sum((a-b).length>1e-5 for a,b in zip(rest_before,pose_snap[bone])),flush=True)
bpy.context.view_layer.update()
meshworld=mesh.matrix_world.copy(); armworld=arm.matrix_world.copy()
mesh.parent=None; mesh.matrix_world=Matrix.Identity(4); mesh.data.transform(fit@meshworld)
bpy.context.view_layer.objects.active=arm; bpy.ops.object.mode_set(mode='EDIT')
bone_snap={b.name:(b.matrix.copy(),b.length,b.use_connect) for b in arm.data.edit_bones}
for b in arm.data.edit_bones:b.use_connect=False
for b in arm.data.edit_bones:
 mat,length,connected=bone_snap[b.name]; b.matrix=fit@armworld@mat; b.length=length*factor
for b in arm.data.edit_bones:b.use_connect=bone_snap[b.name][2]
root=arm.data.edit_bones.new('Root'); root.head=(0,0,0); root.tail=(0,0,.12); root.roll=math.pi; root.use_deform=False
arm.data.edit_bones['mixamorig:Hips'].parent=root; arm.data.edit_bones['mixamorig:Hips'].use_connect=False
bpy.ops.object.mode_set(mode='OBJECT')
arm.matrix_world=Matrix.Identity(4);mesh.parent=arm;mesh.matrix_parent_inverse=Matrix.Identity(4);mesh.matrix_world=Matrix.Identity(4)
for old,new in mapping.items():arm.data.bones[old].name=new
for g in mesh.vertex_groups:
 if g.name in mapping:g.name=mapping[g.name]
 else:assert g.name in mapping.values()
weights_after=[[(g.group,g.weight) for g in v.groups] for v in mesh.data.vertices]
assert weights_before==weights_after
assert not set(core)-set(arm.data.bones.keys())
assert arm.data.bones['Root'].parent is None and arm.data.bones['Hip'].parent.name=='Root'
assert all(g.name in arm.data.bones for g in mesh.vertex_groups)
rest_after=points(); rest_error=max((fit@a-b).length for a,b in zip(rest_before,rest_after)); assert rest_error<1e-5
probes={}
for old,expected in pose_snap.items():
 name=mapping[old]; pb=arm.pose.bones[name]; pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=(math.cos(math.radians(15)/2),math.sin(math.radians(15)/2),0,0)
 result=points(); preservation=max((fit@a-b).length for a,b in zip(expected,result))
 subtree={name}|{b.name for b in arm.data.bones[name].children_recursive}
 groupids={g.index for g in mesh.vertex_groups if g.name in subtree}
 moved=[i for i,(a,b) in enumerate(zip(rest_after,result)) if (a-b).length>1e-5]
 unrelated=[i for i in moved if not any(g.group in groupids and g.weight>1e-7 for g in mesh.data.vertices[i].groups)]
 print('DEFORMATION_PROBE',name,'preservation',preservation,'moved',len(moved),'unrelated',len(unrelated),flush=True)
 if preservation>=1e-5:print('MATRIX_COMPARE',pose_matrices[old],[list(r) for r in pb.matrix],flush=True)
 assert preservation<1e-5 and moved and not unrelated
 probes[name]={'moved_vertices':len(moved),'unrelated_vertices':len(unrelated),'deformation_preservation_error_m':preservation}
 pb.rotation_quaternion=(1,0,0,0)
for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
final_rest=points(); assert max((a-b).length for a,b in zip(rest_after,final_rest))<1e-5
texture=pkg/'source/model/textures'/f'{prefix}_basecolor_v002.png'
for mat in mesh.data.materials:
 for n in mat.node_tree.nodes:
  if n.type=='TEX_IMAGE' and n.image:
   im=bpy.data.images.load(str(pkg/'source/model/textures'/f'{prefix}_basecolor_v001.jpeg'),check_existing=False); im.name=prefix+'_basecolor_512'; im.colorspace_settings.name='sRGB'; _=im.pixels[0]; im.scale(512,512)
   im.pack(); im.filepath_raw=str(texture); im.file_format='PNG'; im.save(); im.pack(); im.filepath='//textures/'+texture.name; n.image=im
for im in list(bpy.data.images):
 if im.users==0:bpy.data.images.remove(im)
signature=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in arm.data.bones]).encode()).hexdigest()
arm.data['skeleton_id']='SKEL-FAT-ZOMBIE03-002'; arm.data['bone_contract']='36 core names + preserved extra bones; independent rest signature'
arm.name=prefix+'_armature';arm.data.name=arm.name;mesh.name=prefix+'_mesh';mesh.data.name=mesh.name
for mat in mesh.data.materials:mat.name=prefix+'_material'
arm.data['skeleton_signature']=signature
bpy.context.scene.render.fps=30
# Organize authoring collections; export only rig and skin.
for o in [arm,mesh]:
 for coll in list(o.users_collection):coll.objects.unlink(o)
rigcoll=bpy.data.collections.new('SharedSkeleton'); bpy.context.scene.collection.children.link(rigcoll); rigcoll.objects.link(arm)
body=bpy.data.collections.new('Body'); bpy.context.scene.collection.children.link(body)
style=bpy.data.collections.new('fat_zombie03'); body.children.link(style); style.objects.link(mesh)
pts=[v.co for v in mesh.data.vertices]; lo=[min(v[i] for v in pts) for i in range(3)]; hi=[max(v[i] for v in pts) for i in range(3)]
report={'asset_id':'ENM-NORMAL-FAT-ZOMBIE03','source_number':'03','version':'v002','source_bounds_m':[hi[i]-lo[i] for i in range(3)],'game_bounds_at_0_70':[.7*(hi[i]-lo[i]) for i in range(3)],'game_height_m':2.2,'source_height_m':2.2/.7,'height_multiplier_assumption':{'base':.7,'kind':1,'variant':1},'bounds_min':lo,'bounds_max':hi,'vertices':len(pts),'triangles':sum(len(f.vertices)-2 for f in mesh.data.polygons),'bones':len(arm.data.bones),'core_bones':core,'extra_bones':[b.name for b in arm.data.bones if b.name not in core],'bone_mapping':mapping,'skeleton_id':arm.data['skeleton_id'],'skeleton_signature':signature,'core_missing':[],'root_parent':None,'hip_parent':'Root','weights_preserved_exactly':True,'unweighted':sum(not any(g.weight>0 for g in v.groups) for v in mesh.data.vertices),'weight_sum_errors':sum(abs(sum(g.weight for g in v.groups)-1)>1e-3 for v in mesh.data.vertices),'rest_preservation_error_m':rest_error,'deformation_probes':probes,'object_scales':{o.name:list(o.scale) for o in [arm,mesh]},'object_rotations':{o.name:list(o.rotation_euler) for o in [arm,mesh]},'texture_size':[512,512],'actions':[],'missing_clips':['idle','walking','running','attack','hurt','dead'],'status':'model_rig_verified_animation_design_only'}
bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=str(out))
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); mesh.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
(pkg/'source/model/model_audit_v002.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Source references stay versioned; previews use actual 0.70 game scale.
arm.scale=(.7,)*3; bpy.context.view_layer.update()
sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=24; sc.render.resolution_x=768;sc.render.resolution_y=768;sc.render.resolution_percentage=100
if sc.world is None:sc.world=bpy.data.worlds.new('PreviewWorld')
sc.world.color=(.22,)*3
for loc in [(3,4,5),(-3,-2,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc); bpy.context.object.data.energy=500;bpy.context.object.data.size=4
for x,h,name in [(3.05,2.2,'FatZombieHeight_2_2m'),(-3.05,1.2,'PlayerHeight_1_2m')]:
 bpy.ops.mesh.primitive_cube_add(size=1,location=(x,0,h/2)); marker=bpy.context.object;marker.name=name;marker.scale=(.05,.05,h)
bpy.ops.object.camera_add();cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=7.0
for name,pos in [('front_plus_y',(0,8,1.2)),('back_minus_y',(0,-8,1.2)),('side_plus_x',(8,0,1.2)),('side_minus_x',(-8,0,1.2)),('top',(0,0,8)),('three_quarter',(5,8,4))]:
 cam.location=Vector(pos);cam.rotation_euler=(Vector((0,0,1.1))-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(pkg/'previews'/f'v002_{name}.png');bpy.ops.render.render(write_still=True)
print('FAT_ZOMBIE03_MODEL_V002_OK',json.dumps(report))
