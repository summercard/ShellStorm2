import bpy,json
from pathlib import Path
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v029.blend'));im=bpy.data.images.load(str(B/'source/textures_v030/expressions_atlas.png'));im.name='BOSS002_Expressions_v030';im.pack()
for mat in bpy.data.materials:
 if mat.use_nodes:
  for node in mat.node_tree.nodes:
   if node.type=='TEX_IMAGE' and node.image and node.image.name=='expressions_atlas.png':node.image=im
for s in bpy.data.scenes:s['asset_version']='v030'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v030.blend'))
m=json.loads((B/'source/rig_contract_v029.json').read_text());m['version']='v030';m['expression_states']['hurt_x_eye']=4;m['expression_states']['seated_double_spiral']=5;m['expression_atlas']='source/textures_v030/expressions_atlas.png';m['verification']='previews/expressions_v030/audit.json';(B/'source/rig_contract_v030.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v030.blend'));s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig'];s.cycles.samples=24;s.render.resolution_x=960;s.render.resolution_y=800;report={}
for name,f,expected in [('hurt',5,4),('stun_enter',4,4),('stun_enter',35,5),('stun_loop',25,5),('stun_exit',25,0)]:
 r.animation_data.action=bpy.data.actions[name];s.frame_set(f);report[name+'_'+str(f)]={'expression':r['expression_state'],'passed':round(r['expression_state'])==expected};s.render.filepath=str(B/'previews/expressions_v030'/(name+'_'+str(f)+'.png'));bpy.ops.render.render(write_still=True)
report['passed']=all(v['passed'] for v in report.values());(B/'previews/expressions_v030/audit.json').write_text(json.dumps(report,indent=2));print(report)
