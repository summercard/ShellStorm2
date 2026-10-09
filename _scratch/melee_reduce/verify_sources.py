import bpy,json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/melee_chaser';out=root/'outputs/melee_zombie_reduction';t=json.loads((pkg/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'));report={'sources':[]}
def curves(act):return { (f.data_path,f.array_index):[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation) for k in f.keyframe_points] for f in act.fcurves if not any(n in f.data_path for n in ['Thumb','Index','Middle','Pinky','Ring'])}
bpy.ops.wm.open_mainfile(filepath=t['animation']);expected={c['id']:curves(bpy.data.actions[c['action']]) for c in t['clips']}
for kind,path in [('model',pkg/'source/model/enm_melee_fungboar01_model_v003.blend'),('animation',pkg/'source/animation/enm_melee_fungboar01_animation_v004.blend')]:
 bpy.ops.wm.open_mainfile(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH')
 sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in rig.data.bones]).encode()).hexdigest()
 assert len(rig.data.bones)==20 and len(m.data.polygons)<1800
 assert not any(any(n in b.name for n in ['Thumb','Index','Middle','Pinky','Ring']) for b in rig.data.bones)
 assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 and 1<=len(v.groups)<=4 for v in m.data.vertices)
 assert all(g.name in rig.data.bones for g in m.vertex_groups)
 assert all(abs(v-1)<1e-6 for obj in [rig,m] for v in obj.scale)
 images=[list(im.size) for im in bpy.data.images if im.users];assert [512,512] in images
 if kind=='animation':
  for name,c in expected.items():assert curves(bpy.data.actions[name])==c,name
 report['sources'].append({'kind':kind,'signature':sig,'vertices':len(m.data.vertices),'triangles':len(m.data.polygons),'bones':20,'weights_normalized':True,'max_influences':max(len(v.groups) for v in m.data.vertices),'texture_sizes':images,'retained_curves_identical':True})
assert report['sources'][0]['signature']==report['sources'][1]['signature'];report['passed']=True
(out/'reopen.json').write_text(json.dumps(report,indent=2));print('MELEE_REOPEN_OK')
