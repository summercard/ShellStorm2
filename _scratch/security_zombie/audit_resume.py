import bpy,json
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2')
base=P/'assets/art/enemies/normal_enemy_3d'
paths=[base/'melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend',base/'melee_chaser/source/animation/enm_melee_fungboar01_animation_v003.blend',base/'ranged_caster/source/model/enm_ranged_sporeshooter01_model_v001.blend',base/'ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v001.blend']
rows=[]
for path in paths:
 bpy.ops.wm.open_mainfile(filepath=str(path))
 row={'file':str(path),'objects':[],'actions':[]}
 for o in bpy.context.scene.objects:
  d={'name':o.name,'type':o.type,'matrix':[list(r) for r in o.matrix_world]}
  if o.type=='ARMATURE':d['bones']=[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local),'matrix':[list(r) for r in b.matrix_local]} for b in o.data.bones]
  if o.type=='MESH':
   d['vertices']=len(o.data.vertices);d['unweighted']=sum(not v.groups for v in o.data.vertices);d['modifiers']=[(m.type,m.object.name if m.type=='ARMATURE' and m.object else '') for m in o.modifiers]
  row['objects'].append(d)
 for a in bpy.data.actions:row['actions'].append({'name':a.name,'frames':list(a.frame_range),'slots':[s.identifier for s in a.slots] if hasattr(a,'slots') else []})
 rows.append(row)
out=P/'_scratch/security_zombie/audit_resume.json';out.write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
print('RESUME_AUDIT_OK',out)
