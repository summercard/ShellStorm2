import bpy,json
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/source/enm_boss_monitor002_animation_v012.blend')
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;s.frame_set(1)
for o in s.objects:
 if o.type=='MESH' and ('face' in o.name.lower() or 'expression' in o.name.lower() or o.name=='Keyboard outer shell'):
  print('OBJ',o.name,dict(o.items()),'dims',list(o.dimensions),'matrix',list(map(list,o.matrix_world)),'groups',[g.name for g in o.vertex_groups])
  if o.name=='Keyboard outer shell':print('POLY',[(p.area,list(p.normal)) for p in sorted(o.data.polygons,key=lambda p:p.area,reverse=True)[:3]])
print('MATERIALS',[m.name for m in bpy.data.materials])
