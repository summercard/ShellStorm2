import bpy,json,math
from pathlib import Path
from mathutils import Vector
P=Path('I:/工作项目/shellstrom2/ShellStorm2'); path=P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v002.blend'
bpy.ops.wm.open_mainfile(filepath=str(path));s=bpy.context.scene;arm=next(o for o in s.objects if o.type=='ARMATURE');mesh=next(o for o in s.objects if o.type=='MESH')
# put rest pose and armature display
arm.data.pose_position='REST';arm.show_in_front=True;arm.data.display_type='OCTAHEDRAL';arm.hide_viewport=False;arm.hide_render=False
for o in s.objects:
 if o not in [arm,mesh]: o.hide_render=True;o.hide_viewport=True
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=600;s.render.resolution_y=800;s.render.resolution_percentage=100
# clear lights/cameras and add simple lighting
for o in list(s.objects):
 if o.type in {'LIGHT','CAMERA'}:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.object.light_add(type='AREA',location=(3,3,4));l=bpy.context.object;l.data.energy=800;l.data.size=5;l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='AREA',location=(-3,-2,2));l=bpy.context.object;l.data.energy=500;l.data.size=4;l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
out=P/'_scratch/security_zombie/diagnostic';out.mkdir(exist_ok=True)
for name,loc,target in [('plusY',(0,4,1.0),(0,0,0.9)),('minusY',(0,-4,1.0),(0,0,0.9)),('plusX',(4,0,1.0),(0,0,0.9)),('minusX',(-4,0,1.0),(0,0,0.9))]:
 bpy.ops.object.camera_add(location=loc);cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=2.5;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();s.camera=cam;s.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True);bpy.data.objects.remove(cam,do_unlink=True)
# Render rest-bone overlay for anatomical alignment; viewport bones are not rendered.
for b in arm.data.bones:
 if b.name == 'Root': continue
 a=arm.matrix_world@b.head_local; z=arm.matrix_world@b.tail_local
 a.y=0.8;z.y=0.8
 curve=bpy.data.curves.new('audit_'+b.name,'CURVE');curve.dimensions='3D';curve.bevel_depth=.006
 spline=curve.splines.new('POLY');spline.points.add(1)
 spline.points[0].co=(*a,1);spline.points[1].co=(*z,1)
 ob=bpy.data.objects.new(curve.name,curve);s.collection.objects.link(ob)
 mat=bpy.data.materials.get('audit_bone') or bpy.data.materials.new('audit_bone');mat.diffuse_color=(0.05,1,.15,1);ob.data.materials.append(mat)
bpy.ops.object.camera_add(location=(0,4,1));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=2.5;cam.rotation_euler=(Vector((0,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler();s.camera=cam;s.render.filepath=str(out/'rest_bone_overlay.png');bpy.ops.render.render(write_still=True)
# diagnostics
lo=Vector((1e9,)*3);hi=Vector((-1e9,)*3)
for v in mesh.data.vertices:
 w=mesh.matrix_world@v.co;lo=Vector((min(lo.x,w.x),min(lo.y,w.y),min(lo.z,w.z)));hi=Vector((max(hi.x,w.x),max(hi.y,w.y),max(hi.z,w.z)))
rows=[]
for n in ['Root','Hip','Spine02','Neck','Head','L_Clavicle','L_Upperarm','L_Forearm','L_Hand','R_Clavicle','R_Upperarm','R_Forearm','R_Hand']:
 b=arm.data.bones[n];rows.append({'name':n,'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None})
(P/'_scratch/security_zombie/diagnostic.json').write_text(json.dumps({'mesh_min':list(lo),'mesh_max':list(hi),'armature_matrix':[list(r) for r in arm.matrix_world],'bones':rows},indent=2))
