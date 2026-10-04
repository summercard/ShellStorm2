import bpy,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/rig_v006'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v006.blend'))
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];ctrl=bpy.data.objects['ExpressionController'];cam=s.camera;s.cycles.samples=20;s.render.resolution_x=1100;s.render.resolution_y=850;s.render.resolution_percentage=100
def render(name,loc,target,scale):
 rig.update_tag();ctrl.update_tag();bpy.context.view_layer.update();cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;s.render.filepath=str(P/(name+'.png'));bpy.ops.render.render(write_still=True)
render('overview',(4,11,5),(0,0,1.9),8.5)
render('rear_axle',(4,-10,4),(0,-.1,1.85),8.2)
rig.pose.bones['arm_02.L'].rotation_euler.z=.45;rig.pose.bones['arm_04.L'].rotation_euler.z=.45;rig.pose.bones['arm_03.R'].rotation_euler.x=.5
render('arms_bent',(3,11,5),(0,0,1.9),8.5)
for p in rig.pose.bones:p.rotation_euler=(0,0,0)
rig.pose.bones['monitor_spin'].rotation_euler.y=math.pi/2
render('independent_spin',(2,12,4),(0,0,1.9),8.5)
rig.pose.bones['monitor_spin'].rotation_euler.y=0
s.render.resolution_x=600;s.render.resolution_y=600;s.cycles.samples=12
for i,name in enumerate(['default','suspicious','angry','sleepy','taunting','glitched']):
 ctrl['expression_index']=i;render('expression_'+name,(0,12,2.6),(0,0,2.6),3.3)
