import bpy,math
from mathutils import Matrix,Vector
import kawaii_jelly_interaction as j
OUT='/Users/summercards/ShellStorm2/output/kawaii_jelly_v002'
s=bpy.context.scene;s.name='Q弹果冻_重力与固定切面'
j._UPDATING=True
c=bpy.data.collections.get('00_固定切面基座')
if c is None:c=bpy.data.collections.new('00_固定切面基座');s.collection.children.link(c)
a=j.anchor(s)
if a is None:a=bpy.data.objects.new('固定切面基座_只响应朝向控件',None);c.objects.link(a)
a['jelly_anchor']=True;a.empty_display_type='CIRCLE';a.empty_display_size=1.0;a.location=(0,0,2.2);a.rotation_euler=(0,0,0)
a.lock_location=(True,True,True);a.lock_rotation=(True,True,True);a.lock_scale=(True,True,True)
for o in list(s.objects):
 if o.get('jelly_deform') or o.name=='薄荷色小托盘':
  o.parent=a;o.matrix_parent_inverse=Matrix.Identity(4);o.lock_location=(True,True,True);o.lock_rotation=(True,True,True);o.lock_scale=(True,True,True)
s.jelly_k=30;s.jelly_damp=2.2;s.jelly_g=1;s.jelly_gravity=True;s.jelly_running=True;s.jelly_continuous_shake=False;s.jelly_shake_strength=1;s.jelly_tilt=90
s.use_gravity=True;s.gravity=(0,0,-9.81);a.rotation_euler.y=math.pi/2
s.render.engine='BLENDER_EEVEE_NEXT'
cam=s.camera;cam.location=(4.3,-7,4.5);cam.rotation_euler=(Vector((.12,0,2.05))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.3
bpy.context.view_layer.update();j._UPDATING=False;j._STATE=None;j.settle(s)
for ar in bpy.context.screen.areas:
 if ar.type=='VIEW_3D':
  ar.spaces.active.shading.type='SOLID';ar.spaces.active.shading.color_type='MATERIAL';ar.spaces.active.overlay.show_overlays=False;ar.spaces.active.show_region_ui=True;ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.region_3d.view_camera_zoom=16
  for r in ar.regions:
   if r.type=='UI':
    try:r.active_panel_category='Q弹果冻'
    except AttributeError:pass
s['功能说明']='固定切面 + 世界重力 + 软硬预设 + 连续硬度/阻尼/重力/摇晃参数 + 抓拉快甩 + 余晃'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/Q弹果冻_重力交互_v002.blend')
def start():
 if not (hasattr(bpy.types,'blendermcp_server') and bpy.types.blendermcp_server and bpy.types.blendermcp_server.running):bpy.ops.blendermcp.start_server()
 j.wake(s)
 return None
bpy.app.timers.register(start,first_interval=1.0)
print('V002 ready',j.equilibrium(s).tolist())
