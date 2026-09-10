import bpy
from mathutils.bvhtree import BVHTree
from pathlib import Path
root=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(root/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v014/source/animation/chr_bunny01_animation_v014.blend'))
def tree(obj,dg):
    e=obj.evaluated_get(dg); m=e.to_mesh()
    result=BVHTree.FromPolygons([e.matrix_world@v.co for v in m.vertices],[list(p.vertices) for p in m.polygons])
    e.to_mesh_clear(); return result
for title in ['05_单手持枪_小跑','06_单手持枪_待机循环']:
    s=bpy.data.scenes[title]; bpy.context.window.scene=s; s.frame_set(1)
    dg=bpy.context.evaluated_depsgraph_get()
    head=next(o for o in s.objects if o.type=='MESH' and o.get('component_id')=='head' and o.get('variant_id')!='chibi_anime')
    gun=next(o for o in s.objects if o.type=='MESH' and o.get('preview_only'))
    print('GUN_HEAD_OVERLAP',title,len(tree(head,dg).overlap(tree(gun,dg))))
