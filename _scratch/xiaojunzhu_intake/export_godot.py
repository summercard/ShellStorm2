import bpy,json,hashlib
from pathlib import Path
P=Path(__file__).parent
root=P.parents[1]
asset=root/'assets/art/enemies/normal_enemy_3d/melee_chaser'
meta=json.loads((P/'animation_meta_v003.json').read_text(encoding='utf-8'))
def sig(a):
 return [(b.name,b.parent.name if b.parent else '',[round(x,6) for row in b.matrix_local for x in row]) for b in a.data.bones]
bpy.ops.wm.open_mainfile(filepath=str(asset/'source/model/enm_melee_fungboar01_model_v002.blend'))
model_sig=sig(next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'))
bpy.ops.wm.open_mainfile(filepath=meta['animation'])
scene=bpy.data.scenes[meta['clips'][0]['scene']];bpy.context.window.scene=scene
a=next(o for o in scene.objects if o.type=='ARMATURE');m=next(o for o in scene.objects if o.type=='MESH')
assert sig(a)==model_sig,'skeleton mismatch'
# Remove other scene copies and preview content in this in-memory export copy only.
for obj in list(bpy.data.objects):
 if obj not in [a,m]:bpy.data.objects.remove(obj,do_unlink=True)
for s in list(bpy.data.scenes):
 if s!=scene:bpy.data.scenes.remove(s)
a.name='ZombieRig';m.name='ZombieMesh'
a.animation_data_clear();a.animation_data_create()
for entry in meta['clips']:
 action=bpy.data.actions[entry['action']];action.name=entry['id'];action.use_frame_range=True;action.frame_start=1;action.frame_end=entry['frames']+1
 track=a.animation_data.nla_tracks.new();track.name=entry['id']
 strip=track.strips.new(entry['id'],1,action);strip.action_frame_start=1;strip.action_frame_end=entry['frames']+1;strip.frame_start=1;strip.frame_end=entry['frames']+1
 track.mute=True
scene.render.fps=30;scene.frame_start=1;scene.frame_end=97;scene.frame_set(1)
for pb in a.pose.bones:pb.matrix_basis.identity()
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True);bpy.context.view_layer.objects.active=a
out=asset/'components/enm_melee_fungboar01_visual_top3d.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_nla_strips_merged_animation_name='unused',export_yup=True)
r={'asset_id':'ENM-MELEE-FUNGBOAR01','display_name':'小僵尸','status':'exported_pending_godot_validation','model':meta['model'],'animation':meta['animation'],'skeleton_signature':hashlib.sha256(json.dumps(model_sig).encode()).hexdigest(),'clips':meta['clips'],'outputs':{str(out.relative_to(root)):hashlib.sha256(out.read_bytes()).hexdigest()},'limitations':['源跑步亚帧约1.3mm穿地；未完成全程自穿插/支撑脚滑移质量审查'],'source_sha256':{str(Path(f).relative_to(root)):hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in [meta['model'],meta['animation']]}}
(asset/'runtime/character_transfer_ledger.json').write_bytes((json.dumps(r,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode())
print('ZOMBIE_EXPORT_OK',out)
