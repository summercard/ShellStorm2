import bpy,json,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/melee_chaser';out=root/'outputs/melee_zombie_reduction'
t=json.loads((pkg/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=t['animation'])
scene=bpy.context.scene;oldrig=next(o for o in scene.objects if o.type=='ARMATURE');old=next(o for o in scene.objects if o.type=='MESH')
rig=oldrig.copy();rig.data=oldrig.data.copy();scene.collection.objects.link(rig)
m=old.copy();m.data=old.data.copy();scene.collection.objects.link(m);m.parent=rig
for index,material in enumerate(m.data.materials):
 local=material.copy();m.data.materials[index]=local
 for node in local.node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.image:
   node.image=node.image.copy();node.image.filepath=str(pkg/'source/model/textures/enm_melee_fungboar01_basecolor_v002.png');node.image.reload();node.image.pack()
for mod in m.modifiers:
 if mod.type=='ARMATURE':mod.object=rig
fingers=[b.name for b in rig.data.bones if any(x in b.name for x in ['Thumb','Index','Middle','Pinky','Ring'])]
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
oldrig.animation_data.action=bpy.data.actions[t['clips'][0]['action']];scene.frame_set(1);bpy.context.view_layer.update()
# Freeze fingers in their authored idle curl, expressed relative to the unchanged hand bind.
for v in m.data.vertices:
 if not any(m.vertex_groups[g.group].name in fingers and g.weight>0 for g in v.groups):continue
 skin=Matrix(((0,0,0,0),)*4)
 for g in v.groups:
  n=m.vertex_groups[g.group].name
  if n in fingers:
   hand=n[:2]+'Hand';transform=(oldrig.pose.bones[hand].matrix@rest[hand].inverted()).inverted()@oldrig.pose.bones[n].matrix@rest[n].inverted()
  else:transform=Matrix.Identity(4)
  skin+=transform*g.weight
 v.co=skin@v.co
for side in ['L_','R_']:
 hand=m.vertex_groups[side+'Hand']
 for v in m.data.vertices:
  weight=sum(g.weight for g in v.groups if m.vertex_groups[g.group].name in fingers and m.vertex_groups[g.group].name.startswith(side))
  if weight:hand.add([v.index],weight,'ADD')
for n in fingers:m.vertex_groups.remove(m.vertex_groups[n])
bpy.context.view_layer.objects.active=rig;bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for n in fingers:rig.data.edit_bones.remove(rig.data.edit_bones[n])
bpy.ops.object.mode_set(mode='OBJECT')
rig.data['skeleton_id']='SKEL-MELEE-ZOMBIE01-003'
for mod in list(m.modifiers):m.modifiers.remove(mod)
priority=m.vertex_groups.new(name='ReducePriority')
for v in m.data.vertices:
 feature=any(g.weight>.25 and any(x in m.vertex_groups[g.group].name for x in ['Head','Hand']) for g in v.groups)
 priority.add([v.index],.8 if feature else .05,'REPLACE')
bpy.context.view_layer.objects.active=m;m.select_set(True)
mod=m.modifiers.new('Reduce','DECIMATE');mod.ratio=1790/4552;mod.use_collapse_triangulate=True;mod.vertex_group=priority.name;mod.vertex_group_factor=.03;mod.invert_vertex_group=True
bpy.ops.object.modifier_apply(modifier=mod.name);m.vertex_groups.remove(m.vertex_groups['ReducePriority'])
for v in m.data.vertices:
 groups=sorted([(g.group,g.weight) for g in v.groups],key=lambda x:x[1],reverse=True)
 for i,w in groups[4:]:m.vertex_groups[i].remove([v.index])
 total=sum(g.weight for g in v.groups);assert total>0
 for g in list(v.groups):m.vertex_groups[g.group].add([v.index],g.weight/total,'REPLACE')
mod=m.modifiers.new('Armature','ARMATURE');mod.object=rig
triangles=sum(len(p.vertices)-2 for p in m.data.polygons);assert triangles<1800
def pts(obj):
 ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();p=[v.co.copy() for v in me.vertices];f=[tuple(x.vertices) for x in me.polygons];ev.to_mesh_clear();return p,f
report={'triangles':triangles,'vertices':len(m.data.vertices),'before_triangles':4552,'before_bones':36,'bones':len(rig.data.bones),'removed_bones':fingers,'clips':{},'preserved_body_curves':True}
actions={}
for clip in t['clips']:
 orig=bpy.data.actions[clip['action']];act=orig.copy();act.name=clip['id'];act.use_fake_user=True
 for fc in list(act.fcurves):
  if any('"'+n+'"' in fc.data_path for n in fingers):act.fcurves.remove(fc)
 actions[clip['id']]=act
 oldrig.animation_data.action=orig;rig.animation_data.action=act
 if act.slots:rig.animation_data.action_slot=act.slots[0]
 minimum=100;surface95=0;surface_max=0
 for k in range(clip['frames']*2+1):
  f=1+k/2;scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update();op,of=pts(old);np,nf=pts(m);minimum=min(minimum,min(v.z*.7 for v in np))
  if k%6==0:
   tree=BVHTree.FromPolygons(np,nf);ds=sorted(tree.find_nearest(v)[3]*.7 for v in op);surface95=max(surface95,ds[int(len(ds)*.95)]);surface_max=max(surface_max,max(ds))
 report['clips'][clip['id']]={'min_z_m':minimum,'p95_surface_error_m':surface95,'max_surface_error_m':surface_max,'samples':clip['frames']*2+1}
 assert minimum>-.006,(clip['id'],minimum)
sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in rig.data.bones]).encode()).hexdigest();report['skeleton_signature']=sig
original_name=old.name;rig_name=oldrig.name
for obj in list(bpy.data.objects):
 if obj not in [rig,m]:bpy.data.objects.remove(obj,do_unlink=True)
for sc in list(bpy.data.scenes):
 if sc!=scene:bpy.data.scenes.remove(sc)
rig.name=rig_name;m.name=original_name
for act in list(bpy.data.actions):
 if act not in actions.values():bpy.data.actions.remove(act)
scene.name='MeleeZombieActions';rig.animation_data.action=actions['idle'];scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
model=pkg/'source/model/enm_melee_fungboar01_model_v003.blend';animation=pkg/'source/animation/enm_melee_fungboar01_animation_v004.blend'
for im in bpy.data.images:
 if not im.library and list(im.size)!=[0,0]:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(animation))
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
for act in list(bpy.data.actions):bpy.data.actions.remove(act)
bpy.ops.wm.save_as_mainfile(filepath=str(model))
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'geometry.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
(out/'source_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('MELEE_REDUCED',json.dumps(report),flush=True)
