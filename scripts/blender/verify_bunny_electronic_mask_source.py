"""Independent reopen audit: original geometry/UV/material/bones are conserved."""
import bpy,json,hashlib
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01'
ASSET=BASE/'components/face/electronic_mask'
def rig_signature(rig):
    data=[{'name':b.name,'parent':b.parent.name if b.parent else None,'rest':[round(v,8) for row in b.matrix_local for v in row]} for b in rig.data.bones]
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
def meshes():
    result={}
    for o in bpy.data.objects:
        if o.type!='MESH': continue
        data={'v':[list(v.co) for v in o.data.vertices],'p':[list(p.vertices) for p in o.data.polygons],'uv':[[list(d.uv) for d in layer.data] for layer in o.data.uv_layers],'matrix':[list(row) for row in o.matrix_world],'materials':[m.name for m in o.data.materials],'groups':[(g.name,g.index) for g in o.vertex_groups],'weights':[[(g.group,g.weight) for g in v.groups] for v in o.data.vertices]}
        result[o.name]=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
    return result
bpy.ops.wm.open_mainfile(filepath=str(BASE/'production/v021/source/model/chr_bunny01_model_v021.blend'))
old=meshes(); sig=rig_signature(bpy.data.objects['RIG_bunny01'])
ledger=json.loads((ASSET/'character_transfer_ledger.json').read_text('utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/ledger['source_model']))
new=meshes(); assert all(new.get(k)==v for k,v in old.items()),'Original mesh drift'
assert rig_signature(bpy.data.objects['RIG_bunny01'])==sig,'Skeleton drift'
col=bpy.data.collections['01_部件'].children['眼镜'].children['眼镜__electronic_mask']
if ledger.get('expressions'):
    assert len(col.all_objects)==9
    for definition in ledger['expressions']:
        obj=bpy.data.objects[definition['source_object']]
        assert len(obj.data.vertices)==definition['pixel_count']*8
        assert obj['expression_id']==definition['expression_id']
        assert len(obj.data.shape_keys.key_blocks)==2
        if ledger.get('mouth_free'):
            plan=json.loads(bpy.context.scene['expression_plan'])[definition['expression_id']]
            assert len(plan)==definition['pixel_count']
            actual=set()
            for i in range(0,len(obj.data.vertices),8):
                center=sum((obj.matrix_world@v.co for v in obj.data.vertices[i:i+8]),Vector())/8
                actual.add((round(center.x/.014+18),round(10.5-(center.z-.735)/.014)))
            assert actual==set(map(tuple,plan)), 'Authored cell geometry differs from mouth-free plan'
            if definition['kind']=='emotion':
                assert all(x<=15 or x>=21 for x,y in plan), 'Mouth cells present'
            assert obj.data.materials[0] is not None
            strength=obj.data.materials[0].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value
            assert abs(strength-ledger.get('emission_strength',5))<1e-6, 'Expression emission strength mismatch'
            if definition['kind']=='emotion':
                basis=[(obj.matrix_world@v.co).z for v in obj.data.shape_keys.key_blocks['Basis'].data]
                closed=[(obj.matrix_world@v.co).z for v in obj.data.shape_keys.key_blocks['Blink'].data]
                assert abs((max(closed)-min(closed))/(max(basis)-min(basis))-.06)<1e-4, 'Eye cells do not close fully'
else:
    assert {o.name for o in col.objects}=={'SRC_Face_ElectronicMask_Shell','SRC_Face_ElectronicMask_Pixels'}
shell=bpy.data.objects['SRC_Face_ElectronicMask_Shell']; eye=bpy.data.objects['SRC_Face_ElectronicMask_Pixels']
assert len(eye.data.vertices)==ledger['pixel_count']*8
if ledger.get('mouth_free'):
    assert ledger['pixel_grid']==[2,6,15] and ledger['pixel_count']==180
    width=(ledger['pixel_grid'][1]-1)*ledger['pixel_pitch_m']+ledger['pixel_cell_size_m']
    height=(ledger['pixel_grid'][2]-1)*ledger['pixel_pitch_m']+ledger['pixel_cell_size_m']
    assert all(abs(a-b)<1e-6 for a,b in zip(ledger['eye_dimensions_m'],[width,height]))
if ledger['version']=='v002':
    assert eye.data.shape_keys.key_blocks.keys()==['Basis','Blink']
    assert abs(ledger['pixel_cell_size_m']/.0058-1.8620689)<1e-5
source=bpy.data.objects['SRC_Head']
source_vertices={tuple(round(v.co[i],6) for i in range(3)) for v in source.data.vertices}
matches=0
for v in shell.data.vertices:
    key=(round(v.co.x,6),round(v.co.y-.009,6),round(v.co.z,6))
    # Floating point addition can cross a rounding boundary; compare distance
    # directly if the rounded key is not equal.
    if key in source_vertices or min((v.co-b.co-Vector((0,.009,0))).length for b in source.data.vertices)<1e-6:
        matches+=1
assert matches==len(shell.data.vertices),'Shell is not copied from original head'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'production/v021/source/animation/chr_bunny01_animation_v021.blend'))
animation_rig=next(o for o in bpy.data.objects if o.type=='ARMATURE' and 'head' in o.data.bones)
assert rig_signature(animation_rig)==sig,'Animation skeleton mismatch'
if ledger.get('source_animation'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/ledger['source_animation']))
    assert all(meshes().get(k)==v for k,v in old.items()),'Animation master altered original geometry'
    assert rig_signature(bpy.data.objects['RIG_bunny01'])==sig
    curves=json.loads((ASSET/'components/chr_bunny01_electronic_mask_expression_curves.json').read_text('utf-8'))
    for name,clip in curves['clips'].items():
        action=bpy.data.actions[name]
        for prop,keys in clip['tracks'].items():
            curve=action.fcurves.find(f'["{prop}"]')
            assert curve is not None
            for time,value in keys:
                assert abs(curve.evaluate(1+time*100)-value)<1e-5,(name,time,value)
            assert all(k.interpolation=='LINEAR' for k in curve.keyframe_points)
    bpy.context.scene.frame_set(293)
    assert bpy.data.objects['SRC_Face_ElectronicMask_Pixels'].data.shape_keys.key_blocks['Blink'].value>.99,'Animation source preview did not blink'
    bpy.context.scene.frame_set(515)
    strength=bpy.data.objects['SRC_Face_ElectronicMask_Pixels'].data.materials[0].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value
    assert abs(strength-ledger.get('emission_strength',5)*.18)<1e-4,'Animation source preview did not flicker'
for entry in ledger['files']:
    path=ROOT/entry['path']; assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256'],entry['path']
report={'result':'pass','version':ledger['version'],'original_meshes_preserved':len(old),'original_geometry_uv_material_transform_weights_preserved':True,'skeleton_signature':sig,'model_animation_rest_signatures_match':True,'all_shell_vertices_copied_from_original':matches,'pixel_cells':ledger['pixel_count'],'authored_animation_curves_match':bool(ledger.get('source_animation')),'collection_path':'01_部件/眼镜/眼镜__electronic_mask','source_hashes_match':True,'mouth_free':ledger.get('mouth_free',False),'pixel_cell_size_m':ledger.get('pixel_cell_size_m'),'emission_strength':ledger.get('emission_strength',5)}
if ledger.get('expressions'):
    report['all_emotion_morphs_close_fully']=bool(ledger.get('mouth_free'))
    report['expression_meshes_verified']={e['expression_id']:e['pixel_count'] for e in ledger['expressions']}
(ASSET/'source_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('ELECTRONIC_MASK_SOURCE_OK',json.dumps(report,ensure_ascii=False))
