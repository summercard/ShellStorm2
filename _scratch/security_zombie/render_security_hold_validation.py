import bpy, math, json
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM=P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
OUT=P/'assets/art/enemies/normal_enemy_3d/security_zombie/previews'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ANIM));sc=bpy.context.scene
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for o in bpy.data.objects:
    if o.type=='MESH' and o.name.startswith('wpn_security_short_shotgun_'):
        o.hide_render=False
for n in ('GripSocket','SupportHandSocket','MuzzleSocket'):
    o=bpy.data.objects.get(n)
    if o: o.hide_viewport=False; o.hide_render=True
# visual grip markers, only in previews
for name,loc,col in [('VISUAL_GripMarker',(0.16,0.33,0.87),(0.1,0.85,0.2)),('VISUAL_SupportMarker',(0.16,0.57,0.91),(0.95,0.55,0.05))]:
    old=bpy.data.objects.get(name)
    if old: bpy.data.objects.remove(old,do_unlink=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.035, location=loc)
    o=bpy.context.object;o.name=name
    m=bpy.data.materials.new(name+'_mat');m.diffuse_color=(*col,1);o.data.materials.append(m)

def cam(name,loc,target):
    cd=bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    c=bpy.data.objects.get(name) or bpy.data.objects.new(name,cd)
    if c.name not in sc.objects:sc.collection.objects.link(c)
    c.location=Vector(loc);c.rotation_euler=(Vector(target)-c.location).to_track_quat('-Z','Y').to_euler();c.data.type='ORTHO';c.data.ortho_scale=2.15;return c
views={
 'side_r':((2.8,0.75,1.05),(0,0.42,0.93)),
 'side_l':((-2.8,0.75,1.05),(0,0.42,0.93)),
 'threeq_r':((2.5,2.0,1.15),(0,0.38,0.95)),
 'top_hold':((1.9,1.7,2.8),(0,0.4,0.9)),
}
sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.light='STUDIO';sc.display.shading.color_type='TEXTURE';sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True
sc.render.resolution_x=700;sc.render.resolution_y=700;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
made=[]
for clip,frame in [('armed_idle',25),('attack',10)]: 
    a=bpy.data.actions[clip];arm.animation_data_create();arm.animation_data.action=a;sc.frame_set(frame);bpy.context.view_layer.update()
    for vn,(loc,target) in views.items():
        c=cam('validation_'+vn,loc,target);sc.camera=c
        path=OUT/('security_zombie_%s_%s.png'%(clip,vn));sc.render.filepath=str(path);bpy.ops.render.render(write_still=True);made.append(str(path))
# compute mount errors from actual gun root orientation and authored socket locals
root=bpy.data.objects['WeaponRoot']; grip=bpy.data.objects['GripSocket'].matrix_world.translation.copy()
# v002 SupportHandSocket is parented under the animated pump. Read its actual
# evaluated world transform; do not reconstruct it from the old v001 offset.
support=bpy.data.objects['SupportHandSocket'].matrix_world.translation.copy()
errors={}
for n,goal in [('GripSocket',grip),('SupportHandSocket',support)]:
    bone='L_Hand' if n=='GripSocket' else 'R_Hand';pb=arm.pose.bones[bone]
    tail=arm.matrix_world@pb.tail;errors[n]={'bone':bone,'bone_tail':list(tail),'socket':list(goal),'err_m':(tail-goal).length}
report={'previews':made,'mount_errors_m':errors,'camera_policy':'side and three-quarter views expose barrel length; colored markers are preview-only'}
(P/'_scratch/security_zombie/security_hold_validation_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SECURITY_HOLD_VALIDATION_OK',json.dumps(report,ensure_ascii=False))
