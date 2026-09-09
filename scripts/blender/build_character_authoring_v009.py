"""One-time migration: v008 -> separate model/action masters sharing an armature.

Run with Blender --background --python this_file. Never used to export edited masters.
"""
from pathlib import Path
import json
import hashlib
import bpy
from mathutils import Matrix, Vector, Quaternion

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01'
PACKAGE = BASE / 'production/v009'
C = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
PARENTS = {'root':None,'body':'root','head':'root','hand_l':'root','hand_r':'root','feet':'root','foot_l':'feet','foot_r':'feet','ear_l':'head','ear_r':'head'}
PARTS = {
 'body': ('身体','bunny_white',['SRC_Body']),
 'head': ('头部','bunny_white',['SRC_Head']),
 'hand_l': ('左手','bunny_white',['SRC_Hand_Main_L','SRC_Hand_Cuff_L']),
 'hand_r': ('右手','bunny_white',['SRC_Hand_Main_R','SRC_Hand_Cuff_R']),
 'foot_l': ('左脚','bunny_white',['SRC_Foot_L']),
 'foot_r': ('右脚','bunny_white',['SRC_Foot_R']),
 'ear_l': ('帽子','bunny_ears_l',['SRC_Ear_L_Mirror']),
 'ear_r': ('帽子','bunny_ears_r',['SRC_Ear_R']),
}

def matrix(value):
    q = value['q']
    return Matrix.LocRotScale(Vector(value['p']), Quaternion((q[3],q[0],q[1],q[2])), Vector(value['s']))

def collection(name, parent):
    result = bpy.data.collections.new(name)
    parent.children.link(result)
    return result

def main():
    model_path = PACKAGE / 'source/model/chr_bunny01_model_v009.blend'
    animation_path = PACKAGE / 'source/animation/chr_bunny01_animation_v009.blend'
    if model_path.exists() or animation_path.exists():
        raise RuntimeError('Version exists; increment version, do not overwrite edited masters')
    capture = json.loads((ROOT/'outputs/character_pipeline/legacy_motion_capture.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(BASE/'source/chr_player_capsule01_bunny01_top3d_v008.blend'))
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    source_meshes = {name: bpy.data.objects[name] for _,_,names in PARTS.values() for name in names}
    source_meshes['制作组件_二次元头部_已对齐'] = bpy.data.objects['制作组件_二次元头部_已对齐']
    keep = set(source_meshes.values())
    worlds = {o:o.matrix_world.copy() for o in keep}
    for obj in list(bpy.data.objects):
        if obj not in keep: bpy.data.objects.remove(obj, do_unlink=True)
    for obj in keep:
        obj.parent = None
        obj.matrix_world = worlds[obj]
    for child in list(scene.collection.children): scene.collection.children.unlink(child)
    rig_collection = collection('00_共享骨架', scene.collection)
    parts_collection = collection('01_部件', scene.collection)
    collection('90_预览环境_不导出', scene.collection)
    data = bpy.data.armatures.new('SKEL_bunny01_v001')
    rig = bpy.data.objects.new('RIG_bunny01', data)
    rig_collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    rest_world = {}
    for name, parent in PARENTS.items():
        local = C @ matrix(capture['rest'][name]) @ C.inverted()
        rest_world[name] = rest_world[parent] @ local if parent else local
        bone = data.edit_bones.new(name)
        bone.head = rest_world[name].translation
        bone.tail = bone.head + Vector((0,0.08,0))
        if parent: bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    signature = [{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in data.bones]
    skeleton_hash = hashlib.sha256(json.dumps(signature,sort_keys=True).encode()).hexdigest()
    rig['skeleton_id'] = 'SKEL-BUNNY01-001'
    rig['skeleton_sha256'] = skeleton_hash
    part_collections = {}
    for bone, (slot,variant,names) in PARTS.items():
        if slot not in part_collections: part_collections[slot] = collection(slot,parts_collection)
        variant_collection = collection(slot+'__'+variant,part_collections[slot])
        variant_collection['slot_id'] = bone
        variant_collection['variant_id'] = variant
        for name in names:
            bind(source_meshes[name],rig,bone,variant_collection)
    head_variant = collection('头部__chibi_anime',part_collections['头部'])
    head_variant['slot_id']='head'
    head_variant['variant_id']='chibi_anime'
    bind(source_meshes['制作组件_二次元头部_已对齐'],rig,'head',head_variant)
    head_variant.hide_render = True
    head_variant.hide_viewport = True
    for slot in ['眼镜','下身配件']:
        branch=collection(slot,parts_collection)
        collection(slot+'__none',branch)
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1
    scene['skeleton_sha256']=skeleton_hash
    scene['asset_id']='CHR-PLY-CAPSULE01-3D-BUNNY01'
    scene['authoring_height_m']=1.5
    scene['runtime_scale']=0.7
    scene['workflow']='model_and_animation_shared_rig_v1'
    scene['file_role']='model'
    for image in bpy.data.images:
        if image.source == 'FILE' and image.has_data: image.pack()
    model_path.parent.mkdir(parents=True,exist_ok=True)
    animation_path.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(model_path))
    # Use linked model meshes/materials/armature data; only pose Actions live in this file.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(model_path),link=True) as (source,destination):
        destination.collections=['01_部件']
    bpy.context.scene.collection.children.link(destination.collections[0])
    rig=bpy.data.objects['RIG_bunny01'].copy()
    rig.data=rig.data.copy()
    bpy.context.scene.collection.objects.link(rig)
    # Preview objects are local copies of linked geometry so their modifier targets the action rig.
    linked=bpy.context.scene.collection.children.get('01_部件')
    preview=collection('01_动作预览_来自模型母版',bpy.context.scene.collection)
    for obj in list(linked.all_objects):
        if obj.type!='MESH': continue
        copy=obj.copy()
        preview.objects.link(copy)
        copy.parent=rig
        for modifier in copy.modifiers:
            if modifier.type=='ARMATURE': modifier.object=rig
        copy.hide_render = obj.get('variant_id')=='chibi_anime'
        copy.hide_set(copy.hide_render)
    bpy.context.scene.collection.children.unlink(linked)
    rig.animation_data_create()
    scene=bpy.context.scene
    scene.render.fps=60
    scene.unit_settings.system='METRIC'
    scene['file_role']='animation'
    scene['skeleton_sha256']=skeleton_hash
    scene['model_source']='../model/chr_bunny01_model_v009.blend'
    for name, clip in capture['clips'].items():
        action=bpy.data.actions.new('anim_bunny01_'+name+'_v009')
        action.use_fake_user=True
        action['state_id']=name
        action['loop']=clip['loop']
        action['duration']=clip['duration']
        action['migration_source']='v008 procedural presentation; editable Blender keys from v009 onward'
        rig.animation_data.action=action
        for index,frame in enumerate(clip['frames']):
            posed={}
            for bone,parent in PARENTS.items():
                local=C@matrix(frame[bone])@C.inverted()
                posed[bone]=posed[parent]@local if parent else local
                p=rig.pose.bones[bone]
                p.rotation_mode='QUATERNION'
                rest=rig.data.bones[bone]
                rest_local=rest.parent.matrix_local.inverted()@rest.matrix_local if rest.parent else rest.matrix_local
                p.matrix_basis=rest_local.inverted()@local
                for prop in ['location','rotation_quaternion','scale']: p.keyframe_insert(prop,frame=index+1,group=bone)
        for curve in action.fcurves:
            for key in curve.keyframe_points: key.interpolation='LINEAR'
    rig.animation_data.action=bpy.data.actions['anim_bunny01_idle_v009']
    scene.frame_start=1
    scene.frame_end=len(capture['clips']['idle']['frames'])
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(animation_path),relative_remap=True)
    print('CHARACTER_AUTHORING_CREATED',model_path,animation_path,skeleton_hash)

def bind(obj,rig,bone,branch):
    world=obj.matrix_world.copy()
    obj.data=obj.data.copy()
    obj.data.transform(world)
    obj.parent=rig
    obj.matrix_parent_inverse=Matrix.Identity(4)
    obj.matrix_basis=Matrix.Identity(4)
    for old in list(obj.users_collection): old.objects.unlink(obj)
    branch.objects.link(obj)
    obj.vertex_groups.clear()
    group=obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    modifier=obj.modifiers.new('共享骨架绑定','ARMATURE')
    modifier.object=rig
    obj['bone_id']=bone
    obj['variant_id']=branch.get('variant_id','bunny_white')

if __name__=='__main__': main()
