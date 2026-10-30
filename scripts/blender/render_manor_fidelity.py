import bpy,json,sys,importlib.util
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');W=R.parent/'ShellStorm2-work/manor_v017'
mode='after' if '/export/' in bpy.data.filepath.replace('\\','/') else 'before'
sc=bpy.data.scenes['复古公馆_组件实例参考_非正式关卡'];bpy.context.window.scene=sc
sc.render.resolution_x=720;sc.render.resolution_y=640;sc.cycles.samples=12;sc.render.resolution_percentage=100
cam=bpy.data.objects['参考顶视相机'];sc.camera=cam;cam.data.ortho_scale=32
for key,p in [('game',(0,-8,38)),('front',(0,-32,22)),('back',(0,32,22)),('side',(32,0,22))]:
 cam.location=p;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(W/(mode+'_'+key+'.png'));bpy.ops.render.render(write_still=True)
if mode=='before':
 gallery=bpy.data.scenes['组件母版画廊_独立可编辑'];bpy.context.window.scene=gallery
 spec=importlib.util.spec_from_file_location('prop_validator','C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 sys.argv=['validate','--','--all-meshes','--shared-palette',str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(W/'master_validation.json')]
 try:m.main()
 except SystemExit as e:print('MASTER_VALIDATION_EXIT',e.code)
print('FIDELITY_RENDERED',mode)
