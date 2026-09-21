import bpy
from pathlib import Path
from mathutils import Vector
P=Path(r"I:\工作项目\shellstrom2\ShellStorm2"); fbx=P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx'; out=P/'_scratch/security_zombie/new_binding_preview';out.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=str(fbx)); s=bpy.context.scene; mesh=next(o for o in s.objects if o.type=='MESH'); arm=next(o for o in s.objects if o.type=='ARMATURE'); arm.hide_render=True
for o in list(s.objects):
 if o.type in {'LIGHT','CAMERA'}: bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.object.light_add(type='AREA',location=(3,4,3)); l=bpy.context.object;l.data.energy=900;l.data.size=5;l.rotation_euler=(Vector((0,0,.5))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='AREA',location=(-3,-2,2)); l=bpy.context.object;l.data.energy=500;l.data.size=4;l.rotation_euler=(Vector((0,0,.5))-l.location).to_track_quat('-Z','Y').to_euler()
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=600;s.render.resolution_y=800;s.render.resolution_percentage=100
for name,loc in [('plusY',(0,4,.5)),('minusY',(0,-4,.5)),('plusX',(4,0,.5))]:
 bpy.ops.object.camera_add(location=loc);cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=1.5;cam.rotation_euler=(Vector((0,0,.5))-cam.location).to_track_quat('-Z','Y').to_euler();s.camera=cam;s.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True);bpy.data.objects.remove(cam,do_unlink=True)