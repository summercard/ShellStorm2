import bpy, json, sys
from pathlib import Path
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
FBX = P/'_scratch/security_zombie/police_source/tripo_convert_f72ff985-096a-4f37-8d40-5455761bf423.fbx'
OUT = P/'_scratch/security_zombie/police_skeleton_raw.json'
log = open(P/'_scratch/security_zombie/inspect_police.log','w',encoding='utf-8')
def P_(s):
    log.write(str(s)+'\n'); log.flush()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(FBX))
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type=='ARMATURE')
mesh = next(o for o in scene.objects if o.type=='MESH')
P_('objects: %s' % [(o.name,o.type) for o in scene.objects])
P_('armature %r bones=%d  mesh %r verts=%d groups=%d' % (arm.name, len(arm.data.bones), mesh.name, len(mesh.data.vertices), len(mesh.vertex_groups)))
P_('arm matrix_world=%s' % [list(r) for r in arm.matrix_world])
P_('mesh matrix_world=%s' % [list(r) for r in mesh.matrix_world])
P_('mesh parent=%r modifiers=%s' % (mesh.parent.name if mesh.parent else None, [(m.type, m.object.name if getattr(m,'object',None) else None) for m in mesh.modifiers]))

rows = []
for b in arm.data.bones:
    rows.append({'name':b.name,'parent':b.parent.name if b.parent else None,
                 'head':[round(c,5) for c in b.head_local],'tail':[round(c,5) for c in b.tail_local]})
P_('BONES %d' % len(rows))
for r in rows: P_('  %-24s parent=%-22s head=%s tail=%s' % (r['name'], r['parent'], r['head'], r['tail']))
P_('GROUPS %d: %s' % (len(mesh.vertex_groups), [g.name for g in mesh.vertex_groups]))

# world bbox
from mathutils import Vector
lo=Vector((1e9,)*3); hi=Vector((-1e9,)*3)
for v in mesh.data.vertices:
    w=mesh.matrix_world@v.co
    for i in range(3):
        lo[i]=min(lo[i],w[i]); hi[i]=max(hi[i],w[i])
P_('world bbox min=%s max=%s size=%s' % ([round(c,4) for c in lo],[round(c,4) for c in hi],[round(hi[i]-lo[i],4) for i in range(3)]))
d={'armature':arm.name,'mesh':mesh.name,'bones':rows,'groups':[g.name for g in mesh.vertex_groups],
   'arm_matrix_world':[list(r) for r in arm.matrix_world],'mesh_matrix_world':[list(r) for r in mesh.matrix_world],
   'world_min':list(lo),'world_max':list(hi)}
OUT.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
log.close()
print('POLICE_RAW_OK', len(rows))
