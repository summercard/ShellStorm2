import bpy, json
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
MELEE = P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend'
OUT = P/'_scratch/security_zombie/melee_skeleton_ref.json'

bpy.ops.wm.open_mainfile(filepath=str(MELEE))
arm = next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = {e.name: e for e in arm.data.edit_bones}
rows = []
for b in arm.data.bones:
    e = eb[b.name]
    rows.append({
        'name': b.name,
        'parent': b.parent.name if b.parent else None,
        'head': [round(c,6) for c in b.head_local],
        'tail': [round(c,6) for c in b.tail_local],
        'roll': round(e.roll,6),
        'x_axis': [round(c,6) for c in e.x_axis],
        'y_axis': [round(c,6) for c in e.y_axis],
        'z_axis': [round(c,6) for c in e.z_axis],
        'matrix': [list(r) for r in e.matrix],
        'use_connect': e.use_connect,
    })
bpy.ops.object.mode_set(mode='OBJECT')
OUT.write_text(json.dumps({'armature':arm.name,'skeleton_id':arm.data.get('skeleton_id'),'bones':rows},ensure_ascii=False,indent=2),encoding='utf-8')
for r in rows:
    print('%-14s parent=%-14s head=%s roll=%.4f' % (r['name'], r['parent'], r['head'], r['roll']))
print('MELEE_REF_OK', len(rows))
