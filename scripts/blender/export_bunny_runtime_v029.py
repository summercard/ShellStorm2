"""Export evaluated active scenes, not stale/fake-user duplicate actions."""
from pathlib import Path
import sys,json,hashlib,subprocess,struct
import bpy
from mathutils import Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_character_bundle import signature,C
R=Path(__file__).resolve().parents[2]
B=R/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01'
MODEL=B/'production/v021/source/model/chr_bunny01_model_v021.blend'
VERSION=next((arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--source-version=')), 'v030' if '--firing-v030' in sys.argv else 'v029')
assert VERSION in ('v029','v030','v031','v032','v033')
SOURCE=B/f'source/animation/chr_bunny01_animation_{VERSION}.blend'
OUT=B/'components/chr_bunny01_motion';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');expected=signature(rig)
rest={k:Matrix(v) for k,v in json.loads(bpy.context.scene['runtime_component_rest']).items()}
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
old=json.loads((B/'production/v024/exports/anim_bunny01_library_v024.json').read_text())
clips=old['clips'];new={};selected=[];anchors={};action_fps={}
specs=json.loads((R/'outputs/character_pipeline/directional_v028/specs.json').read_text())
specs.update(json.loads((R/'outputs/character_pipeline/runtime_v029/new_specs.json').read_text()))
for s in list(bpy.data.scenes):
    state=s.get('preview_clip','')
    if not state.startswith(('sidearm_','longgun_','machinegun_','unarmed_')):continue
    assert state not in new,state
    bpy.context.window.scene=s;r=next(o for o in s.objects if o.type=='ARMATURE');assert signature(r)==expected
    anchors={side:list(C.to_3x3()@(rest['hand_'+side].inverted()@r.data.bones['hand_'+side].tail_local)) for side in ('l','r')}
    a=r.animation_data.action;selected.append(a);action_fps[a.name]=s.render.fps
    gun=next((o for o in s.objects if o.name.startswith('PREVIEW_GripSocket')),None)
    first,last=map(int,a.frame_range);frames=[]
    for frame in range(first,last+1):
        s.frame_set(frame);dg=bpy.context.evaluated_depsgraph_get();er=r.evaluated_get(dg)
        glob={}
        for n,m in rest.items():
            bone='chest' if n=='body' else n
            glob[n]=er.pose.bones[bone].matrix@r.data.bones[bone].matrix_local.inverted()@m if bone in er.pose.bones else m
        matrices={n:(glob['head'].inverted()@m if n.startswith('ear_') else glob['root'].inverted()@m if n not in ('root','feet') else m) for n,m in glob.items()}
        if gun:matrices['weapon_socket']=glob['root'].inverted()@gun.evaluated_get(dg).matrix_world
        values={}
        for n,m in matrices.items():
            p,q,sc=(C@m@C.inverted()).decompose()
            values[n]={'p':list(p),'q':[q.x,q.y,q.z,q.w],'s':[1,1,1] if n=='weapon_socket' else list(sc)}
        frames.append(values)
    new[state]=dict(duration=float(a['duration']),loop=bool(a['loop']),frames=frames,source_action=a.name)
    spec_key=state.replace('_fire_','_')
    if spec_key in specs:new[state]['reference_speed_mps']=specs[spec_key]['reference_speed_mps']
expected_count=35 if VERSION=='v029' else 77 if VERSION=='v033' else 74 if VERSION=='v032' else 62
assert len(new)==expected_count,len(new)
clips.update(new)
path=OUT/'anim_bunny01_library.json'
if VERSION=='v033':
    previous=json.loads(path.read_text(encoding='utf-8'))['clips']
    retained=[n for n in previous if not n.endswith('_reload')]
    assert len(retained)==88
    assert all(clips[n]==previous[n] for n in retained),'Unrelated runtime clip changed'
if VERSION=='v032':
    previous=json.loads(path.read_text(encoding='utf-8'))['clips']
    retained=[n for n in previous if not (n.startswith('unarmed_') and n.endswith(('forward','backward'))) and '_stow_' not in n and '_draw_' not in n]
    assert len(retained)==72
    assert all(clips[n]==previous[n] for n in retained),'Unrelated runtime clip changed'
if VERSION=='v031':
    previous=json.loads(path.read_text(encoding='utf-8'))['clips']
    retained=[n for n in clips if not (n.startswith(('longgun_','machinegun_')) and '_fire_' not in n)]
    assert len(retained)==58
    assert all(clips[n]==previous[n] for n in retained),'Unrelated runtime clip changed'
path.write_text(json.dumps(dict(schema=2,version=VERSION,skeleton_sha256=expected,palm_offsets=anchors,clips=clips),separators=(',',':')),encoding='utf-8')
# A clean animation-only interchange with the exact 35 new approved actions.
# Normalize source sampling rates to a common 60fps interchange time base.
for action in selected:
    first_frame,last_frame=map(float,action.frame_range)
    factor=60*float(action['duration'])/(last_frame-first_frame)
    if factor!=1:
        for curve in action.fcurves:
            for key in curve.keyframe_points:
                key.co.x=1+(key.co.x-first_frame)*factor
                key.handle_left.x=1+(key.handle_left.x-first_frame)*factor
                key.handle_right.x=1+(key.handle_right.x-first_frame)*factor
        action.frame_end=1+60*float(action['duration'])
for scene in bpy.data.scenes:scene.render.fps=60
rig=r
for o in list(bpy.data.objects):
    if o!=rig:bpy.data.objects.remove(o,do_unlink=True)
for action in list(bpy.data.actions):
    if action not in selected and not action.library:bpy.data.actions.remove(action)
rig.animation_data_clear();rig.animation_data_create();rig.animation_data.action=selected[0]
if selected[0].slots:rig.animation_data.action_slot=selected[0].slots[0]
for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.objects.active=rig;rig.select_set(True)
glb=OUT/'anim_bunny01_library.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_skins=False,export_morph=False,export_yup=True)
raw=glb.read_bytes();size,kind=struct.unpack_from('<II',raw,12);gltf=json.loads(raw[20:20+size])
assert not gltf.get('meshes') and not gltf.get('cameras')
assert len(gltf.get('animations',[]))==expected_count,len(gltf.get('animations',[]))
durations={a.name:float(a['duration']) for a in selected}
for animation in gltf['animations']:
    duration=max(gltf['accessors'][s['input']]['max'][0]-gltf['accessors'][s['input']]['min'][0] for s in animation['samplers'])
    assert abs(duration-durations[animation['name']])<1/60,(animation['name'],duration)
def entry(p):return dict(path=p.relative_to(R).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size)
ledger=dict(schema=1,asset_id='CHR-PLY-CAPSULE01-3D-BUNNY01',version='v029',status='exported_pending_godot_validation',classification='version_increment',skeleton_id='SKEL-BUNNY01-004',skeleton_sha256=expected,model_signature=expected,animation_signature=expected,files=[entry(p) for p in (MODEL,SOURCE,path,glb)],animation_adapter='anatomical_to_rigid_node_map',consumer='src/player3d/CharacterMotionLibrary3D.gd',state_owner='src/player3d/Player3D.gd',prefab='assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/runtime/chr_bunny01_root_v021.tscn',verification='verify_player3d_directional_motion',collision_owner='scenes/Player3D.tscn',authoring_height_m=1.5,blender_forward='+Y',godot_forward='-Z',preview_weapon_exported=False,clips={n:dict(duration=c['duration'],loop=c['loop'],frames=len(c['frames']),tracks=len(c['frames'][0])) for n,c in clips.items()},new_clip_count=35,retained_legacy_clip_count=14,glb_clip_count=35,missing_actions=['family_fire','family_reload','family_charge','heavy_melee'],rollback='Retained v028/v027 Blender sources and Git runtime baseline',git_baseline=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip())
ledger.update(version=VERSION,new_clip_count=expected_count,glb_clip_count=expected_count)
if VERSION in ('v030','v031','v032','v033'):
    ledger['missing_actions']=['family_reload','family_charge','heavy_melee']
    ledger['verification']='verify_player3d_firing_motion'
if VERSION=='v033':
    ledger['missing_actions']=['family_charge','heavy_melee']
    ledger['verification']='verify_player3d_reload_motion'
(B/'character_transfer_ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
print('RUNTIME_EXPORTED',len(clips),'GLB',len(gltf['animations']))
