import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[2];p=root/'assets/art/enemies/normal_enemy_3d/melee_chaser';t=json.loads((p/'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
out=root/'outputs/melee_zombie_reduction';out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=t['animation'])
r={'scenes':[]}
for s in bpy.data.scenes:
 r['scenes'].append({'name':s.name,'objects':[(o.name,o.type,o.data.name if o.data else None,o.animation_data.action.name if o.animation_data and o.animation_data.action else None) for o in s.objects]})
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH')
r.update(bones=[(b.name,b.parent.name if b.parent else None) for b in rig.data.bones],vertices=len(m.data.vertices),triangles=sum(len(p.vertices)-2 for p in m.data.polygons),shapes=list(m.data.shape_keys.key_blocks.keys()) if m.data.shape_keys else [],modifiers=[(x.name,x.type) for x in m.modifiers],actions=[(a.name,len(a.fcurves),list(a.frame_range)) for a in bpy.data.actions])
(out/'baseline_source.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(r,ensure_ascii=False),flush=True)
