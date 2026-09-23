"""Widen the reference room type to three 5 m lanes and reserve shared door bays.

Run through Blender MCP while v002 is open. v002 remains immutable.
"""
import bpy, json, os, math, shutil
from mathutils import Vector

ROOT='/Users/summercards/ShellStorm2'
BASE=ROOT+'/assets/art/environments/tower_zones/battle/source/room_types/l_corridor'
V2=BASE+'/v002'; OUT=BASE+'/v003'
COMMON=ROOT+'/assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend'
assert os.path.realpath(bpy.data.filepath)==os.path.realpath(V2+'/l_corridor_room_type_v002.blend'),bpy.data.filepath
os.makedirs(OUT,exist_ok=True)
for name in ('reference.png','reference_crop_a.png','reference_crop_b.png'):
    shutil.copy2(V2+'/'+name,OUT+'/'+name)
shutil.copytree(V2+'/component_packages_v002',OUT+'/component_packages_v003',dirs_exist_ok=True)
with open(V2+'/component_packages_v002/catalog.json') as f: catalog=json.load(f)
with open(V2+'/room_type_manifest.json') as f: room=json.load(f)
game=bpy.data.collections['02_游戏输出_独立资产包_v001']
floor=bpy.data.collections['02_地面系统']; arch=bpy.data.collections['01_建筑结构']
support=bpy.data.collections['04_环境支持']; source=bpy.data.collections['01_制作组件_按设施拆分']
M={m.name:m for m in bpy.data.materials}

def catalog_entry(slug):
    return next(e for e in catalog if e['path'].split('/')[-1]==slug)
def manifest_path(entry):
    return OUT+'/'+entry['path'].replace('component_packages_v002','component_packages_v003')+'/asset_manifest.json'
def pack(slug):
    e=catalog_entry(slug)
    with open(manifest_path(e)) as f: rec=json.load(f)
    return bpy.data.collections[rec['collection']]
def remove_pack(slug):
    e=catalog_entry(slug);col=pack(slug)
    for ob in list(col.objects):bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.collections.remove(col,do_unlink=True)
    shutil.rmtree(os.path.dirname(manifest_path(e)))
    catalog.remove(e)
def translate(slug,dx=0,dy=0,dz=0):
    for o in pack(slug).objects:o.location+=Vector((dx,dy,dz))

# Four 5 m door-wall positions remain empty for the shared wall_door_5m + door_5m.
# The two side-wall bays preserve the reference composition; the west and south
# end caps use the middle of the new three-module width.
for slug in ('wall_x_05_rear','wall_x_35_rear','wall_y_30_00',
             'wall_x_35_front','wall_x_30_front','door_west','door_east','door_south'):
    remove_pack(slug)

# Move the rear edge of the long arm from y=10 to y=15, with every directly
# attached package following the wall, including cable anchor points.
for e in list(catalog):
    slug=e['path'].split('/')[-1]
    if slug.startswith('wall_x_') and slug.endswith('_rear'):
        translate(slug,dy=5)
    elif slug.startswith(('high_pipe_rear_','pipe_riser_')):
        translate(slug,dy=5)
    elif slug in ('server_00','server_01','server_gallery','console_00','console_01',
                  'crate_00','crate_01','planter_00','planter_01','service_cart_gallery',
                  'hanging_cable_gallery_a','hanging_cable_gallery_b','wall_label_gallery'):
        translate(slug,dy=5)
    elif slug=='hanging_cable_turn':
        translate(slug,dy=5)

# Widen the south arm westward one grid cell. The old inner wall becomes the
# cutaway on x=30; the east wall stays at x=45.
for e in list(catalog):
    slug=e['path'].split('/')[-1]
    if slug.startswith('wall_y_') and slug.endswith('_35'):
        translate(slug,dx=-5)
        col=pack(slug)
        old_path=os.path.dirname(manifest_path(e));new_slug=slug[:-2]+'30'
        new_path=os.path.join(os.path.dirname(old_path),new_slug)
        os.rename(old_path,new_path)
        col.name=col.name.replace('_35米','_30米')
        renamed_manifest=os.path.join(new_path,'asset_manifest.json')
        with open(renamed_manifest) as f:renamed=json.load(f)
        renamed['collection']=col.name
        with open(renamed_manifest,'w') as f:json.dump(renamed,f,ensure_ascii=False,indent=2)
        e['path']=e['path'][:-len(slug)]+new_slug

# Facilities in both branches occupy the perimeter strip. The middle 5 m lane
# remains free of equipment and fixed obstacles.
translate('server_04',dx=-4.9)
translate('console_02',dx=4.6)
translate('planter_02',dx=-5.0)
for slug,dx in (('server_02',.7),('server_03',.7),('crate_04',.7),('service_cart_south',.6)):
    translate(slug,dx=dx)
contract=pack('cutaway_wall_contract_0')
for ob in contract.objects:
    ob.location.x=15.0;ob.dimensions.x=30.0
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);ob.select_set(False)
translate('cutaway_wall_contract_1',dx=-5)

# Bring the existing formal shared art meshes into the same source scene. Mesh
# datablocks are copied; colours continue to use this source's four materials.
want=['floor_tile_r01_c01_主体_输出','floor_tile_r01_c01_主体_输出.001',
      'floor_tile_r01_c02_主体_输出','floor_tile_r01_c02_主体_输出.001',
      'wall_standard_5m_主体_输出']
with bpy.data.libraries.load(COMMON,link=False) as (src,dst):
    dst.objects=[n for n in want if n in src.objects]
lib={o.name:o for o in dst.objects if o is not None}
def shared_mesh(name):
    me=lib[name].data.copy()
    for i,mat in enumerate(me.materials):
        if mat and mat.name.split('.')[0] in M:me.materials[i]=M[mat.name.split('.')[0]]
    return me
tiles_A=[shared_mesh('floor_tile_r01_c01_主体_输出'),shared_mesh('floor_tile_r01_c01_主体_输出.001')]
tiles_B=[shared_mesh('floor_tile_r01_c02_主体_输出'),shared_mesh('floor_tile_r01_c02_主体_输出.001')]
wall_mesh=shared_mesh('wall_standard_5m_主体_输出')
wall_uv=wall_mesh.uv_layers.get('PaletteUV')
assert wall_uv is not None
wall_uv.active_render=True;wall_mesh.uv_layers.active=wall_uv
for poly in wall_mesh.polygons:
    for j,li in enumerate(poly.loop_indices):
        a,b=[(-.024,-.024),(.024,-.024),(.024,.024),(-.024,.024)][j%4]
        wall_uv.data[li].uv=(.95+a,.95+b)
for ob in lib.values():bpy.data.objects.remove(ob,do_unlink=True)
for mat in list(bpy.data.materials):
    if mat.name not in M:bpy.data.materials.remove(mat,do_unlink=True)

def clone_pack(template_slug,new_slug,dx,dy,category=None):
    original=pack(template_slug)
    old=catalog_entry(template_slug)
    cat=category or old['path'].split('/')[-2]
    parent={'floor':floor,'architecture':arch,'support':support}[cat]
    c=bpy.data.collections.new(original.name.replace('资产包','扩展资产包'))
    parent.children.link(c)
    for o in original.objects:
        q=o.copy();q.data=o.data.copy() if o.type=='MESH' else None
        c.objects.link(q);q.location+=Vector((dx,dy,0))
    catalog.append({'package_id':'ENV-BATTLE-LCORRIDOR-'+new_slug.upper(),
                    'path':'component_packages_v002/'+cat+'/'+new_slug,
                    'object_count':len([o for o in c.objects if o.type=='MESH']),
                    '_collection':c.name})
    return c

# Existing 28 tiles plus 9 in the new north row and 5 in the new west leg
# column = 42. The centre tile is floor, never an obstructing wall.
for x in range(9):
    clone_pack(f'tile_r06_c{x:02d}',f'tile_r07_c{x:02d}',0,5,'floor')
for y in range(-5,0):
    row=y+5;template=f'tile_r{row:02d}_c07'
    clone_pack(template,f'tile_r{row:02d}_c06',-5,0,'floor')

# Replace each bespoke top skin with one of the two approved shared tile art
# variants, retaining the 0.30 m structural brick and attached floor details.
for e in catalog:
    if '/floor/' not in e['path']:continue
    slug=e['path'].split('/')[-1];col=pack(slug) if '_collection' not in e else bpy.data.collections[e['_collection']]
    for ob in list(col.objects):
        if ob.name.startswith(('深蓝分缝面板','中心可维护面板')):
            bpy.data.objects.remove(ob,do_unlink=True)
    base=next(o for o in col.objects if o.name.startswith('5米结构地砖'))
    cx,cy=base.location.x,base.location.y
    x=int((cx-2.5)/5);y=int((cy-2.5)/5)
    meshes=tiles_A if (x+y)%2==0 else tiles_B
    for j,me in enumerate(meshes):
        ob=bpy.data.objects.new(f'通用地砖表层_{j}',me);col.objects.link(ob)
        ob.location=(cx,cy,.015)
    e['_shared_component_id']='ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01' if meshes is tiles_A else 'ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02'

# A standard full-height wall is reused as the structural mesh in every visible
# perimeter segment. Existing decorative rails and panels remain attached.
for e in catalog:
    if '/architecture/' not in e['path']:continue
    slug=e['path'].split('/')[-1]
    if not slug.startswith(('wall_x_','wall_y_')):continue
    col=pack(slug)
    for ob in col.objects:
        if not ob.name.startswith('标准5米墙体') or ob.dimensions.z<10:continue
        ob.data=wall_mesh
        ob.location.z=0
        ob.rotation_euler.z=math.pi/2 if slug.startswith('wall_y_') else 0
        e['_shared_component_id']='ENV-BATTLE-COMMON-WALL-STANDARD-5M'

# Extend the four exposed perimeter runs with the same five-metre wall module.
clone_pack('wall_y_25_00','wall_y_35_00',0,10,'architecture')
clone_pack('wall_y_30_45','wall_y_35_45',0,5,'architecture')
clone_pack('wall_x_40_front','wall_x_30_south',-10,0,'architecture')
clone_pack('high_pipe_east_06','high_pipe_east_07',0,5,'support')
for slug in ('wall_y_35_00','wall_y_35_45','wall_x_30_south'):
    e=catalog_entry(slug);col=bpy.data.collections[e['_collection']]
    for ob in col.objects:
        if ob.name.startswith('标准5米墙体'):
            ob.data=wall_mesh;ob.location.z=0
            ob.rotation_euler.z=math.pi/2 if slug.startswith('wall_y_') else 0
    e['_shared_component_id']='ENV-BATTLE-COMMON-WALL-STANDARD-5M'

# Add the new grid cell handles to the hidden authoring layer.
for x,y in [(x,2) for x in range(9)]+[(6,y) for y in range(-5,0)]:
    g=bpy.data.objects.new(f'砖块定位_R{y+5:02d}_C{x:02d}',None)
    source.objects.link(g);g.location=(x*5+2.5,y*5+2.5,0)
    g.empty_display_type='CUBE';g.empty_display_size=2.5

# Reframe the expanded footprint. No display camera or light belongs to output.
from mathutils import Vector
cam=bpy.data.objects['参考相机_全景'];cam.location=(-42,-79,72)
cam.rotation_euler=(Vector((22,-3,7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=75
top=bpy.data.objects['参考相机_俯视'];top.location=(22,-5,85)
top.rotation_euler=(Vector((22,-5,0))-top.location).to_track_quat('-Z','Y').to_euler();top.data.ortho_scale=65
for name in ('参考相机_补图区块A',):
    c=bpy.data.objects[name];c.location.y+=5
    c.rotation_euler=(Vector((30,13,2))-c.location).to_track_quat('-Z','Y').to_euler()

# Update source-only package manifests from actual Blender object ownership.
for e in catalog:
    slug=e['path'].split('/')[-1]
    p=manifest_path(e)
    if os.path.exists(p):
        with open(p) as f:rec=json.load(f)
        col=bpy.data.collections[rec['collection']]
    else:
        col=bpy.data.collections[e['_collection']]
        rec={'package_id':e['package_id'],'slug':slug,'name_zh':col.name,'category':e['path'].split('/')[-2],
             'material_roles':list(M),'exported':False,'collision':'pending Godot assembly'}
    rec['version']='v003';rec['source_blend']='l_corridor_room_type_v003.blend'
    rec['collection']=col.name;rec['slug']=slug;rec['package_id']=e['package_id']
    rec['objects']=[{'name':o.name,'location_m':[round(v,4) for v in o.location],
                     'dimensions_m':[round(v,4) for v in o.dimensions]} for o in col.objects if o.type=='MESH']
    if '_shared_component_id' in e:rec['shared_component_asset_id']=e['_shared_component_id']
    e['object_count']=len(rec['objects'])
    os.makedirs(os.path.dirname(p),exist_ok=True)
    with open(p,'w') as f:json.dump(rec,f,ensure_ascii=False,indent=2)
    e['path']=e['path'].replace('component_packages_v002','component_packages_v003')
    e.pop('_collection',None);e.pop('_shared_component_id',None)
with open(OUT+'/component_packages_v003/catalog.json','w') as f:json.dump(catalog,f,ensure_ascii=False,indent=2)
with open(OUT+'/component_packages_v003/tree.txt','w') as f:f.write('\n'.join(e['path'] for e in catalog)+'\n')

room['version']='v003';room['source_blend']='l_corridor_room_type_v003.blend'
room['dimensions_m']={'outer_bounds':[45,40],'horizontal_arm':[45,15],'south_arm_extension':[15,25]}
room['corridor_width_m']=15;room['tiles_per_cross_section']=3;room['tile_count']=42
room['door_centers_m']=[[0,7.5],[7.5,15],[37.5,15],[37.5,-25]]
room['door_opening_m']=[2.2,2.5]
room['reserved_door_slots']=[{'center_m':[0,7.5],'normal':'west','width_m':5},
                             {'center_m':[7.5,15],'normal':'north','width_m':5},
                             {'center_m':[37.5,15],'normal':'north','width_m':5},
                             {'center_m':[37.5,-25],'normal':'south','width_m':5}]
room['shared_door_wall_component_id']='ENV-BATTLE-COMMON-WALL-DOOR-5M'
room['shared_door_component_id']='ENV-BATTLE-COMMON-DOOR-5M'
room['shared_standard_wall_component_id']='ENV-BATTLE-COMMON-WALL-STANDARD-5M'
room['shared_floor_tile_component_ids']=['ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01','ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02']
room['door_geometry_in_source']=False
room['package_count']=len(catalog)
room['art_revision']='15 m wide three-tile corridor; shared wall/floor component art; 5 m door-wall bays left empty; facilities moved to perimeter'
with open(OUT+'/room_type_manifest.json','w') as f:json.dump(room,f,ensure_ascii=False,indent=2)

bpy.context.scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/l_corridor_room_type_v003.blend')
print(json.dumps({'blend':bpy.data.filepath,'packages':len(catalog),'tiles':42,
                  'door_slots':len(room['reserved_door_slots'])},ensure_ascii=False))
