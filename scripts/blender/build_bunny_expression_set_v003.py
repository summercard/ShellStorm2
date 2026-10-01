"""Author eight real cell meshes from a frozen pixel-art plan; keep prior masters."""
import bpy,json,sys,shutil
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from build_bunny_electronic_mask import ROOT,ASSET,MODEL,ANIMATION,ID,signature,sha,tag,material
from update_bunny_electronic_mask_v002 import author_curves,animation_library
from electronic_mask_expression_definitions_v003 import EXPRESSIONS,asset_id,slug,pixels

def record(paths):
    return [{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'role':role} for p,role in paths]

def export(objects,path,pivot):
    bpy.ops.object.select_all(action='DESELECT'); copies=[]
    for obj in objects:
        dup=obj.copy(); dup.data=obj.data.copy(); dup.parent=None; bpy.context.scene.collection.objects.link(dup)
        for mod in list(dup.modifiers):
            if mod.type=='ARMATURE': dup.modifiers.remove(mod)
        bpy.context.view_layer.objects.active=dup
        for mod in list(dup.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        dup.data.transform(Matrix.Translation(-pivot)@dup.matrix_world,shape_keys=True)
        dup.matrix_world=Matrix.Identity(4); dup.name='MaskShell' if obj.name=='SRC_Face_ElectronicMask_Shell' else 'ExpressionPixels'
        dup.vertex_groups.clear()
        if 'source_polygon_indices' in dup: del dup['source_polygon_indices']
        dup.select_set(True); copies.append(dup)
    path.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_morph=True,export_yup=True,export_extras=True)
    for obj in copies: bpy.data.objects.remove(obj,do_unlink=True)

def main():
    archive=ROOT/'outputs/electronic_mask/v002'; archive.mkdir(parents=True,exist_ok=True)
    for name in ['asset_manifest.json','character_transfer_ledger.json','verification_report.json','source_validation.json']:
        if not (archive/name).exists(): shutil.copy2(ASSET/name,archive/name)
    previous=ASSET/'source/chr_bunny01_electronic_mask_model_v002.blend'
    model=ASSET/'source/chr_bunny01_electronic_mask_model_v003.blend'
    animation=ASSET/'source/chr_bunny01_electronic_mask_animation_v003.blend'
    if model.exists() or animation.exists():
        pending=json.loads((ASSET/'asset_manifest.json').read_text('utf-8'))
        assert pending['version']=='v003' and pending['status']=='exported_pending_godot_validation','Keep released source versions immutable'
    bpy.context.preferences.filepaths.save_version=0
    before={str(p):sha(p) for p in [MODEL,ANIMATION,previous,ASSET/'source/chr_bunny01_electronic_mask_animation_v002.blend']}
    bpy.ops.wm.open_mainfile(filepath=str(previous))
    rig=bpy.data.objects['RIG_bunny01']; sig=signature(rig); scene=bpy.context.scene
    shell=bpy.data.objects['SRC_Face_ElectronicMask_Shell']; variant=bpy.data.collections['眼镜__electronic_mask']
    bpy.data.objects.remove(bpy.data.objects['SRC_Face_ElectronicMask_Pixels'],do_unlink=True)
    surface=BVHTree.FromPolygons([v.co for v in shell.data.vertices],[list(p.vertices) for p in shell.data.polygons])
    objects={}; palette={}
    for key,name,kind,color,emission,blink_enabled in EXPRESSIONS:
        collection=bpy.data.collections.new('表情__'+key); variant.children.link(collection)
        collection['asset_id']=asset_id(key); collection['expression_id']=key
        mat=material('MAT_MaskExpression_'+key,tuple(v*.45 for v in emission),.1,.28,emission)
        palette[key]=mat; cells=[]
        for col,row in pixels(key):
            x=(col-18)*.014; z=.735+(10.5-row)*.014
            hit,normal,_,_=surface.ray_cast(Vector((x,2,z)),Vector((0,-1,0))); assert hit is not None,(key,x,z)
            bpy.ops.mesh.primitive_cube_add(size=1,location=hit+normal*.0034)
            obj=bpy.context.object; obj.rotation_mode='QUATERNION'; obj.rotation_quaternion=normal.to_track_quat('Y','Z'); obj.scale=(.0108,.0025,.0108)
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            for branch in list(obj.users_collection): branch.objects.unlink(obj)
            collection.objects.link(obj); obj.data.materials.append(mat); cells.append(obj)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in cells: obj.select_set(True)
        bpy.context.view_layer.objects.active=cells[0]; bpy.ops.object.join(); eye=bpy.context.object
        eye.name='SRC_Face_ElectronicMask_Pixels' if key=='neutral' else 'SRC_Face_Expression_'+key
        tag(eye); eye['expression_id']=key; eye['asset_id']=asset_id(key); eye['pixel_count']=len(pixels(key)); eye['blink_enabled']=blink_enabled
        eye.vertex_groups.new(name='head').add(list(range(len(eye.data.vertices))),1,'REPLACE')
        eye.modifiers.new('共享骨架绑定','ARMATURE').object=rig
        eye.shape_key_add(name='Basis'); blink=eye.shape_key_add(name='Blink'); inverse=eye.matrix_world.inverted()
        if blink_enabled:
            for vertex in blink.data:
                world=eye.matrix_world@vertex.co
                # Eye/heart channels close about their own eye center; mouths
                # remain readable instead of collapsing the entire expression.
                if key!='neutral' and (abs(world.x)<.072 or world.z<.67): continue
                center=.735
                oldhit,_,_,_=surface.ray_cast(Vector((world.x,2,world.z)),Vector((0,-1,0)))
                newz=center+(world.z-center)*.06
                newhit,_,_,_=surface.ray_cast(Vector((world.x,2,newz)),Vector((0,-1,0)))
                assert oldhit is not None and newhit is not None
                vertex.co=inverse@Vector((world.x,newhit.y+world.y-oldhit.y,newz))
        eye.hide_render=key!='neutral'; objects[key]=eye
    scene['expression_plan']=json.dumps({key:pixels(key) for key,*_ in EXPRESSIONS})
    scene['electronic_mask_contract']='v003: eight individually registered mesh emotions/symbols; independent expression owner; original head/rig unchanged.'
    bpy.ops.wm.save_as_mainfile(filepath=str(model))
    clips=author_curves(scene)
    drivers=[]
    for key,eye in objects.items():
        for target,attribute,prop,expression in [(eye.data.shape_keys.key_blocks['Blink'],'value','mask_blink','value'),(palette[key].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'],'default_value','mask_brightness','5 * value')]:
            curve=target.driver_add(attribute); variable=curve.driver.variables.new(); variable.name='value'; variable.type='SINGLE_PROP'
            variable.targets[0].id_type='SCENE'; variable.targets[0].id=scene; variable.targets[0].data_path=f'["{prop}"]'; curve.driver.expression=expression
            drivers.append((target,attribute))
    bpy.ops.wm.save_as_mainfile(filepath=str(animation))
    for target,attribute in drivers: target.driver_remove(attribute)
    scene.frame_set(1)
    for eye in objects.values(): eye.data.shape_keys.key_blocks['Blink'].value=0
    for mat in palette.values(): mat.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=5
    pivot=Matrix(json.loads(scene['runtime_component_rest'])['head']).translation
    glb=ASSET/'components/chr_bunny01_electronic_mask_visual.glb'; export([shell,objects['neutral']],glb,pivot)
    library=animation_library(clips)
    curvefile=ASSET/'components/chr_bunny01_electronic_mask_expression_curves.json'
    curvefile.write_text(json.dumps({'schema':1,'version':'v003','source_animation':animation.relative_to(ROOT).as_posix(),'fps':100,'interpolation':'LINEAR','clips':clips},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    entries=[]
    for key,name,kind,color,emission,blink_enabled in EXPRESSIONS:
        package=ASSET/'expressions'/slug(key); (package/'runtime').mkdir(parents=True,exist_ok=True)
        visual=package/'components'/f'{slug(key)}_visual_top3d.glb'; export([objects[key]],visual,pivot)
        prefab=package/'runtime'/f'{slug(key)}_root_top3d.tscn'
        prefab.write_text(f'[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="res://{visual.relative_to(ROOT).as_posix()}" id="1_visual"]\n\n[node name="ExpressionVisual" type="Node3D"]\nmetadata/asset_id = "{asset_id(key)}"\nmetadata/asset_version = "v001"\nmetadata/expression_id = "{key}"\nmetadata/presentation_only = true\n\n[node name="Visual" parent="." instance=ExtResource("1_visual")]\n',encoding='utf-8')
        item={'expression_id':key,'asset_id':asset_id(key),'name':name,'kind':kind,'color':color,'blink_enabled':blink_enabled,'pixel_count':len(pixels(key)),'scene':prefab.relative_to(ROOT).as_posix(),'source_object':objects[key].name}
        entries.append(item)
        transfer={'schema':1,'asset_id':asset_id(key),'version':'v001','status':'exported_pending_godot_validation','classification':'child_variant','parent_asset_id':ID,'expression':item,'source_model':model.relative_to(ROOT).as_posix(),'source_animation':animation.relative_to(ROOT).as_posix(),'shared_source':True,'skeleton_id':'SKEL-BUNNY01-004','skeleton_sha256':sig,'blender_forward':'+Y','godot_forward':'-Z','root_scale':1,'collision_owner':'external Player3D','files':record([(visual,'output'),(prefab,'runtime_wrapper'),(model,'dependency'),(animation,'dependency')])}
        for namefile in ['asset_manifest.json','character_transfer_ledger.json']: (package/namefile).write_text(json.dumps(transfer,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    catalog=ROOT/'src/presentation/expressions/CharacterExpressionCatalog.gd'
    lines=['class_name CharacterExpressionCatalog','extends RefCounted','## Generated from the Blender pixel-art plan; stable scene IDs, no gameplay authority.','const ENTRIES := {']
    for item in entries:
        key=item['expression_id']; lines.append(f'\t"{key}": {{"asset_id": "{item["asset_id"]}", "name": "{item["name"]}", "kind": "{item["kind"]}", "color": Color("{item["color"]}"), "blink_enabled": {str(item["blink_enabled"]).lower()}, "scene": preload("res://{item["scene"]}")}},')
    lines.extend(['}','', 'static func has_expression(id: String) -> bool:', '\treturn ENTRIES.has(id)', '', 'static func get_definition(id: String) -> Dictionary:', '\treturn (ENTRIES.get(id, {}) as Dictionary).duplicate()', '', 'static func get_ids() -> Array[String]:', '\tvar result: Array[String] = []', '\tfor id in ENTRIES:', '\t\tresult.append(str(id))', '\treturn result',''])
    catalog.parent.mkdir(parents=True,exist_ok=True); catalog.write_text('\n'.join(lines),encoding='utf-8')
    catalogfile=ASSET/'components/chr_bunny01_expression_catalog.json'; catalogfile.write_text(json.dumps({'schema':1,'version':'v003','expressions':entries},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest=json.loads((archive/'asset_manifest.json').read_text('utf-8'))
    manifest.update(version='v003',classification='version_increment',status='exported_pending_godot_validation',validation_status='not_run',source_model=model.relative_to(ROOT).as_posix(),source_animation=animation.relative_to(ROOT).as_posix(),expression_catalog=catalogfile.relative_to(ROOT).as_posix(),expressions=entries,clips=clips,dependency_contract='Shared original skeleton and head pose; eight independent mesh child components. Separate expression owner, event adapter, mesh display; authored local blink/flicker curves retained.')
    manifest.pop('validation',None)
    paths=[(model,'output'),(animation,'output'),(glb,'output'),(library,'output'),(curvefile,'output'),(catalogfile,'output'),(catalog,'runtime_catalog'),(MODEL,'dependency'),(ANIMATION,'dependency'),(ASSET/'runtime/chr_bunny01_electronic_mask_root.tscn','runtime_wrapper'),(ROOT/'src/player3d/customization/ElectronicMaskExpression3D.gd','adapter')]
    manifest['files']=record(paths)
    for namefile in ['asset_manifest.json','character_transfer_ledger.json']: (ASSET/namefile).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert signature(rig)==sig and all(sha(Path(p))==s for p,s in before.items())
    print('EXPRESSION_SET_AUTHORED',json.dumps({item['expression_id']:item['pixel_count'] for item in entries}))
if __name__=='__main__': main()
