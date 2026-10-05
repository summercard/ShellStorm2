import bpy,math,json,hashlib,shutil
from pathlib import Path
from mathutils import Vector
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v022';P.mkdir(exist_ok=True);F=P/'frames';F.mkdir(exist_ok=True)
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v020.blend'))
 for sc in bpy.data.scenes:sc['asset_version']='v022'
 if kind=='animation':
  s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW'];s.frame_set(65);origin=next(o.location.copy() for o in fx.objects if o.name.startswith('Ground pulse 0 sector'));origin.z=.065
  mat=bpy.data.materials.new('CYBER_Impact_OneFrame_Yellow');mat.use_nodes=True;n=mat.node_tree.nodes;n.clear();e=n.new('ShaderNodeEmission');e.inputs[0].default_value=(1,.68,.015,1);e.inputs[1].default_value=1.6;o=n.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(e.outputs[0],o.inputs[0])
  verts=[];faces=[];count=32
  for i in range(count):
   a=math.tau*i/count;r=(3.25+.45*math.sin(i*2.7)) if i%2==0 else (2.15+.18*math.cos(i*1.7))
   for rad in [1.05+.14*math.sin(i*1.2),r]:verts.append((math.cos(a)*rad,math.sin(a)*rad,0))
  for i in range(count):faces.append((2*i,2*i+1,(2*i+3)%(2*count),(2*i+2)%(2*count)))
  me=bpy.data.meshes.new('Impact jagged radial plate');me.from_pydata(verts,[],faces);me.materials.append(mat);burst=bpy.data.objects.new('Impact flash F065 ONLY',me);fx.objects.link(burst);burst.location=origin;burst.visible_shadow=False;burst['preview_only']=True;burst['export']=False
  light=bpy.data.lights.new('Impact flash bounce','POINT');light.color=(1,.68,.035);light.shadow_soft_size=2;lo=bpy.data.objects.new('Impact flash bounce F065',light);fx.objects.link(lo);lo.location=origin+Vector((0,0,.6));lo['preview_only']=True;lo['export']=False
  for f in [1,64,65,66,97]:
   burst.hide_render=f!=65;burst.keyframe_insert('hide_render',frame=f);burst.scale=(1,1,1) if f==65 else (0,0,0);burst.keyframe_insert('scale',frame=f);light.energy=450 if f==65 else 0;light.keyframe_insert('energy',frame=f)
  for a in [burst.animation_data.action,light.animation_data.action]:
   for fc in a.fcurves:
    for k in fc.keyframe_points:k.interpolation='CONSTANT'
  s.frame_set(1)
 bpy.ops.wm.save_as_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v022.blend'))
a=[]
for f in range(1,98):
 s.frame_set(f)
 if not burst.hide_render:a.append(f)
assert a==[65]
(P/'style_audit.json').write_text(json.dumps({'highlight_frames':a,'highlight_duration_seconds':1/30,'unoutlined_yellow_jagged_ground_burst':True,'base_animation':'v020 unchanged','first_last_light_zero':True},indent=2))
for p in (B/'previews/heavy_v020/frames').glob('*.png'):shutil.copy2(p,F/p.name)
s.frame_set(65);s.cycles.samples=12;s.render.resolution_x=960;s.render.resolution_y=800;s.render.filepath=str(P/'pose_065.png');bpy.ops.render.render(write_still=True)
s.render.resolution_x=800;s.render.resolution_y=660;s.render.filepath=str(F/'0064.png');bpy.ops.render.render(write_still=True)
