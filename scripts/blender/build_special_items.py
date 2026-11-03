"""Author the three SPECIAL-ITEMS masters, derive low meshes, export pure visuals.

Run with Blender --background --python scripts/blender/build_special_items.py.
"""
import bpy
import hashlib
import json
import math
from mathutils import Vector
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from special_items_workspace import write, work_path

CATALOG = json.loads((ROOT / 'data/special_items/catalog.json').read_text(encoding='utf-8'))['items']
PALETTE = ROOT / 'assets/art/shared/palette/item_high_visibility_palette_10x10_512.png'
TEMPLATE = ROOT / 'art_source/items_weapons/_templates/prp/prp_template_source_v001.blend'
ROLES = ['01_精工金属_道具骨架', '02_细腻哑光_道具大面', '03_清漆反光_道具点缀', '04_柔和自发光_道具UI']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def record_contracts():
    ledger = {'schema':'special_items_delivery_v1','feature_id':'SPECIAL-ITEMS','date':'2026-11-03','items':[]}
    for definition in CATALOG:
        slug = definition['id']
        base = f'art_source/items_weapons/props/{slug}'
        contract = dict(definition)
        contract.update({'asset_id':definition['asset_id'], 'display_name_zh':definition['name'], 'category':'道具','subclass':'special_item','logical_id':slug,
                         'domain_ledger':'props','animation_tier':'tier_0_static','dimensions_m':definition['dimensions_m'],
                         'source_collection':f"ITM_{definition['name']}_中文资产管理",'anchor_contract':['HoldAnchor'],
                         'material_roles':ROLES,'origin':'bottom_center','front_axis':'-Z',
                         'collision_intent':'external_projectile_sweep_and_ground_loot',
                         'source_dir':base+'/source','stable_glb':f'assets/art/items_weapons/props/{slug}/components/itm_{slug}_ground_visual_top3d.glb',
                         'stable_prefab':f'assets/art/items_weapons/props/{slug}/runtime/itm_{slug}_ground_root_top3d.tscn'})
        write(base+'/asset_contract.json', json.dumps(contract, ensure_ascii=False, indent=2)+'\n')
        ledger['items'].append({'id':slug,'asset_id':definition['asset_id'],'status':'待制作','contract':base+'/asset_contract.json'})
    write('assets/registry/special_items_ledger.json',json.dumps(ledger, ensure_ascii=False, indent=2)+'\n')

def setup(definition):
    bpy.ops.wm.open_mainfile(filepath=str(TEMPLATE))
    bpy.context.preferences.filepaths.save_version=0
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    root = bpy.data.collections.new(f"ITM_{definition['name']}_中文资产管理")
    bpy.context.scene.collection.children.link(root)
    sections = {}
    for title in ['01_制作组件_已统一材质','02_游戏输出_整合模型','10_骨骼与动画','80_挂点_交互接口','90_展示环境_灯光相机']:
        collection = bpy.data.collections.new(title)
        root.children.link(collection)
        sections[title[:2]] = collection
    image = bpy.data.images.load(str(PALETTE), check_existing=True)
    materials = []
    for index, name in enumerate(ROLES):
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        nodes = material.node_tree.nodes
        bsdf = next(node for node in nodes if node.type=='BSDF_PRINCIPLED')
        texture = nodes.new('ShaderNodeTexImage')
        texture.image = image
        texture.interpolation = 'Closest'
        material.node_tree.links.new(texture.outputs['Color'],bsdf.inputs['Base Color'])
        bsdf.inputs['Metallic'].default_value = 0.8 if index==0 else 0.0
        bsdf.inputs['Roughness'].default_value = [0.45,0.7,0.28,0.55][index]
        if index==3:
            material.node_tree.links.new(texture.outputs['Color'],bsdf.inputs['Emission Color'])
            bsdf.inputs['Emission Strength'].default_value = 0.25
        materials.append(material)
    pixels = list(image.pixels)
    colors = []
    for row in range(10):
        for column in range(10):
            offset = (int((row+.5)*image.size[1]/10)*image.size[0]+int((column+.5)*image.size[0]/10))*4
            colors.append((column,row,pixels[offset:offset+3]))
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1.0
    bpy.context.scene.render.engine='BLENDER_EEVEE_NEXT'
    return sections,materials,colors

def assign(obj, collection, material, color, colors):
    for link in list(obj.users_collection):
        link.objects.unlink(obj)
    collection.objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    uv=obj.data.uv_layers.new(name='PaletteUV')
    uv.active_render=True
    column,row,_=min(colors,key=lambda entry:sum((entry[2][i]-color[i])**2 for i in range(3)))
    for face in obj.data.polygons:
        for i,loop in enumerate(face.loop_indices):
            angle=2*math.pi*i/len(face.loop_indices)
            uv.data[loop].uv=((column+.5+.22*math.cos(angle))/10,(row+.5+.22*math.sin(angle))/10)
    obj.select_set(False)
    return obj

def cube(name, position, dimensions, color, role=1, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj=bpy.context.object
    obj.name=name
    obj.dimensions=dimensions
    assign(obj,sections['01'],materials[role],color,colors)
    if bevel:
        modifier=obj.modifiers.new('CraftedEdges','BEVEL');modifier.width=bevel;modifier.segments=3
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        assign(obj,sections['01'],materials[role],color,colors)
    return obj

def lathe(name, profile, color, role=1, segments=32):
    vertices=[]
    for height,radius in profile:
        vertices += [(radius*math.cos(i*math.tau/segments),radius*math.sin(i*math.tau/segments),height) for i in range(segments)]
    faces=[]
    for ring in range(len(profile)-1):
        for i in range(segments):
            a=ring*segments+i;b=ring*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces += [tuple(reversed(range(segments))),tuple((len(profile)-1)*segments+i for i in range(segments))]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);sections['01'].objects.link(obj)
    return assign(obj,sections['01'],materials[role],color,colors)

def build(definition):
    global sections, materials, colors
    sections,materials,colors=setup(definition)
    slug=definition['id']
    if slug=='special_grenade':
        lathe('OliveFragmentationBody',[(0,.038),(.015,.061),(.04,.076),(.08,.08),(.12,.078),(.16,.068),(.185,.047)],(.19,.37,.12))
        lathe('YellowIdentificationBand',[(.128,.077),(.143,.073)],(.95,.63,.03),0)
        lathe('FuseCap',[(.18,.034),(.218,.031)],(.26,.31,.32),0)
        cube('SafetyLever',(0,-.015,.214),(.036,.10,.018),(.36,.41,.42),0,.003)
        cube('LeverArm',(0,.027,.173),(.027,.018,.09),(.36,.41,.42),0,.002)
        bpy.ops.mesh.primitive_torus_add(major_radius=.024,minor_radius=.004,major_segments=24,minor_segments=6,location=(.047,-.01,.213),rotation=(math.pi/2,0,0))
        assign(bpy.context.object,sections['01'],materials[0],(.7,.73,.72),colors).name='PullRing'
        # Four shallow vertical seams keep the stylized grenade readable in preview.
        for i in range(4):
            angle=i*math.pi/2
            obj=cube('FragmentSeam_%d'%i,(.078*math.cos(angle),.078*math.sin(angle),.09),(.004,.004,.095),(.07,.10,.05),1)
    elif slug=='special_molotov':
        lathe('GreenBottle',[(0,.055),(.015,.069),(.18,.071),(.225,.067),(.258,.028),(.305,.025),(.322,.027)],(.08,.48,.25),2)
        lathe('AmberPaperLabel',[(.066,.072),(.142,.072)],(.83,.47,.10),1)
        lathe('CorkAndCollar',[(.31,.028),(.337,.026)],(.35,.21,.09),1)
        obj=cube('ClothWick',(0,.006,.355),(.026,.065,.032),(.94,.86,.63),1,.003)
        obj.rotation_euler[1]=.35
        cube('DangerStripe',(0,-.073,.103),(.029,.003,.047),(.88,.14,.035),1,.002)
    else:
        cube('RedFuelBottle',(0,0,.12),(.24,.13,.24),(.76,.08,.025),1,.012)
        # Genuine open handle made from three independent structural pieces.
        cube('HandleLeft',(-.079,0,.259),(.022,.04,.065),(.94,.62,.02),1,.005)
        cube('HandleRight',(.015,0,.259),(.022,.04,.065),(.94,.62,.02),1,.005)
        cube('HandleTop',(-.032,0,.286),(.115,.04,.022),(.94,.62,.02),1,.005)
        obj=lathe('BlackScrewCap',[(.23,.024),(.263,.024)],(.08,.095,.11),0)
        obj.location.x=.08
        cube('HazardPlaque',(0,-.066,.126),(.1,.004,.095),(.99,.73,.08),1,.003)
        cube('HazardDarkCore',(0,-.069,.126),(.036,.003,.049),(.13,.10,.055),1,0)
        for x in [-.087,.087]:
            cube('RaisedRib',(x,-.068,.118),(.009,.008,.16),(.92,.18,.025),1,.002)
    # Fit the new physical contract once in Blender; runtime roots stay identity.
    components=list(sections['01'].objects)
    bounds=[obj.matrix_world@Vector(corner) for obj in components for corner in obj.bound_box]
    lo=Vector(tuple(min(v[i] for v in bounds) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in bounds) for i in range(3)))
    # Blender XYZ maps to Godot XZY.
    width,depth,height=definition['dimensions_m']
    factors=Vector((width/(hi.x-lo.x),depth/(hi.y-lo.y),height/(hi.z-lo.z)))
    center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for obj in components:
        for vertex in obj.data.vertices:
            vertex.co=((obj.matrix_world@vertex.co)-center)*factors
        obj.matrix_world.identity()
    bpy.ops.object.select_all(action='DESELECT')
    output_parts=[]
    for component in components:
        duplicate=component.copy();duplicate.data=component.data.copy()
        sections['02'].objects.link(duplicate);duplicate.select_set(True);output_parts.append(duplicate)
    bpy.context.view_layer.objects.active=output_parts[0]
    bpy.ops.object.join()
    output=bpy.context.object;output.name='ItemVisual'
    bpy.ops.object.select_all(action='DESELECT')
    anchor=bpy.data.objects.new('HoldAnchor',None);sections['80'].objects.link(anchor)
    anchor.location=(0,0,height*.5)
    sections['01'].hide_viewport=True;sections['01'].hide_render=True
    base=f'art_source/items_weapons/props/{slug}'
    source=ROOT/base/'source'/f'itm_{slug}_source_v001.blend'
    source.parent.mkdir(parents=True,exist_ok=True)
    for image in bpy.data.images:
        if image.source=='FILE':
            image.filepath=str(PALETTE)
    bpy.ops.wm.save_as_mainfile(filepath=str(source),relative_remap=False)
    for image in bpy.data.images:
        if image.source=='FILE':
            image.filepath=bpy.path.relpath(str(PALETTE))
    bpy.ops.wm.save_as_mainfile(filepath=str(source),relative_remap=False)
    preview_info=export(definition,output,anchor,'preview')
    # Low mesh is derived from the actual high output, with a measured triangle budget.
    bpy.ops.object.select_all(action='DESELECT');output.select_set(True);bpy.context.view_layer.objects.active=output
    modifier=output.modifiers.new('DerivedGroundReduction','DECIMATE')
    modifier.use_collapse_triangulate=True
    output.data.calc_loop_triangles();initial=len(output.data.loop_triangles)
    modifier.ratio=180/max(initial,1)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    triangulate=output.modifiers.new('GroundTriangles','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    low_bounds=[vertex.co.copy() for vertex in output.data.vertices]
    low_min=Vector(tuple(min(v[i] for v in low_bounds) for i in range(3)))
    low_max=Vector(tuple(max(v[i] for v in low_bounds) for i in range(3)))
    target_dimensions=Vector((width,depth,height))
    low_scale=Vector(tuple(target_dimensions[i]/(low_max[i]-low_min[i]) for i in range(3)))
    low_center=Vector(((low_min.x+low_max.x)*.5,(low_min.y+low_max.y)*.5,low_min.z))
    for vertex in output.data.vertices:
        vertex.co=(vertex.co-low_center)*low_scale
    output.data.update()
    # Repair UVs after reduction, retaining material/color identity face by face.
    mesh=output.data
    uv=mesh.uv_layers['PaletteUV']
    for face in mesh.polygons:
        previous=[uv.data[index].uv.copy() for index in face.loop_indices]
        center_uv=sum(previous,Vector((0,0)))/len(previous)
        column=max(0,min(9,int(center_uv.x*10)));row=max(0,min(9,int(center_uv.y*10)))
        for i,index in enumerate(face.loop_indices):
            angle=i*math.tau/len(face.loop_indices)
            uv.data[index].uv=((column+.5+.22*math.cos(angle))/10,(row+.5+.22*math.sin(angle))/10)
    mesh.calc_loop_triangles()
    assert 100<=len(mesh.loop_triangles)<=200,(slug,len(mesh.loop_triangles))
    ground_source=source.with_name(f'itm_{slug}_ground_source_v001.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(ground_source),relative_remap=False)
    ground_info=export(definition,output,anchor,'ground')
    manifest={'asset_id':definition['asset_id'],'version':'v001','logical_id':slug,'palette':PALETTE.relative_to(ROOT).as_posix(),
              'roles':{'preview':dict(preview_info,source=source.relative_to(ROOT).as_posix(),source_sha256=sha(source)),
                       'ground':dict(ground_info,source=ground_source.relative_to(ROOT).as_posix(),source_sha256=sha(ground_source),derived_from=source.relative_to(ROOT).as_posix())},
              'materials':ROLES,'uv':'PaletteUV; nonzero single-cell islands','license':'Original project art; authored for this feature'}
    write(base+'/source_manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('SPECIAL_MODEL_OK',slug,ground_info,flush=True)

def export(definition,output,anchor,role):
    slug=definition['id'];base=f'assets/art/items_weapons/props/{slug}'
    glb=f'{base}/components/itm_{slug}_{role}_visual_top3d.glb'
    target=ROOT/glb;target.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');output.select_set(True);anchor.select_set(True)
    bpy.context.view_layer.objects.active=output
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False,export_apply=True,export_yup=True)
    output.data.calc_loop_triangles();triangles=len(output.data.loop_triangles)
    width,depth,height=definition['dimensions_m']
    prefab=f'{base}/runtime/itm_{slug}_{role}_root_top3d.tscn'
    write(prefab,f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://{glb}" id="1_visual"]

[node name="ItemRoot" type="Node3D"]
metadata/asset_id = "{definition['asset_id']}"
metadata/logical_id = "{slug}"
metadata/asset_version = "v001"
metadata/model_role = "{role}"
metadata/triangle_count = {triangles}
metadata/dimensions_m = Vector3({width}, {height}, {depth})
metadata/front_axis = "-Z"
metadata/collision_intent = "external_projectile_sweep_and_ground_loot"

[node name="Visual" parent="." instance=ExtResource("1_visual")]
''')
    # Explicit import configuration: shared four item materials, no embedded images.
    import hashlib as _hash
    imported=f"res://.godot/imported/{target.name}-{_hash.md5(('res://'+glb).encode()).hexdigest()}.scn"
    write(glb+'.import',f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{imported}"

[deps]
source_file="res://{glb}"
dest_files=["{imported}"]

[params]
nodes/root_type=""
nodes/root_name="ItemVisual"
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/generate_lods=false
meshes/create_shadow_meshes=true
animation/import=false
import_script/path="res://tools/asset_pipeline/item_shared_palette_post_import.gd"
materials/extract=0
_subresources={{}}
gltf/embedded_image_handling=0
''')
    return {'glb':glb,'prefab':prefab,'triangles':triangles,'dimensions_m':definition['dimensions_m'],'glb_sha256':sha(target)}

record_contracts()
for definition in CATALOG:
    build(definition)
