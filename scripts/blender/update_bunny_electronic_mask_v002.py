"""Enlarge the existing component; author facial curves in a separate Blender master.

GLTF carries the closed-eye morph. Blender-authored scalar curves are transferred
losslessly to a Godot AnimationLibrary (glTF does not carry emissive strength).
"""
import bpy, json, hashlib, shutil, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).parent))
from build_bunny_electronic_mask import ROOT, ASSET, MODEL, ANIMATION, ID, sha, signature, tag

VERSION = 'v002'
FPS = 100
CLIPS = {
    'mask_idle': (12., True,
        [(0,0),(2.8,0),(2.89,1),(2.96,1),(3.06,0),(7.2,0),(7.29,1),(7.36,1),(7.46,0),(12,0)],
        [(0,1),(5.1,1),(5.14,.18),(5.19,1),(5.24,.35),(5.29,1),(5.35,.55),(5.43,1),(10.1,1),(10.15,.4),(10.21,1),(12,1)]),
    'mask_blink': (.26, False, [(0,0),(.09,1),(.16,1),(.26,0)], [(0,1),(.26,1)]),
    'mask_flicker': (.42, False, [(0,0),(.42,0)], [(0,1),(.04,.18),(.09,1),(.14,.35),(.19,1),(.25,.55),(.33,1),(.42,1)]),
}

def author_curves(scene):
    scene['mask_blink'] = 0.; scene['mask_brightness'] = 1.
    result = {}
    for name, (duration, loop, blink, brightness) in CLIPS.items():
        action = bpy.data.actions.new(name); action.use_fake_user = True
        curves = {}
        for prop, keys in [('mask_blink',blink), ('mask_brightness',brightness)]:
            curve = action.fcurves.new(data_path=f'["{prop}"]')
            for time,value in keys:
                key = curve.keyframe_points.insert(1+time*FPS,value)
                key.interpolation = 'LINEAR'
            curves[prop] = [[round((k.co.x-1)/FPS,6), round(k.co.y,6)] for k in curve.keyframe_points]
        action['duration_seconds']=duration; action['loop']=loop
        result[name]={'duration':duration,'loop':loop,'tracks':curves,'action':action.name}
    scene.animation_data_create(); scene.animation_data.action=bpy.data.actions['mask_idle']
    scene.render.fps=FPS; scene.frame_start=1; scene.frame_end=1201; scene.frame_set(1)
    return result

def animation_library(clips):
    lines=['[gd_resource type="AnimationLibrary" load_steps=5 format=3]', '', '[sub_resource type="Animation" id="Reset"]', 'resource_name = "RESET"', 'length = 0.001']
    for i,(prop,value) in enumerate([('blink_amount',0),('pixel_brightness',1)]):
        lines.extend([f'tracks/{i}/type = "value"', f'tracks/{i}/path = NodePath(".:{prop}")',f'tracks/{i}/interp = 1',f'tracks/{i}/keys = {{"times": PackedFloat32Array(0), "transitions": PackedFloat32Array(1), "update": 0, "values": [{value}.0]}}'])
    for name,clip in clips.items():
        lines.extend(['',f'[sub_resource type="Animation" id="{name}"]',f'resource_name = "{name}"',f'length = {clip["duration"]}',f'loop_mode = {1 if clip["loop"] else 0}'])
        for i,(source,target) in enumerate([('mask_blink','blink_amount'),('mask_brightness','pixel_brightness')]):
            keys=clip['tracks'][source]
            times=', '.join(str(p[0]) for p in keys); values=', '.join(str(p[1]) for p in keys); transitions=', '.join('1' for p in keys)
            lines.extend([f'tracks/{i}/type = "value"',f'tracks/{i}/path = NodePath(".:{target}")',f'tracks/{i}/interp = 1',f'tracks/{i}/keys = {{"times": PackedFloat32Array({times}), "transitions": PackedFloat32Array({transitions}), "update": 0, "values": [{values}]}}'])
    lines.extend(['','[resource]','_data = {','"RESET": SubResource("Reset"),'])
    lines.extend(f'"{n}": SubResource("{n}")'+(',' if i<2 else '') for i,n in enumerate(clips))
    lines.extend(['}',''])
    path=ASSET/'runtime/chr_bunny01_electronic_mask_animations.tres'
    path.write_text('\n'.join(lines),encoding='utf-8'); return path

def main():
    # Preserve the completed v001 evidence and both original dependencies.
    archive=ROOT/'outputs/electronic_mask/v001'; archive.mkdir(parents=True,exist_ok=True)
    for name in ['asset_manifest.json','character_transfer_ledger.json','source_validation.json','verification_report.json']:
        p=ASSET/name
        if p.exists() and not (archive/name).exists(): shutil.copy2(p,archive/name)
    original_hashes={str(p):sha(p) for p in [MODEL,ANIMATION,ASSET/'source/chr_bunny01_electronic_mask_model_v001.blend']}
    bpy.ops.wm.open_mainfile(filepath=str(ASSET/'source/chr_bunny01_electronic_mask_model_v001.blend'))
    rig=bpy.data.objects['RIG_bunny01']; sig=signature(rig)
    shell=bpy.data.objects['SRC_Face_ElectronicMask_Shell']
    variant=bpy.data.collections['眼镜__electronic_mask']
    old=bpy.data.objects['SRC_Face_ElectronicMask_Pixels']; bpy.data.objects.remove(old,do_unlink=True)
    blue=bpy.data.materials['MAT_ElectronicMask_CyanPixels']
    surface=BVHTree.FromPolygons([v.co for v in shell.data.vertices],[list(p.vertices) for p in shell.data.polygons])
    cells=[]
    for side,x0 in [('L',-.112),('R',.112)]:
        for row in range(14):
            for col in range(5):
                x=x0+(col-2)*.014; z=.735+(row-6.5)*.014
                hit,normal,_,_=surface.ray_cast(Vector((x,2,z)),Vector((0,-1,0)))
                assert hit is not None,(x,z)
                bpy.ops.mesh.primitive_cube_add(size=1,location=hit+normal*.0034)
                obj=bpy.context.object; obj.name=f'SRC_Face_Pixel_{side}_{row:02d}_{col:02d}'
                obj.rotation_mode='QUATERNION'; obj.rotation_quaternion=normal.to_track_quat('Y','Z'); obj.scale=(.0108,.0025,.0108)
                bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
                for collection in list(obj.users_collection): collection.objects.unlink(obj)
                variant.objects.link(obj); obj.data.materials.append(blue); cells.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in cells: obj.select_set(True)
    bpy.context.view_layer.objects.active=cells[0]; bpy.ops.object.join()
    eye=bpy.context.object; eye.name='SRC_Face_ElectronicMask_Pixels'; tag(eye)
    eye.vertex_groups.new(name='head').add(list(range(len(eye.data.vertices))),1,'REPLACE')
    eye.modifiers.new('共享骨架绑定','ARMATURE').object=rig
    eye.shape_key_add(name='Basis'); blink=eye.shape_key_add(name='Blink')
    inverse=eye.matrix_world.inverted()
    for vertex in blink.data:
        world=eye.matrix_world@vertex.co
        oldhit,_,_,_=surface.ray_cast(Vector((world.x,2,world.z)),Vector((0,-1,0)))
        newz=.735+(world.z-.735)*.06
        newhit,_,_,_=surface.ray_cast(Vector((world.x,2,newz)),Vector((0,-1,0)))
        assert oldhit is not None and newhit is not None
        vertex.co=inverse@Vector((world.x,newhit.y+(world.y-oldhit.y),newz))
    scene=bpy.context.scene
    scene['electronic_mask_contract']='v002: 2x5x14 enlarged square cells; Blink surface morph; authored scalar AnimationLibrary; HeadJoint cosmetic component only.'
    model=ASSET/'source/chr_bunny01_electronic_mask_model_v002.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(model))
    clips=author_curves(scene)
    # The animation master previews exactly the authored channels.
    for channel,prop in [(blink,'mask_blink'),(blue.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'],'mask_brightness')]:
        curve=channel.driver_add('value' if channel==blink else 'default_value')
        variable=curve.driver.variables.new(); variable.name='value'; variable.type='SINGLE_PROP'
        variable.targets[0].id_type='SCENE'; variable.targets[0].id=scene; variable.targets[0].data_path=f'["{prop}"]'
        curve.driver.expression='value' if channel==blink else '5 * value'
    animation=ASSET/'source/chr_bunny01_electronic_mask_animation_v002.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(animation))
    # Model export excludes the preview drivers/actions and the shared skeleton.
    blink.driver_remove('value'); blue.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].driver_remove('default_value')
    blink.value=0; blue.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=5
    pivot=Matrix(json.loads(scene['runtime_component_rest'])['head']).translation
    bpy.ops.object.select_all(action='DESELECT'); copies=[]
    for obj in [shell,eye]:
        dup=obj.copy(); dup.data=obj.data.copy(); dup.parent=None; scene.collection.objects.link(dup)
        for mod in list(dup.modifiers):
            if mod.type=='ARMATURE': dup.modifiers.remove(mod)
        bpy.context.view_layer.objects.active=dup
        for mod in list(dup.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        dup.data.transform(Matrix.Translation(-pivot)@dup.matrix_world,shape_keys=True)
        dup.matrix_world=Matrix.Identity(4); dup.name='MaskShell' if obj==shell else 'ExpressionPixels'
        dup.vertex_groups.clear()
        if 'source_polygon_indices' in dup: del dup['source_polygon_indices']
        dup.select_set(True); copies.append(dup)
    glb=ASSET/'components/chr_bunny01_electronic_mask_visual.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=False,export_morph=True,export_yup=True,export_extras=True)
    library=animation_library(clips)
    curvefile=ASSET/'components/chr_bunny01_electronic_mask_expression_curves.json'
    curvefile.write_text(json.dumps({'schema':1,'version':VERSION,'source_animation':animation.relative_to(ROOT).as_posix(),'fps':FPS,'interpolation':'LINEAR','clips':clips},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert signature(rig)==sig
    assert all(sha(Path(path))==digest for path,digest in original_hashes.items())
    manifest=json.loads((ASSET/'asset_manifest.json').read_text('utf-8'))
    manifest.update(version=VERSION,status='exported_pending_godot_validation',classification='version_increment',validation_status='not_run',source_model=model.relative_to(ROOT).as_posix(),source_animation=animation.relative_to(ROOT).as_posix(),dependency_contract='Shared v021 skeleton/head poses unchanged. Separate v002 model/animation masters. GLB Blink morph + Blender-authored linear scalar curves transferred to Godot AnimationLibrary; no procedural character poses.',pixel_grid=[2,5,14],pixel_count=140,pixel_cell_size_m=.0108,pixel_pitch_m=.014,eye_dimensions_m=[.0668,.1928],clips=clips,original_source_hashes_preserved=True)
    manifest.pop('validation',None); manifest.pop('duplicate_gate',None)
    paths=[model,animation,glb,library,curvefile,MODEL,ANIMATION,ASSET/'runtime/chr_bunny01_electronic_mask_root.tscn',ROOT/'src/player3d/customization/ElectronicMaskExpression3D.gd']
    manifest['files']=[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'role':'dependency' if p in [MODEL,ANIMATION] else 'output'} for p in paths]
    for name in ['asset_manifest.json','character_transfer_ledger.json']: (ASSET/name).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('ELECTRONIC_MASK_V002_AUTHORED',json.dumps({'pixels':140,'clips':list(clips),'original_preserved':True}))

if __name__=='__main__': main()
