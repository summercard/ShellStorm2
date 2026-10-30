import bpy,json,random,math,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');ROOT=R;S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017'
# Reuse only pure geometry helpers and shared material references, not setup code.
ref=(R/'scripts/blender/refine_manor_components.py').read_text(encoding='utf-8');start=ref.index('code=(R/');end=ref.index('# Darken high contrast parquet')
exec(ref[start:end],globals())
p=S/'component_catalog.json';d=json.loads(p.read_text(encoding='utf-8'))
changed=['manor_wall_standard','manor_wall_door','manor_wall_window','manor_wall_grille','manor_wall_lamp','manor_plant_large','manor_plant_compact']
for e in d['components']:
 if e['slug'] not in changed:continue
 col=bpy.data.collections[e['collection']]
 for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
 g=build(e['slug']);e['bounds_size_m']=g.finish(col,e['slug'])
 for k in ['source_bounds_size_m','geometry_fingerprint','vertex_count']:e.pop(k,None)
print([(e['slug'],e['bounds_size_m']) for e in d['components'] if e['slug'] in changed])
p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
sc=bpy.data.scenes['复古公馆_组件实例参考_非正式关卡'];bpy.context.window_manager.windows[0].scene=sc;sc.camera=bpy.data.objects['参考顶视相机']
bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
sc.render.filepath=str(W/'manor_final.png');bpy.ops.render.render(write_still=True)
sc.camera=bpy.data.objects['会客前台近景'];sc.render.filepath=str(W/'manor_detail.png');bpy.ops.render.render(write_still=True)
sc.camera=bpy.data.objects['参考顶视相机']
bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
