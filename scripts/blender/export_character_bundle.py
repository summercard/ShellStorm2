"""Export the two existing authoring masters, with a hashed transfer ledger.

Blender --background --python scripts/blender/export_character_bundle.py -- <production/vNNN>
Exports evaluated bone animation for the legacy Node3D adapter plus skinned GLB.
"""
import sys
import json
import hashlib
from pathlib import Path
import bpy
from mathutils import Matrix

C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def signature(rig):
    data=[{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in rig.data.bones]
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()

def main():
    root=Path(__file__).resolve().parents[2]
    package=Path(sys.argv[sys.argv.index('--')+1]).resolve()
    models=list((package/'source/model').glob('*.blend'))
    motions=list((package/'source/animation').glob('*.blend'))
    assert len(models)==len(motions)==1, 'One model master and one animation master required'
    version=package.name
    output=package/'exports'
    output.mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(models[0]))
    if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    expected=signature(rig)
    skeleton_id=rig.get('skeleton_id','SKEL-BUNNY01-001')
    schema=int(bpy.context.scene.get('motion_schema',1))
    component_rest={k:Matrix(v) for k,v in json.loads(bpy.context.scene.get('runtime_component_rest','{}')).items()}
    assert tuple(rig.scale)==(1,1,1)
    entries=[]
    component_files=[]
    for branch in bpy.data.collections['01_部件'].children:
        for variant in branch.children:
            grouped={}
            for obj in variant.objects:
                if obj.type!='MESH': continue
                assert any(m.type=='ARMATURE' and m.object==rig for m in obj.modifiers), obj.name
                assert obj.vertex_groups.get(obj['bone_id']) is not None
                entries.append({'slot':branch.name,'variant':variant.name,'object':obj.name,'bone':obj['bone_id']})
                grouped.setdefault(obj.get('component_id',obj['bone_id']),[]).append(obj)
            for component,objects in grouped.items():
                bone=objects[0]['bone_id']
                bpy.ops.object.select_all(action='DESELECT')
                copies=[]
                for obj in objects:
                    copy=obj.copy()
                    copy.data=obj.data.copy()
                    copy.modifiers.clear()
                    copy.parent=None
                    # Rigid components exported in the bone's rest-local origin; Godot keeps existing joints.
                    pivot=component_rest[component].translation if component in component_rest else rig.data.bones[bone].head_local
                    copy.data.transform(Matrix.Translation(-pivot))
                    copy.matrix_world=Matrix.Identity(4)
                    bpy.context.scene.collection.objects.link(copy)
                    copy.hide_set(False)
                    copy.hide_viewport=False
                    copy.select_set(True)
                    copies.append(copy)
                suffix='chibi_anime' if objects[0].get('variant_id')=='chibi_anime' else component
                path=output/f'chr_bunny01_{suffix}_{version}.glb'
                bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
                component_files.append(path)
                for copy in copies: bpy.data.objects.remove(copy,do_unlink=True)
    # Only the registered armature and active default components enter the model GLB.
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH' and obj.get('variant_id')!='chibi_anime':
            obj.hide_set(False)
            obj.select_set(True)
    model_glb=output/f'chr_bunny01_model_{version}.glb'
    bpy.ops.export_scene.gltf(filepath=str(model_glb),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
    bpy.ops.wm.open_mainfile(filepath=str(motions[0]))
    if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    assert signature(rig)==expected, 'MODEL / ANIMATION skeleton rest mismatch; rebind before exporting'
    for obj in bpy.context.scene.objects:
        for modifier in obj.modifiers:
            modifier.show_viewport=False
    clips={}
    for action in bpy.data.actions:
        if 'state_id' not in action: continue
        rig.animation_data.action=action
        frames=[]
        start,end=map(int,action.frame_range)
        for frame in range(start,end+1):
            bpy.context.scene.frame_set(frame)
            values={}
            if schema==2:
                globals={}
                for name,rest in component_rest.items():
                    # v012+ binds the coat/body to chest. Sampling waist here
                    # silently discarded authored chest counter-motion.
                    source='chest' if name=='body' else name
                    globals[name]=(rig.pose.bones[source].matrix@rig.data.bones[source].matrix_local.inverted()@rest) if source in rig.pose.bones else rest
                matrices={name:(globals['head'].inverted()@m if name.startswith('ear_') else globals['root'].inverted()@m if name not in ('root','feet') else m) for name,m in globals.items()}
            else:
                matrices={b.name:b.parent.matrix.inverted()@b.matrix if b.parent else b.matrix.copy() for b in rig.pose.bones}
            for name,matrix in matrices.items():
                matrix=C@matrix@C.inverted()
                p,q,s=matrix.decompose()
                values[name]={'p':list(p),'q':[q.x,q.y,q.z,q.w],'s':list(s)}
            frames.append(values)
        state_id=str(action['state_id'])
        assert state_id not in clips, 'Duplicate production clip: '+state_id
        clips[state_id]={'duration':float(action['duration']),'loop':bool(action['loop']),'frames':frames}
    gameplay={'idle','moving','dashing','hurt','locked','falling','landing','dead'}
    variants={'walking','armed_walking','armed_moving','armed_idle'}
    required=gameplay|variants if schema==2 else gameplay
    assert set(clips)==required, 'Production clip set mismatch: '+str(sorted(set(clips)^required))
    expected_loops={'idle','moving','locked','walking','armed_walking','armed_moving','armed_idle'}
    assert {name for name,clip in clips.items() if clip['loop']}==expected_loops, 'Loop flags do not match the state contract'
    animation_json=output/f'anim_bunny01_library_{version}.json'
    animation_json.write_text(json.dumps({'schema':schema,'skeleton_sha256':expected,'clips':clips},separators=(',',':')))
    # Keep a standard animated GLB available for Skeleton3D consumers and DCC review.
    # Preview meshes (notably the hand-aligned pistol) are authoring aids only. Blender's
    # selected-object export can still pull armature descendants, so remove every mesh
    # from this unsaved export scene before writing the animation-only interchange file.
    # Remove objects from every loaded scene/library, not just the active scene:
    # linked preview collections can otherwise be gathered by the glTF animator.
    for obj in list(bpy.data.objects):
        if obj != rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    animation_glb=output/f'anim_bunny01_library_{version}.glb'
    bpy.ops.export_scene.gltf(filepath=str(animation_glb),export_format='GLB',use_selection=True,export_animations=True,export_skins=False,export_morph=False,export_yup=True)
    files=[models[0],motions[0],model_glb,animation_json,animation_glb]+component_files
    previous_ledger=package/f'character_transfer_ledger_{version}.json'
    previous=json.loads(previous_ledger.read_text()) if previous_ledger.exists() else {}
    ledger={'schema':1,'asset_id':'CHR-PLY-CAPSULE01-3D-BUNNY01','version':version,'skeleton_id':'SKEL-BUNNY01-001','skeleton_sha256':expected,'status':'exported_pending_godot_validation','animation_adapter':'rigid_node_bone_map','model_components':entries,'clips':{k:{'duration':v['duration'],'loop':v['loop'],'frame_count':len(v['frames'])} for k,v in clips.items()},'files':[{'path':str(p.relative_to(root)),'sha256':digest(p),'bytes':p.stat().st_size} for p in files],'collision_owner':'scenes/Player3D.tscn','authoring_height_m':1.5,'runtime_base_scale':0.7,'runtime_visual_height_m':1.05,
        'source_validation':previous.get('validation',previous.get('source_validation',{})),
        'presentation_contract':{'body_source_bone':'chest','weapon_grip':'hand_r_palm','blender_forward':'+Y','godot_forward':'-Z','preview_weapon_exported':False}}
    ledger['skeleton_id']=skeleton_id
    ledger['animation_adapter']='anatomical_to_rigid_node_map' if schema==2 else 'rigid_node_bone_map'
    ledger['skeleton_bones']=[{'name':b.name,'parent':b.parent.name if b.parent else None,'deform':b.use_deform} for b in rig.data.bones]
    ledger['validation_status']='not_run'
    (package/f'character_transfer_ledger_{version}.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
    print('CHARACTER_BUNDLE_EXPORTED',expected,len(entries),len(clips))

if __name__=='__main__': main()
