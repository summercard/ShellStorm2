import bpy,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v016'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v016.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];rig=bpy.data.objects['Boss002_Rig']
source=(R/'scripts/blender/boss002_impact_preview_v014.py').read_text(encoding='utf-8')
source=source[:source.index('# White ink')].replace("'Keyboard outer shell'","'Portrait display'").replace('center_at(33)','center_at(65)').replace("fx['impact_frame']=33","fx['impact_frame']=65").replace('key(ob,55,loc,0)','key(ob,97,loc,0)').replace('(55,True)','(97,True)')
exec(source)
fx['style']='heavy slam: broad ink shockwave + cyan/magenta sparks; screen-only spin trails'
envelope(sprite('Heavy ground shock ring',1,True),65,69,80,origin,7.8)
envelope(sprite('Heavy outer echo ring',1,True),68,73,82,origin+Vector((0,0,.012)),9.0)
for i,(x,y,size) in enumerate([(-1.8,.1,2.7),(1.8,.2,3.2),(-.8,1,2.1),(.9,-.8,2.0)]):
 envelope(sprite('Heavy ink impact %d'%i,0),65+i%2,67+i%2,72+i,origin+Vector((x,y,.75)),size)
for i in range(8):
 a=math.tau*i/8;d=Vector((math.cos(a),math.sin(a),0));ob=sprite('Heavy cyber radial %02d'%i,2 if i%2==0 else 3)
 envelope(ob,65+i%3,68+i%3,76+i%3,origin+d*2.6+Vector((0,0,.5+(i%3)*.15)),1.5+(i%2)*.4)
# Thin hand drawn rotating swooshes sit behind the screen, never spin the body.
for j in range(3):
 ob=sprite('Screen spin ink trail %d'%j,2 if j%2==0 else 3)
 ob.rotation_mode='XYZ';ob.rotation_euler=(math.pi/2,0,0)
 for f in range(1,98):
  studio.frame_set(f);axle=rig.pose.bones['rear_axle'].matrix.translation.copy();ob.location=axle+Vector((0,-.20,.15))
  active=20<=f<=49;ob.scale=((3.6+j*.35),)*3 if active else (0,0,0)
  ob.rotation_euler=(math.pi/2,0,(f-19)*.5+j*math.tau/3)
  for prop in ['location','rotation_euler','scale']:ob.keyframe_insert(prop,frame=f)
  ob.hide_render=not active;ob.keyframe_insert('hide_render',frame=f)
 for fc in ob.animation_data.action.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if fc.data_path in ['hide_render','scale'] else 'LINEAR'
studio.camera.location=(5,12,6);studio.camera.rotation_euler=(Vector((0,1,1.5))-studio.camera.location).to_track_quat('-Z','Y').to_euler();studio.camera.data.ortho_scale=11.5
studio.frame_set(1);studio['preview_instructions']='heavy_spin_slam 1-97: screen spins 3 turns, hold49-55, impact65, low65-81, recover97. VFX only in studio.'
bpy.context.window.scene=studio;bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v016.blend'))
studio.cycles.samples=8;studio.render.resolution_x=960;studio.render.resolution_y=800
for f in [29,49,55,65,69,73,81,97]:
 studio.frame_set(f);studio.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
