import bpy,json
from pathlib import Path
from mathutils import Matrix
s=bpy.data.scenes['BOSS002_STUDIO'];s.frame_set(192)
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
dg=bpy.context.evaluated_depsgraph_get();meshes={}
for name in ['Portrait display','Sculpted glove L','Sculpted glove R','Keyboard outer shell','Long data cable whip']:
 o=bpy.data.objects[name].evaluated_get(dg);me=o.to_mesh();pts=[C@o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear()
 meshes[name]=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
p=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/source_mesh_bounds.json');d=json.loads(p.read_text());d['activate']['191']=meshes;p.write_text(json.dumps(d));print('BOUNDS_191_OK')
