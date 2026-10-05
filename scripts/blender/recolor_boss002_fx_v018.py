import bpy,json
from pathlib import Path
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v018';P.mkdir(exist_ok=True)
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v017.blend'))
 for sc in bpy.data.scenes:sc['asset_version']='v018'
 if kind=='animation':
  fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW']
  for i,ob in enumerate(sorted((o for o in fx.objects if o.get('vfx_role')=='rotation_only'),key=lambda o:o.name)):
   mat=ob.data.materials[0].copy();mat.name='PREVIEW_Rotor_Saturated_'+('Red' if i%2 else 'Blue')+'_%02d'%i;ob.data.materials[0]=mat
   em=next(n for n in mat.node_tree.nodes if n.type=='EMISSION');em.inputs[0].default_value=(.8,0,0,1) if i%2 else (0,.005,.8,1);em.inputs[1].default_value=.8
  # Remap only colored ink; keep white highlights, dark outlines, and original alpha.
  mats={m for ob in fx.objects if not ob.get('vfx_role') for m in ob.data.materials if m}
  for mat in mats:
   ns=mat.node_tree.nodes;ls=mat.node_tree.links;tex=next((n for n in ns if n.type=='TEX_IMAGE'),None);em=next((n for n in ns if n.type=='EMISSION'),None)
   if tex is None or em is None:continue
   sep=ns.new('ShaderNodeSeparateColor');ls.new(tex.outputs['Color'],sep.inputs[0])
   def mathnode(op,a,b):
    n=ns.new('ShaderNodeMath');n.operation=op
    for idx,x in enumerate([a,b]):
     if isinstance(x,(float,int)):n.inputs[idx].default_value=x
     else:ls.new(x,n.inputs[idx])
    return n.outputs[0]
   high=mathnode('MAXIMUM',mathnode('MAXIMUM',sep.outputs[0],sep.outputs[1]),sep.outputs[2]);low=mathnode('MINIMUM',mathnode('MINIMUM',sep.outputs[0],sep.outputs[1]),sep.outputs[2]);colored=mathnode('GREATER_THAN',mathnode('SUBTRACT',high,low),.14)
   isred=mathnode('GREATER_THAN',sep.outputs[0],mathnode('MULTIPLY',sep.outputs[2],.7))
   palette=ns.new('ShaderNodeMixRGB');ls.new(isred,palette.inputs[0]);palette.inputs[1].default_value=(0,.005,.8,1);palette.inputs[2].default_value=(.8,0,0,1)
   mix=ns.new('ShaderNodeMixRGB');ls.new(colored,mix.inputs[0]);ls.new(tex.outputs['Color'],mix.inputs[1]);ls.new(palette.outputs[0],mix.inputs[2]);ls.new(mix.outputs[0],em.inputs[0]);em.inputs[1].default_value=.8
  fx['palette']='saturated red and blue; reduced emission to avoid pale highlights'
 bpy.ops.wm.save_as_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v018.blend'))
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;s.cycles.samples=8;s.render.resolution_x=960;s.render.resolution_y=800
for f in [29,69]:s.frame_set(f);s.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
