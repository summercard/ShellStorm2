import bpy,json
from pathlib import Path
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2');f=P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(f))
out={}
for o in bpy.context.scene.objects:
 out[o.name]={'type':o.type,'parent':o.parent.name if o.parent else None,'matrix_world':[list(r) for r in o.matrix_world],'matrix_parent_inverse':[list(r) for r in o.matrix_parent_inverse]}
print(json.dumps(out,indent=2))
