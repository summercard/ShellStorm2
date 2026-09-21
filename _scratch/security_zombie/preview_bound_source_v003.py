import bpy
from pathlib import Path
from mathutils import Vector
P=Path(r"I:\工作项目\shellstrom2\ShellStorm2"); src=P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v004.blend'; out=P/'_scratch/security_zombie/bound_source_v003_preview';out.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(src)); s=bpy.context.scene; mesh=next(o for o in s.objects if o.type=='MESH'); arm=next(o for o in s.objects if o.type=='ARMATURE'); arm.hide_render=True
for o in list(s.objects):
 if o.type in {'LIGHT','CAMERA'}: bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.object.light_add(type='AREA',location=(3,4,4)); l=bpy.context.object;l.data.energy=900;l.data.size=5;l.rotation_euler=(Vector((0,0,0.8))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='AREA',location=(-3,-2,2)); l=bpy.context.object;l.data.energy=500;l.data.size=4;l.rotation_euler=(Vector((0,0,.8))-l.location).to_track_quat('-Z','Y').to_euler()
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=600;s.render.resolution_y=800;s.render.resolution_percentage=100
for name,loc in [('plusY',(0,4,.9)),('minusY',(0,-4,.9)),('plusX',(4,0,.9))]:
 bpy.ops.object.camera_add(location=loc);cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=2.3;cam.rotation_euler=(Vector((0,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler();s.camera=cam;s.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True);bpy.data.objects.remove(cam,do_unlink=True)
# bone overlay front, using EditBone coordinates (the authoritative rest-pose data).
bpy.context.view_layer.objects.active=arm
bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones:
 if b.name=='Root': continue
 a=arm.matrix_world@b.head; z=arm.matrix_world@b.tail; a.y=0.9;z.y=0.9
 c=bpy.data.curves.new('audit_'+b.name,'CURVE');c.dimensions='3D';c.bevel_depth=.005;sp=c.splines.new('POLY');sp.points.add(1);sp.points[0].co=(*a,1);sp.points[1].co=(*z,1);o=bpy.data.objects.new(c.name,c);s.collection.objects.link(o);m=bpy.data.materials.get('bone_audit') or bpy.data.materials.new('bone_audit');m.diffuse_color=(0.05,1,.15,1);o.data.materials.append(m)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.camera_add(location=(0,4,.9));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=2.3;cam.rotation_euler=(Vector((0,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler();s.camera=cam;s.render.filepath=str(out/'rest_bone_overlay_plusY.png');bpy.ops.render.render(write_still=True)