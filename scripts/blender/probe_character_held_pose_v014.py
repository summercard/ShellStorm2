"""Read-only candidate check for anatomical reach and gun/head clearance."""
from pathlib import Path
import bpy, math
from mathutils import Vector, Matrix, Euler
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(root/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v014/source/animation/chr_bunny01_animation_v014.blend'))
s=bpy.data.scenes['05_单手持枪_小跑']; bpy.context.window.scene=s; s.frame_set(1)
r=next(o for o in s.objects if o.type=='ARMATURE'); r.animation_data_clear()
rest={b.name:b.matrix_local.copy() for b in r.data.bones}
dg=bpy.context.evaluated_depsgraph_get(); er=r.evaluated_get(dg)
base={p.name:p.matrix.copy() for p in er.pose.bones}
def tree(obj):
    e=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); m=e.to_mesh()
    result=BVHTree.FromPolygons([e.matrix_world@v.co for v in m.vertices],[list(p.vertices) for p in m.polygons])
    e.to_mesh_clear(); return result
head=next(o for o in s.objects if o.type=='MESH' and o.get('component_id')=='head' and o.get('variant_id')!='chibi_anime')
gun=next(o for o in s.objects if o.type=='MESH' and o.get('preview_only'))
ht=tree(head)
results=[]
for y in [0,.01,.025,.05]:
 for z in [-.06,-.045,-.03,-.015,0]:
  for yaw in [-.5,-.25,0,.25,.5]:
   posed={k:v.copy() for k,v in base.items()}
   direction=Vector((.08,y,z)).normalized()
   shoulder=(posed['chest']@rest['chest'].inverted())@rest['upper_arm_r'].translation+Vector((.045,0,0))
   for name in ['upper_arm_r','forearm_r']:
    rot=(rest[name].to_3x3()@Vector((0,1,0))).rotation_difference(direction)
    posed[name]=Matrix.Translation(shoulder)@rot.to_matrix().to_4x4()@rest[name].to_3x3().to_4x4()
    shoulder=posed[name]@Vector((0,r.data.bones[name].length,0))
   posed['hand_r']=Matrix.Translation(shoulder)@Euler((0,0,yaw)).to_matrix().to_4x4()@rest['hand_r'].to_3x3().to_4x4()
   for name in ['upper_arm_r','forearm_r','hand_r']:
    b=r.data.bones[name]; parent=b.parent.name
    r.pose.bones[name].matrix_basis=b.convert_local_to_pose(posed[name],rest[name],parent_matrix=posed[parent],parent_matrix_local=rest[parent],invert=True)
   bpy.context.view_layer.update()
   overlap=len(ht.overlap(tree(gun)))
   palm=posed['hand_r']@Vector((0,r.data.bones['hand_r'].length,0))
   results.append((overlap,y,z,yaw,list(palm)))
print('BEST_CANDIDATES',sorted(results,key=lambda a:(a[0],-a[4][2]))[:15])
