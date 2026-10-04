import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/rig_v007';P.mkdir(exist_ok=True)
targets={'large_eye':2.20,'round_eye':2.10,'mouth':1.20};signatures=[]
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v006.blend'))
 s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
 if rig.animation_data:rig.animation_data.action=None
 delta={n:z-bpy.data.objects['Texture '+n].location.z for n,z in targets.items()}
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
 for n,dz in delta.items():
  for prefix in ['face_','face_anchor_']:
   b=arm.edit_bones[prefix+n];b.head.z+=dz;b.tail.z+=dz
 bpy.ops.object.mode_set(mode='OBJECT')
 for n,z in targets.items():bpy.data.objects['Texture '+n].location.z=z
 rig['skeleton_id']='SKEL-MONITOR002-003';arm.name=rig['skeleton_id'];s['skeleton_id']=rig['skeleton_id'];s['asset_version']='v007';bpy.context.view_layer.update()
 signature=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest();signatures.append(signature)
 bpy.ops.wm.save_as_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v007.blend'))
assert len(set(signatures))==1
c=json.loads((B/'source/rig_contract_v006.json').read_text());c.update(version='v007',skeleton_id='SKEL-MONITOR002-003',skeleton_signature=signatures[0],face_anchor_z=targets,animation_design='docs/v0.1/design/Boss002显示器动画设计.md',formal_animations_authored=False)
(B/'source/rig_contract_v007.json').write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;cam=s.camera;cam.location=(2,12,4);cam.rotation_euler=(Vector((0,0,1.9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.2;s.cycles.samples=20;s.render.resolution_x=1100;s.render.resolution_y=850;s.render.filepath=str(P/'face_lowered.png');bpy.ops.render.render(write_still=True)
