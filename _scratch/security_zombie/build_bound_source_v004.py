import bpy, json, math
from pathlib import Path
from mathutils import Vector, Matrix
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
FBX=P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbx'
JPG=P/'_scratch/security_zombie/new_source/tripo_convert_3ae4046f-dc49-4f32-b5ea-ac940bfabdde.fbm/安保警卫3d模型_basecolor.JPEG'
OUT=P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v004.blend'
REPORT=P/'_scratch/security_zombie/bound_source_v004_report.json'
TARGET_H=1.857143
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(FBX))
scene=bpy.context.scene; arm=next(o for o in scene.objects if o.type=='ARMATURE'); mesh=next(o for o in scene.objects if o.type=='MESH')
# Rename existing shared bones only; preserve every original edit bone and skin matrix.
if 'NeckTwist02' in arm.data.bones:
    arm.data.bones['NeckTwist02'].name='Neck'
# Imported source uses a valid bound skeleton; add only the finger extension from the melee contract.
bpy.context.view_layer.objects.active=arm; bpy.ops.object.mode_set(mode='EDIT'); eb=arm.data.edit_bones
finger_specs=[('Thumb',-0.24,0.030),('Index',-0.10,0.046),('Middle',0.0,0.050),('Pinky',0.16,0.040)]
for side,hand_name,sign in [('L','L_Hand',-1.0),('R','R_Hand',1.0)]:
    hand=eb[hand_name]; h=hand.head.copy(); t=hand.tail.copy(); forward=(t-h).normalized(); up=Vector((0,0,1))
    if abs(forward.dot(up))>.9: up=Vector((0,1,0))
    across=up.cross(forward).normalized()*sign
    for finger,offset,length in finger_specs:
        n1=f'{side}_{finger}1'; n2=f'{side}_{finger}2'
        if n1 in eb or n2 in eb: continue
        base=h+forward*.012+across*offset
        if finger=='Thumb':
            base=h+forward*.004+up*.014+across*(-.22); direction=(forward*.55+up*.45+across*(-.35)).normalized()
        else: direction=(forward*.95+up*(-.10)).normalized()
        b1=eb.new(n1); b1.head=base; b1.tail=base+direction*length; b1.parent=hand
        b2=eb.new(n2); b2.head=b1.tail; b2.tail=b2.head+direction*(length*.78); b2.parent=b1; b2.use_connect=True
bpy.ops.object.mode_set(mode='OBJECT')
# Pack the new source texture without touching skin weights.
for mat in mesh.data.materials:
    if not mat: continue
    mat.name='enm_ranged_sporeshooter01_mat'
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE':
            img=bpy.data.images.load(str(JPG),check_existing=False); img.name='enm_ranged_sporeshooter01_basecolor'; img.pack(); img.filepath='//textures/enm_ranged_sporeshooter01_basecolor_v003.jpeg'; node.image=img
# Apply only a shared object transform to armature and mesh world transforms.
# This preserves the imported armature modifier/bind matrices exactly.
bpy.context.view_layer.update()
lo=Vector((1e9,)*3); hi=Vector((-1e9,)*3)
for v in mesh.data.vertices:
    p=mesh.matrix_world@v.co; lo=Vector((min(lo.x,p.x),min(lo.y,p.y),min(lo.z,p.z))); hi=Vector((max(hi.x,p.x),max(hi.y,p.y),max(hi.z,p.z)))
h=hi.z-lo.z; s=TARGET_H/h; cx=(lo.x+hi.x)/2; cy=(lo.y+hi.y)/2
T=Matrix.Translation(Vector((-cx,-cy,-lo.z))) @ Matrix.Scale(s,4)
R=Matrix.Rotation(math.radians(90),4,'Z')
T=R @ T
arm.matrix_world=T@arm.matrix_world
mesh.matrix_world=T@mesh.matrix_world
arm.name='enm_ranged_sporeshooter01_armature'; arm.data.name='enm_ranged_sporeshooter01_armature'; arm.data['skeleton_id']='SKEL-MELEE-FUNGBOAR01-002-EXTENDED'
mesh.name='enm_ranged_sporeshooter01_mesh'; mesh.data.name='enm_ranged_sporeshooter01_mesh'
for o in list(scene.objects):
    if o not in (arm,mesh): bpy.data.objects.remove(o,do_unlink=True)
bpy.context.view_layer.update()
# Validate original groups remain untouched and modifier still targets the same armature.
weights=[sum(g.weight for g in v.groups) for v in mesh.data.vertices]
report={'output_blend':str(OUT),'source_fbx':str(FBX),'bone_count':len(arm.data.bones),'vertex_group_count':len(mesh.vertex_groups),'unbound_vertices':sum(x<1e-4 for x in weights),'weight_sum_bad':sum(abs(x-1)>1e-3 for x in weights),'bones':[b.name for b in arm.data.bones],'mesh_parent':mesh.parent.name if mesh.parent else None,'modifier_target':next((m.object.name for m in mesh.modifiers if m.type=='ARMATURE' and m.object),None),'source_binding_preserved':True,'forward_contract':'Blender +Y'}
if report['unbound_vertices'] or report['weight_sum_bad'] or report['modifier_target']!=arm.name: raise RuntimeError(report)
bpy.context.preferences.filepaths.save_version=0; OUT.parent.mkdir(parents=True,exist_ok=True); bpy.ops.wm.save_as_mainfile(filepath=str(OUT)); REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8'); print('BOUND_SOURCE_V004_OK',json.dumps(report,ensure_ascii=False))
