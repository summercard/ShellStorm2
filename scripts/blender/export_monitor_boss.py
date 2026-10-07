"""Export isolated Boss002 visual and evaluated pose motion; never edit v030 sources."""
import bpy, json, hashlib, math, shutil, datetime, subprocess
from pathlib import Path
from mathutils import Matrix

R=Path(__file__).resolve().parents[2]
bpy.context.preferences.filepaths.save_version=0
B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
C=B/'components/enm_boss_monitor002'; C.mkdir(parents=True,exist_ok=True)
Q=B/'previews/runtime'; Q.mkdir(parents=True,exist_ok=True)
CONV=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
COUNTS=dict(idle=96,move=48,melee_keyboard=54,melee_cable=60,heavy_spin_slam=96,special_prepare=36,special_insert=18,special_channel=24,special_recover=27,hurt=15,stun_enter=42,stun_loop=48,stun_exit=30,turn_left=24,turn_right=24,dead=60)
LOOPS=['idle','move','special_channel','stun_loop']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def signature(r):
    data=[{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in r.data.bones]
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
def load(kind):
    bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v030.blend'))
    bpy.context.window.scene=bpy.data.scenes['BOSS002_STUDIO']
    return bpy.data.objects['Boss002_Rig']

rig=load('animation'); sig=signature(rig)
def legacy_signature(r):return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in r.data.bones],sort_keys=True).encode()).hexdigest()
legacy_sig=legacy_signature(rig)
assert legacy_sig==json.loads((B/'source/rig_contract_v030.json').read_text())['skeleton_signature']
# A death-specific source clip reuses authored collapse, then settles and holds.
dead=bpy.data.actions['stun_enter'].copy();dead.name='dead';dead.use_fake_user=True
for fc in dead.fcurves:
    for k in fc.keyframe_points:
        k.co.x=1+(k.co.x-1)*1.25;k.handle_left.x=1+(k.handle_left.x-1)*1.25;k.handle_right.x=1+(k.handle_right.x-1)*1.25
    fc.keyframe_points.insert(61,fc.evaluate(53.5))
for s in bpy.data.scenes:s['asset_version']='v031'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v031.blend'))
bone_names=[b.name for b in rig.data.bones]
motion={};probes={};bounds={}
for name,n in COUNTS.items():
    rig.animation_data.action=bpy.data.actions[name];frames=[];probe=[];clipbounds={}
    for f in range(1,n+2):
        bpy.context.scene.frame_set(f)
        # Global evaluated matrices preserve Blender inherit_scale NONE, all constraints and drivers.
        frames.append({'bones':[[round(v,7) for row in CONV@p.matrix for v in row] for p in rig.pose.bones],
                       'expression':int(round(rig.get('expression_state',0))),
                       'face_scale':{slot:[bpy.data.objects['Texture '+slot].scale.x,bpy.data.objects['Texture '+slot].scale.z] for slot in ['large_eye','round_eye','mouth']}})
        probe.append({o:[round(v,6) for v in CONV@rig.pose.bones[o].head] for o in ['hand.L','hand.R','cable_16','monitor_tilt']})
        if f-1 in [0,n//2,n-1]:
            dg=bpy.context.evaluated_depsgraph_get();meshes={}
            for obj in ['Portrait display','Sculpted glove L','Sculpted glove R','Keyboard outer shell','Long data cable whip']:
                o=bpy.data.objects[obj].evaluated_get(dg);me=o.to_mesh();pts=[CONV@o.matrix_world@v.co for v in me.vertices];o.to_mesh_clear()
                meshes[obj]=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
            clipbounds[str(f-1)]=meshes
    motion[name]={'duration':n/30,'loop':name in LOOPS,'frames':frames}
    probes[name]=probe
    bounds[name]=clipbounds
(C/'monitor_motion.json').write_text(json.dumps({'schema':1,'fps':30,'skeleton_id':rig['skeleton_id'],'bones':bone_names,'clips':motion},separators=(',',':')))
(Q/'source_pose_probes.json').write_text(json.dumps(probes))
(Q/'source_mesh_bounds.json').write_text(json.dumps(bounds))
rig=load('model');assert signature(rig)==sig,'Dual source rest mismatch'
assert legacy_signature(rig)==legacy_sig
for s in bpy.data.scenes:s['asset_version']='v031'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v031.blend'))
rig.animation_data_clear()
for p in rig.pose.bones:
    for c in list(p.constraints):p.constraints.remove(c)
    p.matrix_basis=Matrix.Identity(4)
rig.data.pose_position='REST'
(C/'face_rest_scale.json').write_text(json.dumps({slot:[bpy.data.objects['Texture '+slot].scale.x,bpy.data.objects['Texture '+slot].scale.z] for slot in ['large_eye','round_eye','mouth']}))
# Physically remove studio and VFX across every loaded scene before export.
allowed=set(bpy.data.collections['BOSS002_MONITOR'].all_objects)
for o in list(bpy.data.objects):
    if o not in allowed:bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
# Extract packed source images for explicit runtime shader adapters.
textures={}
for mat in [bpy.data.materials.get(x) for x in ['BOSS002_01_BodyPalette','BOSS002_02_ExpressionAtlas','BOSS002_03_ScrollingCode']]:
    if not mat:continue
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE' and node.image:
            key={'BOSS002_01_BodyPalette':'body_palette','BOSS002_02_ExpressionAtlas':'expressions_atlas','BOSS002_03_ScrollingCode':'screen_code'}[mat.name]
            p=C/(key+'.png');node.image.filepath_raw=str(p);node.image.file_format='PNG';node.image.save();textures[key]=p.relative_to(R).as_posix()
# Simple glTF material. Runtime replaces expression/code shaders using the authored UV contract.
for mat in list(bpy.data.materials):
    if mat.name.startswith('BOSS002_0'):
        old=next((n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
        nodes=mat.node_tree.nodes;nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');bs=nodes.new('ShaderNodeBsdfPrincipled');mat.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        bs.inputs['Roughness'].default_value=.42
        if old:
            tex=nodes.new('ShaderNodeTexImage');tex.image=old;mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
            if 'Expression' in mat.name:mat.node_tree.links.new(tex.outputs['Alpha'],bs.inputs['Alpha']);mat.surface_render_method='DITHERED'
bpy.context.view_layer.update()
for o in bpy.context.scene.objects:o.hide_set(False);o.hide_viewport=False;o.select_set(True)
out=C/'enm_boss_monitor002_visual_top3d.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_animations=False,export_yup=True,export_skins=True,use_selection=True,export_cameras=False,export_lights=False)
contract=json.loads((B/'source/rig_contract_v030.json').read_text());contract.update(version='v031',formal_animations_authored=list(COUNTS),export_signature=sig,export_signature_schema='ordered bone names, parents and 8-decimal rest matrices')
(B/'source/rig_contract_v031.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
sources=[B/f'source/enm_boss_monitor002_{k}_v031.blend' for k in ['model','animation']]
transfer={'asset_id':'ENM-BOSS-MONITOR002-3D','version':'v031','status':'exported_pending_godot_validation','classification':'version_increment','skeleton_id':'SKEL-MONITOR002-005','model_signature':sig,'animation_signature':sig,'legacy_signature':legacy_sig,'source_sha256':{p.relative_to(R).as_posix():sha(p) for p in sources},'files':[{'path':p.relative_to(R).as_posix(),'sha256':sha(p)} for p in C.iterdir() if p.is_file() and p.suffix!='.import'], 'clips':{k:{'duration':n/30,'loop':k in LOOPS,'tracks':len(bone_names),'root_motion':False} for k,n in COUNTS.items()},'pose_sampling':'Evaluated C @ global matrices at 30Hz; preserve nonuniform stretch/shear and all constraints via Skeleton3D overrides, indexed by AnimationPlayer. No extra local-axis conversion.','textures':textures,'consumer':'src/enemy3d/MonitorBossPresentation.gd','collision_owner':'Enemy3D','rollback':'Retained v030 dual masters; runtime restore from Git baseline','git_baseline':None}
transfer['generated_at']=datetime.datetime.now().astimezone().isoformat(timespec='seconds');transfer['generated_by']='Codex / Blender evaluated exporter'
transfer['git_baseline']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
for item in transfer['files']:item['bytes']=(R/item['path']).stat().st_size
transfer['sources']=[{'kind':kind,'path':p.relative_to(R).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'skeleton_id':transfer['skeleton_id'],'skeleton_signature':sig} for kind,p in zip(['model','animation'],sources)]
transfer['parts']=[{'slot_id':'body','variant_id':'default','path':out.relative_to(R).as_posix()}]
transfer['consumers']={'packed_scene':(B/'runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn').relative_to(R).as_posix(),'controller':'src/enemy3d/Enemy3D.gd','state_machine':'Enemy3D.VALID_STATES','verification':['tests/verification/verify_monitor_boss_flow.tscn','tests/verification/verify_monitor_boss_visual.tscn']}
(B/'enm_boss_monitor002_transfer_ledger_v031.json').write_text(json.dumps(transfer,ensure_ascii=False,indent=2),encoding='utf-8')
print('MONITOR_EXPORT_OK',sig,len(bone_names),flush=True)
