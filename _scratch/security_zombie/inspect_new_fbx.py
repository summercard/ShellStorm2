import bpy,json
from pathlib import Path
P=Path(r"I:\工作项目\shellstrom2\ShellStorm2")
fbx=P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx'
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=str(fbx))
rows=[]
for o in bpy.context.scene.objects:
 if o.type=='ARMATURE':
  rows=[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local)} for b in o.data.bones]
print(json.dumps({'objects':[(o.name,o.type) for o in bpy.context.scene.objects],'armature_bones':rows},ensure_ascii=False,indent=2))