"""Model-only rest/binding correction. Never writes animation or runtime files."""
from pathlib import Path
import sys, json, hashlib, math
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector, Matrix
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
SOURCE = BASE/'v011/source/model/chr_bunny01_model_v011.blend'
TARGET = BASE/'v012/source/model/chr_bunny01_model_v012.blend'
OUT = ROOT/'outputs/character_pipeline/v012'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_character_bundle import signature

def snapshot():
    return {o.name: {'vertices':[tuple(v.co) for v in o.data.vertices],
        'matrix':[list(r) for r in o.matrix_world],
        'polygons':[tuple(p.vertices) for p in o.data.polygons],
        'uv':[[tuple(d.uv) for d in layer.data] for layer in o.data.uv_layers],
        'materials':[m.name if m else None for m in o.data.materials]}
        for o in bpy.context.scene.objects if o.type == 'MESH'}

assert not TARGET.exists(), 'Preserve existing artist version'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig = bpy.data.objects['RIG_bunny01']
if bpy.context.object and bpy.context.object.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
original = snapshot()
rig.animation_data_clear()
for p in rig.pose.bones: p.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = rig.data.edit_bones
def set_bone(name, head, tail):
    b=eb[name]; b.head=head; b.tail=tail
    b.align_roll(Vector((0,1,0)) if abs((b.tail-b.head).normalized().z)>.95 else Vector((0,0,1)))
set_bone('waist',(0,.000635,.16),(0,.000635,.245))
set_bone('chest',(0,.000635,.245),(0,.000635,.43))
for side, sign in [('l',-1),('r',1)]:
    wrist=eb['hand_'+side].head.copy()
    shoulder=Vector((sign*.17,.000635,.43))
    elbow=shoulder.lerp(wrist,.5)
    set_bone('upper_arm_'+side,shoulder,elbow)
    set_bone('forearm_'+side,elbow,wrist)
    ankle=eb['foot_'+side].head.copy(); ankle.z=0
    hip=ankle.copy(); hip.z=.16
    knee=hip.lerp(ankle,.5)
    set_bone('thigh_'+side,hip,knee)
    set_bone('shin_'+side,knee,ankle)
    set_bone('foot_'+side,ankle,ankle+Vector((0,.14,0)))
bpy.ops.object.mode_set(mode='OBJECT')
body=bpy.data.objects['SRC_Body']
body.vertex_groups.clear()
body.vertex_groups.new(name='chest').add(list(range(len(body.data.vertices))),1,'REPLACE')
body['bone_id']='chest'
rig.data.name='SKEL_bunny01_v004'
rig['skeleton_id']='SKEL-BUNNY01-004'
sig=signature(rig)
rig['skeleton_sha256']=sig
scene=bpy.context.scene
scene['skeleton_sha256']=sig
scene['production_status']='model_only_pending_animation'
scene['component_bone_mapping']=json.dumps({o.get('component_id',o.name):o['bone_id'] for o in scene.objects if o.type=='MESH' and 'bone_id' in o})
scene['rig_correction_note']='Shoulders centered; straight upper/lower arms; original wrist/hand alignment retained; grounded feet; body rigid to chest.'
bpy.context.view_layer.update()
assert snapshot()==original
TARGET.parent.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET))
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
rig=bpy.data.objects['RIG_bunny01']; body=bpy.data.objects['SRC_Body']
assert snapshot()==original
assert rig.animation_data is None
assert signature(rig)==sig
for side in ['l','r']:
    for a,b in [('upper_arm_','forearm_'),('thigh_','shin_')]:
        a,b=rig.data.bones[a+side],rig.data.bones[b+side]
        assert (a.tail_local-b.head_local).length<1e-6
        assert (a.tail_local-a.head_local).normalized().dot((b.tail_local-b.head_local).normalized())>.99999
    foot=rig.data.bones['foot_'+side]
    assert abs(foot.head_local.z)<1e-6 and abs(foot.tail_local.z)<1e-6
assert all(len(v.groups)==1 and v.groups[0].weight==1 and body.vertex_groups[v.groups[0].group].name=='chest' for v in body.data.vertices)
def evaluated(name):
    obj=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [obj.matrix_world@v.co for v in obj.data.vertices]
rest=evaluated('SRC_Body'); foot_rest=evaluated('SRC_Foot_L')
checks={}
for name in ['chest','waist']:
    p=rig.pose.bones[name]; p.rotation_mode='XYZ'; p.rotation_euler.x=math.radians(8)
    bpy.context.view_layer.update()
    displacement=max((a-b).length for a,b in zip(rest,evaluated('SRC_Body')))
    assert displacement>.005
    if name=='chest': assert max((a-b).length for a,b in zip(foot_rest,evaluated('SRC_Foot_L')))<1e-6
    checks[name+'_body_displacement_m']=displacement
    p.matrix_basis=Matrix.Identity(4); bpy.context.view_layer.update()
OUT.mkdir(parents=True,exist_ok=True)
report={'geometry_topology_uv_materials_transforms_unchanged':True,'straight_arm_leg_chains':True,
    'foot_bones_grounded':True,'body_rigid_chest_weight':True,'chest_does_not_move_feet':True,
    'pose_checks':checks,'skeleton_sha256':sig,'model_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),
    'bones':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None} for b in rig.data.bones}}
(OUT/'model_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger={'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':'v012','status':'model_only_pending_animation',
    'model_source':str(TARGET.relative_to(ROOT)),'model_sha256':report['model_sha256'],
    'skeleton_id':'SKEL-BUNNY01-004','skeleton_sha256':sig,'source_version':'v011',
    'animation_source':None,'exports':[],'runtime_active_version':'v011','model_checks':report,
    'next_step':'User-approved animation authoring with identical v012 rest skeleton; update body adapter mapping from waist to chest before export. Do not reuse v011 animation as matching skeleton.'}
(BASE/'v012/character_transfer_ledger_v012.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
# QA-only orthographic overlays: offset parallel to view, retaining exact screen projection.
scene=bpy.context.scene; scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'
scene.display.shading.show_cavity=True
scene.render.resolution_x=900; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
mat=bpy.data.materials.new('QA_bones'); mat.diffuse_color=(1,.22,.015,1)
for label,axis in [('front',Vector((0,1,0))),('side',Vector((1,0,0)))]:
    helpers=[]
    for b in rig.data.bones:
        p=b.head_local+axis*.65; q=b.tail_local+axis*.65
        bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.003,depth=(q-p).length,location=(p+q)/2)
        o=bpy.context.object; o.rotation_euler=(q-p).to_track_quat('Z','Y').to_euler(); o.data.materials.append(mat); helpers.append(o)
    data=bpy.data.cameras.new('QA'); cam=bpy.data.objects.new('QA',data); scene.collection.objects.link(cam)
    cam.location=Vector((0,0,.73))+axis*4; cam.rotation_euler=(-axis).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO'; data.ortho_scale=1.7; scene.camera=cam
    scene.render.filepath=str(OUT/('rig_'+label+'.png')); bpy.ops.render.render(write_still=True)
    for o in helpers+[cam]: bpy.data.objects.remove(o,do_unlink=True)
print('V012_MODEL_ONLY_VALIDATED',TARGET)
