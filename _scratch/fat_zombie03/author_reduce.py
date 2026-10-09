import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[2]
pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
out=root/'outputs/fat_zombie03_reduction';out.mkdir(parents=True,exist_ok=True)
t=json.loads((pkg/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
def signature(rig):
 return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in rig.data.bones]).encode()).hexdigest()
def action_hash():
 return {a.name:hashlib.sha256(repr([(f.data_path,f.array_index,[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation) for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest() for a in bpy.data.actions}
bpy.ops.wm.open_mainfile(filepath=str(root/t['animation_source']))
s=bpy.context.scene;rig=next(o for o in s.objects if o.type=='ARMATURE');old=next(o for o in s.objects if o.type=='MESH')
before_actions=action_hash();sig=signature(rig);assert sig==t['skeleton_signature']
shape_action=old.data.shape_keys.animation_data.action
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
old.data.shape_keys.animation_data.action=None
for key in old.data.shape_keys.key_blocks:key.value=0
new=old.copy();new.data=old.data.copy();s.collection.objects.link(new)
new.name=old.name+'_optimized'
for key in list(new.data.shape_keys.key_blocks)[1:]:
 attr=new.data.attributes.new('keep_'+key.name,'FLOAT_VECTOR','POINT')
 for i,v in enumerate(key.data):attr.data[i].vector=v.co-new.data.vertices[i].co
new.shape_key_clear()
for mod in list(new.modifiers):new.modifiers.remove(mod)
bpy.context.view_layer.objects.active=new
dec=new.modifiers.new('TopologyReduction','DECIMATE');dec.ratio=.348;dec.use_collapse_triangulate=True
protect=new.vertex_groups.new(name='ReductionFeaturePriority')
for v in new.data.vertices:
 feature=any(g.weight>.25 and any(x in new.vertex_groups[g.group].name for x in ['Head','Hand','Thumb','Index','Middle','Pinky','Ring']) for g in v.groups)
 protect.add([v.index],.8 if feature else .05,'REPLACE')
dec.vertex_group=protect.name;dec.vertex_group_factor=.03;dec.invert_vertex_group=True
bpy.ops.object.modifier_apply(modifier=dec.name)
new.vertex_groups.remove(new.vertex_groups['ReductionFeaturePriority'])
new.shape_key_add(name='Basis');key=new.shape_key_add(name='BellyGroundCompression')
attr=new.data.attributes['keep_BellyGroundCompression']
for i,v in enumerate(key.data):v.co=new.data.vertices[i].co+attr.data[i].vector
new.data.attributes.remove(attr)
arm=new.modifiers.new('Armature','ARMATURE');arm.object=rig
arm.use_deform_preserve_volume=old.modifiers[0].use_deform_preserve_volume
# Normalize interpolated weights and retain all deformer identities.
for v in new.data.vertices:
 groups=sorted([(g.group,g.weight) for g in v.groups],key=lambda x:x[1],reverse=True)
 for group,weight in groups[4:]:new.vertex_groups[group].remove([v.index])
 total=sum(g.weight for g in v.groups)
 assert total>0
 for g in list(v.groups):new.vertex_groups[g.group].add([v.index],g.weight/total,'REPLACE')
tris=sum(len(p.vertices)-2 for p in new.data.polygons);assert tris<2000
def points(obj):
 ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();p=[v.co.copy() for v in me.vertices];f=[tuple(x.vertices) for x in me.polygons];ev.to_mesh_clear();return p,f
def distances(a,b):
 ap,af=a;bp,bf=b;tree=BVHTree.FromPolygons(bp,bf);d=[tree.find_nearest(v)[3]*.7 for v in ap];d.sort()
 return {'max_m':max(d),'p95_m':d[int(.95*(len(d)-1))],'mean_m':sum(d)/len(d)}
report={'asset_id':t['asset_id'],'before_triangles':5690,'triangles':tris,'vertices':len(new.data.vertices),'skeleton_signature':sig,'bone_count':len(rig.data.bones),'actions_unchanged':True,'clips':{},'samples':[]}
old.data.shape_keys.animation_data_create();new.data.shape_keys.animation_data_create()
# Refit only the contact morph so interpolation cannot push the reduced belly below ground.
rig.animation_data.action=bpy.data.actions['dead']
new.data.shape_keys.animation_data.action=shape_action
new.data.shape_keys.animation_data.action_slot=shape_action.slots[0]
correction={}
for iteration in range(2):
 for k in range(313):
  s.frame_set(k//4,subframe=k%4/4);bpy.context.view_layer.update();value=key.value
  if value<.02:continue
  pts=points(new)[0]
  for i,co in enumerate(pts):
   if co.z>=.002/.7:continue
   v=new.data.vertices[i];skin=Matrix(((0,0,0,0),)*4)
   for g in v.groups:
    bone=rig.pose.bones[new.vertex_groups[g.group].name]
    skin+=(bone.matrix@bone.bone.matrix_local.inverted())*g.weight
   delta=skin.to_3x3().inverted_safe()@Vector((0,0,(.002/.7-co.z)/value))
   key.data[i].co+=delta;correction[i]=correction.get(i,0)+delta.length*.7
  new.data.update()
report['contact_refit']={'vertices':len(correction),'max_rest_delta_m':max(correction.values(),default=0),'samples':626}
for clip in t['planned_clips']:
 name=clip['name'];rig.animation_data.action=bpy.data.actions[name]
 for obj in [old,new]:
  obj.data.shape_keys.animation_data.action=shape_action if name=='dead' else None
  if name=='dead':obj.data.shape_keys.animation_data.action_slot=shape_action.slots[0]
  obj.data.shape_keys.key_blocks['BellyGroundCompression'].value=0
 minimum=100;maxdiff=0;max95=0
 for f in range(0,clip['last_frame']+1,3):
  s.frame_set(f);bpy.context.view_layer.update();original=points(old);reduced=points(new)
  minimum=min(minimum,min(v.z*.7 for v in reduced[0]))
  d=distances(original,reduced);rev=distances(reduced,original)
  maxdiff=max(maxdiff,d['max_m'],rev['max_m']);max95=max(max95,d['p95_m'],rev['p95_m'])
  if f in [0,12,30,36,60,78]:report['samples'].append({'clip':name,'frame':f,'original_to_reduced':d,'reduced_to_original':rev})
 report['clips'][name]={'min_z_m':minimum,'max_surface_error_m':maxdiff,'max_p95_surface_error_m':max95}
 assert minimum>-.005,(name,minimum)
assert before_actions==action_hash()
(out/'source_comparison.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('REDUCTION_METRICS',json.dumps({k:v for k,v in report.items() if k!='samples'}),flush=True)
# Save the exact optimized model in both new masters, keeping the authored actions.
old_name=old.name;old_mesh=old.data
bpy.data.objects.remove(old,do_unlink=True);new.name=old_name;new.data.name=old_mesh.name+'_reduced'
rig.animation_data.action=bpy.data.actions['idle'];new.data.shape_keys.animation_data.action=None;key.value=0;s.frame_set(0)
bpy.context.preferences.filepaths.save_version=0
animation=pkg/'source/animation/enm_normal_fat_zombie03_animation_v009.blend'
model=pkg/'source/model/enm_normal_fat_zombie03_model_v004.blend'
new.data.shape_keys.animation_data.action=shape_action
new.data.shape_keys.animation_data.action_slot=shape_action.slots[0]
# Store death shape action as a fake user; runtime uses the original 13 exported curves.
shape_action.use_fake_user=True
rig.animation_data.action=bpy.data.actions['dead'];s.frame_set(60)
bpy.ops.wm.save_as_mainfile(filepath=str(animation))
rig.animation_data.action=None;new.data.shape_keys.animation_data.action=None;key.value=0
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
bpy.ops.wm.save_as_mainfile(filepath=str(model))
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);new.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'geometry.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
print('REDUCTION_MASTERS_OK',tris,flush=True)
