import bpy, json
from pathlib import Path
from mathutils import Vector
p=Path(__file__).parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(next((p/'extracted').glob('*.fbx'))))
report={'objects':[], 'armatures':[], 'actions':[],'images':[]}
for o in bpy.context.scene.objects:
 d={'name':o.name,'type':o.type,'location':list(o.location),'rotation':list(o.rotation_euler),'scale':list(o.scale)}
 if o.type=='MESH':
  pts=[o.matrix_world@v.co for v in o.data.vertices]
  d.update(vertices=len(pts),polygons=len(o.data.polygons),triangles=sum(len(f.vertices)-2 for f in o.data.polygons),uv_layers=len(o.data.uv_layers),bounds_min=[min(v[i] for v in pts) for i in range(3)],bounds_max=[max(v[i] for v in pts) for i in range(3)],materials=[s.material.name if s.material else None for s in o.material_slots],vertex_groups=[g.name for g in o.vertex_groups],unweighted=sum(not any(g.weight>0 for g in v.groups) for v in o.data.vertices),modifiers=[{'type':m.type,'target':getattr(getattr(m,'object',None),'name',None)} for m in o.modifiers])
 report['objects'].append(d)
 if o.type=='ARMATURE':report['armatures'].append({'name':o.name,'bones':[{'name':b.name,'parent':b.parent.name if b.parent else None,'deform':b.use_deform} for b in o.data.bones]})
for a in bpy.data.actions:report['actions'].append({'name':a.name,'frames':list(a.frame_range)})
for im in bpy.data.images:report['images'].append({'name':im.name,'path':im.filepath,'size':list(im.size),'exists':Path(bpy.path.abspath(im.filepath)).exists()})
(p/'source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(p/'raw_import.blend'))
print('FAT_ZOMBIE_SOURCE_AUDIT_OK')
