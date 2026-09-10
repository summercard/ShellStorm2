"""Source-level rest rig, geometry preservation, rigid animation and rendered QA."""
from pathlib import Path
import json, math, sys, hashlib
import bpy
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
OUT=ROOT/'outputs/character_pipeline/v011'
OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature

def meshes():
    return {o.name:[tuple(v.co) for v in o.data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}

def open_file(p):
    bpy.ops.wm.open_mainfile(filepath=str(p))
    if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    return next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')

def render(name,camera_position, bones=False):
    if '--no-render' in sys.argv: return
    if name.startswith('rest_') and (OUT/(name+'.png')).exists(): return
    scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO'
    scene.display.shading.color_type='MATERIAL'
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.background_type='WORLD'
    if scene.world is None: scene.world=bpy.data.worlds.new('QA_world')
    scene.world.color=(.08,.08,.08)
    scene.render.resolution_x=800
    scene.render.resolution_y=900
    scene.render.resolution_percentage=100
    cam_data=bpy.data.cameras.new('QA_camera')
    cam=bpy.data.objects.new('QA_camera',cam_data)
    scene.collection.objects.link(cam)
    cam.location=camera_position
    cam.rotation_euler=(Vector((0,0,.75))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO'
    cam_data.ortho_scale=1.85
    scene.camera=cam
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)

rig=open_file(BASE/'v009/source/model/chr_bunny01_model_v009.blend')
original=meshes()
rig=open_file(BASE/'v011/source/model/chr_bunny01_model_v011.blend')
assert meshes()==original,'Geometry changed'
sig=signature(rig)
bones=rig.data.bones
for side in ['l','r']:
    for chain in [('upper_arm_','forearm_','hand_'),('thigh_','shin_')]:
        previous=None
        for prefix in chain:
            b=bones[prefix+side]
            direction=(b.tail_local-b.head_local).normalized()
            if previous:
                assert previous[0].dot(direction)>.9999, 'Bent rest chain '+prefix+side
                assert (previous[1]-b.head_local).length<1e-5, 'Disconnected rest chain'
            previous=(direction,b.tail_local)
    assert bones['foot_'+side].tail_local.y>bones['foot_'+side].head_local.y,'Foot backward'
    assert bones['ear_'+side].tail_local.z>bones['ear_'+side].head_local.z+.3,'Ear backward'
assert (bones['waist'].tail_local-bones['chest'].head_local).length<1e-5
assert bones['chest'].tail_local.z<.479,'Chest outside torso'
assert (Matrix(((1,0,0),(0,0,1),(0,-1,0)))@Vector((0,1,0))-Vector((0,0,-1))).length<1e-6
render('rest_front_positive_y',(0,4,.85))
render('rest_back_negative_y',(0,-4,.85))
render('rest_three_quarter',(3,5,2))
# Render bones in front of the body without modifying authoring files.
mat=bpy.data.materials.new('QA_bone_orange')
mat.diffuse_color=(1,.35,.025,1)
for b in bones:
    if b.name=='root': continue
    p=b.head_local.copy(); q=b.tail_local.copy()
    p.y+=.5; q.y+=.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.004,depth=(q-p).length,location=(p+q)/2)
    obj=bpy.context.object
    obj.rotation_euler=(q-p).to_track_quat('Z','Y').to_euler()
    obj.data.materials.append(mat)
render('rest_bone_overlay',(0,4,.85))
rig=open_file(BASE/'v011/source/animation/chr_bunny01_animation_v011.blend')
assert signature(rig)==sig,'Model/animation rest mismatch'
report={'geometry_unchanged':True,'rest_chains_straight':True,'forward':'Blender +Y -> Godot -Z','skeleton_sha256':sig,'clips':{}}
for role in ['model','animation']:
    report[role+'_sha256']=hashlib.sha256((BASE/f'v011/source/{role}/chr_bunny01_{role}_v011.blend').read_bytes()).hexdigest()
for action in bpy.data.actions:
    if 'state_id' not in action: continue
    rig.animation_data.action=action
    start,end=map(int,action.frame_range)
    maximum=0.0
    first=None
    for f in range(start,end+1):
        bpy.context.scene.frame_set(f)
        for bone in rig.pose.bones:
            scale=bone.matrix.to_scale()
            maximum=max(maximum,max(abs(x-1) for x in scale))
            assert max(abs(x-1) for x in scale)<.0001,'Nonrigid bone '+bone.name
            assert abs(bone.matrix.to_3x3().determinant()-1)<.0001,'Shear/reflection '+bone.name
        poses={b.name:b.matrix.copy() for b in rig.pose.bones}
        if f==start: first=poses
        if f==end:
            for name,m in poses.items():
                assert max(abs(m[i][j]-first[name][i][j]) for i in range(4) for j in range(4))<.0001,'Loop seam '+name
    report['clips'][action['state_id']]={'frames':end-start+1,'maximum_scale_error':maximum,'loop_seam_passed':True}
    bpy.context.scene.frame_set(13 if 'moving' in action['state_id'] else 1)
    render(action['state_id'],(3,5,2))
(OUT/'source_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('V011_SOURCE_VALIDATION_OK',json.dumps(report))
