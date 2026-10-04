import bpy,json,struct
from pathlib import Path
from mathutils import Vector
p=Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03');f=p/'source/animation/enm_normal_fat_zombie03_animation_v008.blend';bpy.ops.wm.open_mainfile(filepath=str(f));s=bpy.context.scene;a=next(o for o in s.objects if o.type=='ARMATURE');m=next(o for o in s.objects if o.type=='MESH');hip=a.pose.bones['Hip'];corrections=[]
for k in range(313):
 s.frame_set(k//4,subframe=k%4/4);ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();low=min(v.co.z for v in me.vertices);ev.to_mesh_clear();corrections.append(max(0,.002-low))
for k,c in enumerate(corrections):
 s.frame_set(k//4,subframe=k%4/4);hip.location+=hip.bone.matrix_local.to_3x3().inverted()@Vector((0,0,c));hip.keyframe_insert('location',frame=k/4)
s.frame_set(60);bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(f))
g=p/'components/enm_normal_fat_zombie03_visual_top3d.glb';raw=g.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);buf=bytearray(raw[28+n:]);act=next(x for x in d['animations'] if x['name']=='dead')
for ch in act['channels']:
 if ch['target']['path']!='translation' or d['nodes'][ch['target']['node']].get('name')!='Hip':continue
 sam=act['samplers'][ch['sampler']];ina=d['accessors'][sam['input']];out=d['accessors'][sam['output']];iv=d['bufferViews'][ina['bufferView']];ov=d['bufferViews'][out['bufferView']]
 for i in range(out['count']):
  time=struct.unpack_from('<f',buf,iv.get('byteOffset',0)+ina.get('byteOffset',0)+4*i)[0];k=min(312,round(time*120));offset=ov.get('byteOffset',0)+out.get('byteOffset',0)+12*i+4;y=struct.unpack_from('<f',buf,offset)[0];struct.pack_into('<f',buf,offset,y+corrections[k])
g.write_bytes(raw[:28+n]+buf)
(p/'previews/belly_v008/contact_correction.json').write_text(json.dumps({'max_lift_source_m':max(corrections),'samples':313}),encoding='utf-8')
