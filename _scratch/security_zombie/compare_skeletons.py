import bpy,json
from pathlib import Path
P=Path(r"I:\工作项目\shellstrom2\ShellStorm2")
def inspect(path,fbx=False):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 if fbx: bpy.ops.import_scene.fbx(filepath=str(path))
 else: bpy.ops.wm.open_mainfile(filepath=str(path))
 arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
 mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
 names=[b.name for b in arm.data.bones]
 groups=[g.name for g in mesh.vertex_groups]
 lo=[1e9]*3; hi=[-1e9]*3
 for v in mesh.data.vertices:
  p=mesh.matrix_world@v.co
  for i in range(3): lo[i]=min(lo[i],p[i]);hi[i]=max(hi[i],p[i])
 return {'armature':arm.name,'mesh':mesh.name,'bones':names,'bone_count':len(names),'groups':groups,'group_count':len(groups),'bbox':[hi[i]-lo[i] for i in range(3)],'min':lo,'max':hi,'scene_objects':[(o.name,o.type) for o in bpy.context.scene.objects]}
print(json.dumps({'new':inspect(P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx',True),'old':inspect(P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend')},ensure_ascii=False,indent=2))