import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Matrix
p=Path(__file__).parent; root=p.parents[1]
pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
prefix='enm_normal_fat_zombie03'
for d in ['source/model/textures','source/original','components','runtime','previews']: (pkg/d).mkdir(parents=True,exist_ok=True)
(pkg/'source/.gdignore').write_bytes(b'\r\n')
fbx=next((p/'extracted').glob('*.fbx')); shutil.copy2(fbx,pkg/'source/original'/f'{prefix}_source_v001.fbx')
tex=next((p/'extracted').rglob('*.JPEG')); targettex=pkg/'source/model/textures'/f'{prefix}_basecolor_v001.jpeg'; shutil.copy2(tex,targettex)
bpy.ops.wm.open_mainfile(filepath=str(p/'raw_import.blend'))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
# Apply world coordinates directly to mesh and skeleton. Preserve existing weights.
meshworld=mesh.matrix_world.copy(); armworld=arm.matrix_world.copy()
mesh.parent=None; mesh.matrix_world=Matrix.Identity(4); mesh.data.transform(meshworld)
bpy.context.view_layer.objects.active=arm; bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones: b.transform(armworld)
bpy.ops.object.mode_set(mode='OBJECT'); arm.matrix_world=Matrix.Identity(4)
mesh.parent=arm; mesh.matrix_parent_inverse=Matrix.Identity(4)
pts=[v.co for v in mesh.data.vertices]; low=min(v.z for v in pts); high=max(v.z for v in pts)
factor=(1.3/.7)/(high-low)
transform=Matrix.Scale(factor,4)@Matrix.Translation((0,0,-low))
# Source preview determines front; initial source faces -Y, rotate to contract +Y.
transform=Matrix.Rotation(math.pi,4,'Z')@transform
mesh.data.transform(transform)
bpy.context.view_layer.objects.active=arm; bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones: b.transform(transform)
bpy.ops.object.mode_set(mode='OBJECT')
arm.name=prefix+'_armature'; arm.data.name=arm.name; mesh.name=prefix+'_mesh'; mesh.data.name=mesh.name
for mat in mesh.data.materials:
 mat.name=prefix+'_material'
 for n in mat.node_tree.nodes:
  if n.type=='TEX_IMAGE' and n.image:
   n.image.name=prefix+'_basecolor'; n.image.filepath=str(targettex); n.image.pack(); n.image.filepath='//textures/'+targettex.name
arm.data['skeleton_id']='SKEL-FAT-ZOMBIE03-MIXAMO-001'
pts=[v.co for v in mesh.data.vertices]
lo=[min(v[i] for v in pts) for i in range(3)]; hi=[max(v[i] for v in pts) for i in range(3)]
weights=[sum(g.weight for g in v.groups) for v in mesh.data.vertices]
sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in arm.data.bones]).encode()).hexdigest()
report={'asset_id':'ENM-NORMAL-FAT-ZOMBIE03','source_number':'03','source_bounds_m':[hi[i]-lo[i] for i in range(3)],'bounds_min':lo,'bounds_max':hi,'game_bounds_at_0_70':[.7*(hi[i]-lo[i]) for i in range(3)],'vertices':len(pts),'triangles':sum(len(f.vertices)-2 for f in mesh.data.polygons),'bones':len(arm.data.bones),'bone_names':[b.name for b in arm.data.bones],'skeleton_signature':sig,'actions':[],'unweighted':sum(w<1e-6 for w in weights),'weight_sum_errors':sum(abs(w-1)>1e-3 for w in weights),'weight_sum_range':[min(weights),max(weights)],'max_influences':max(len(v.groups) for v in mesh.data.vertices),'texture_size':list(next(im for im in bpy.data.images if im.name==prefix+'_basecolor').size),'status':'imported_pending_rig_and_animation','missing_clips':['idle','walking','running','attack','hurt','dead']}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(pkg/'source/model'/f'{prefix}_model_v001.blend'))
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); mesh.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(pkg/'components'/f'{prefix}_visual_top3d.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
(pkg/'source/model/model_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copy2(p/'source_audit.json',pkg/'source/original/source_audit.json')
# Render six directions with real material and a 1.2m player height marker.
sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=16
sc.render.resolution_x=640; sc.render.resolution_y=640; sc.render.resolution_percentage=100
if sc.world is None: sc.world=bpy.data.worlds.new('PreviewWorld')
sc.world.color=(.22,.22,.22)
for loc in [(3,4,5),(-3,-2,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc); bpy.context.object.data.energy=450; bpy.context.object.data.shape='DISK'; bpy.context.object.data.size=4
bpy.ops.object.camera_add(); cam=bpy.context.object; sc.camera=cam; cam.data.type='ORTHO'; cam.data.ortho_scale=4.5
for name,pos in [('front_plus_y',(0,6,1.1)),('back_minus_y',(0,-6,1.1)),('side_plus_x',(6,0,1.1)),('side_minus_x',(-6,0,1.1)),('top',(0,0,7)),('three_quarter',(4,6,3))]:
 cam.location=Vector(pos); cam.rotation_euler=(Vector((0,0,.95))-cam.location).to_track_quat('-Z','Y').to_euler(); sc.render.filepath=str(pkg/'previews'/f'{name}.png'); bpy.ops.render.render(write_still=True)
print('FAT_ZOMBIE03_PREPARED',json.dumps(report))
