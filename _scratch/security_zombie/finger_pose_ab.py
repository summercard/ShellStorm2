import bpy, math
from pathlib import Path
from mathutils import Vector, Quaternion
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM=P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
OUT=P/'assets/art/enemies/normal_enemy_3d/security_zombie/previews'
bpy.ops.wm.open_mainfile(filepath=str(ANIM));sc=bpy.context.scene;arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for o in bpy.data.objects:
    if o.type=='MESH' and o.name.startswith('wpn_security_short_shotgun_'): o.hide_render=False
for side,sgn in [('L',-1),('R',1)]:
    pass

def setrot(name,axis,deg):
    pb=arm.pose.bones.get(name)
    if pb: pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion(Vector(axis),math.radians(deg))

def pose(sign,ang_scale):
    for side in ('L','R'):
        for finger in ('Index','Middle','Ring','Pinky'):
            for i,base in enumerate((28,42,50,54),1): setrot(f'{side}_{finger}{i}',(1,0,0),sign*base*ang_scale)
        for i,base in enumerate((20,31,38,42),1): setrot(f'{side}_Thumb{i}',(0,0,1),-sign*base*ang_scale)
    bpy.context.view_layer.update()

def setup(name,loc,target):
    cd=bpy.data.cameras.new(name);c=bpy.data.objects.new(name,cd);sc.collection.objects.link(c);c.location=Vector(loc);c.rotation_euler=(Vector(target)-c.location).to_track_quat('-Z','Y').to_euler();cd.type='ORTHO';cd.ortho_scale=1.9;return c
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='TEXTURE';sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True;sc.render.resolution_x=700;sc.render.resolution_y=700;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
arm.animation_data.action=bpy.data.actions['armed_idle'];sc.frame_set(25);bpy.context.view_layer.update()
for label,sign,scale in [('curl_positive',1,0.75),('curl_negative',-1,0.75),('curl_positive_soft',1,0.45),('curl_negative_soft',-1,0.45)]:
    pose(sign,scale);cam=setup('cam_'+label,(2.8,0.75,1.05),(0,0.42,0.93));sc.camera=cam;sc.render.filepath=str(OUT/('finger_ab_'+label+'.png'));bpy.ops.render.render(write_still=True);bpy.data.objects.remove(cam,do_unlink=True)
print('FINGER_POSE_AB_OK')
