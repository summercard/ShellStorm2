"""Finish isolated Blender component files, independently reopen and audit every file.
Run after decompose_boss_room_components_v001.py. No room source/runtime writes.
"""
import bpy, json, hashlib, math, importlib.util, sys
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/environments/tower_zones/expedition/source/common_components/v001'
MASTER=BASE/'expedition_boss_room_components_source_v001.blend'
SOURCE=ROOT/'assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002/Boss房种类_故障数据库_50x40m_v002.blend'
PAL=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
VALIDATOR=Path.home()/'.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py'

def dump(p,d):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_bytes((json.dumps(d,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))

def hashfile(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p): return p.relative_to(ROOT).as_posix()
def identity(m): return max(abs(m[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-6

def camera_light(scene, bounds):
    lo,hi=map(Vector,bounds); center=(lo+hi)*.5; size=hi-lo
    extent=max(size.length,2.0)
    c=bpy.data.collections.new('90_Preview_'+scene.name); scene.collection.children.link(c)
    data=bpy.data.cameras.new('Camera_'+scene.name); data.type='ORTHO'; data.ortho_scale=extent*1.25
    cam=bpy.data.objects.new('Camera_'+scene.name,data); c.objects.link(cam)
    cam.location=center+Vector((.8,-1.4,.9)).normalized()*extent*2
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler(); scene.camera=cam
    for n,offset,power in [('Key',(1,-2,3),170),('Fill',(-2,-1,1),100),('Rim',(1,2,2),130)]:
        ld=bpy.data.lights.new(n+'_'+scene.name,'AREA'); ld.energy=power*extent*extent; ld.size=extent
        ob=bpy.data.objects.new(n+'_'+scene.name,ld); c.objects.link(ob)
        ob.location=center+Vector(offset)*extent*.8
        ob.rotation_euler=(center-ob.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=8; scene.cycles.use_denoising=False
    scene.render.threads_mode='FIXED'; scene.render.threads=2
    scene.render.resolution_x=800; scene.render.resolution_y=650; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'; scene.use_nodes=False
    scene.view_settings.view_transform='AgX'; scene.view_settings.exposure=.5
    return c

catalog=json.loads((BASE/'component_catalog.json').read_text('utf-8'))
source_hash=hashfile(SOURCE); assert source_hash==catalog['source_room_type_sha256']
source_rows=json.loads((SOURCE.parent/'component_packages/catalog.json').read_text('utf-8'))['packages']
byid={r['package_id']:r for r in source_rows}
bpy.ops.wm.open_mainfile(filepath=str(MASTER)); bpy.context.preferences.filepaths.save_version=0
master_scene=bpy.context.scene
# Source originals were not modified; offsets are recorded for reconstruction only.
for image in bpy.data.images:
    if image.source=='FILE': image.filepath=str(PAL)
world=bpy.data.worlds.new('Component_Studio'); world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs['Color'].default_value=(.30,.32,.36,1); bg.inputs['Strength'].default_value=.45
scenes=[]
for row in catalog['packages']:
    slug=row['source_package_id']; original=byid[slug]
    out=bpy.data.collections[row['collection']]; edit=bpy.data.collections[row['editable_collection']]
    meshes=[o for o in out.all_objects if o.type=='MESH']
    assert meshes
    # Stable AssetID deliberately excludes the room-source version.
    row['component_id']='ENV-EXPEDITION-BOSSROOM-'+slug.upper().replace('_','-')
    row['asset_id']=row['component_id']; row['category']=original['category']; row['name_zh']=original['name_zh']
    row['ledger_registration']='pending; component source only, not formal runtime asset'
    row['source_world_origin_m']=original['world_origin_m']
    row['origin_contract']='bottom-center of component bounds; source placement only in traceability metadata'
    row['front_axis_coordinate_system']='Blender Z-up'
    if slug.startswith('east_'): row['front_axis']='-X'
    if slug.startswith('west_'): row['front_axis']='+X'
    row['godot_front_axis']={'-Y':'+Z','+Y':'-Z','-X':'-X','+X':'+X','+Z':'+Y'}[row['front_axis']]
    row['allowed_rotations_blender_z_deg']=row['allowed_rotations_y_deg']
    row['component_library_blend']=rel(MASTER)
    path=BASE/'component_packages'/slug/(slug+'.blend')
    row['component_blend']=rel(path); row['objects']=[o.name for o in meshes]
    row['preview_render_status']='camera_ready; representative renders only'
    for ob in out.all_objects:
        ob['asset_id']=row['asset_id']
    s=bpy.data.scenes.new('Component_'+slug); s.world=world
    er=bpy.data.collections.new('01_制作组件_'+slug); s.collection.children.link(er); er.children.link(edit)
    ort=bpy.data.collections.new('02_游戏输出_'+slug); s.collection.children.link(ort); ort.children.link(out)
    s.view_layers[0].layer_collection.children[er.name].exclude=True
    s['asset_id']=row['asset_id']; s['room_owned_geometry']=False; s['runtime_connected']=False
    camera_light(s,(row['bounds_lo_m'],row['bounds_hi_m']))
    s.render.filepath=str(BASE/'renders'/(slug+'.png'))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D': area.spaces.active.shading.type='SOLID'
    bpy.data.libraries.write(str(path),{s},path_remap='RELATIVE_ALL',fake_user=False,compress=True)
    row['component_file_sha256']=hashfile(path)
    dump(path.parent/'asset_manifest.json',row); scenes.append((row,s,out))
    print('ISOLATED_FILE_WRITTEN',slug,flush=True)
# Master opens on a separated gallery of real instances, never overlapped copies.
gallery=bpy.data.scenes.new('00_Component_Gallery'); gallery.world=world
xs=0; ys=0; rowdepth=0; points=[]
for i,(row,s,out) in enumerate(scenes):
    size=Vector(row['bounds_size_m']); lo=Vector(row['bounds_lo_m']); hi=Vector(row['bounds_hi_m'])
    if xs+size.x>90 and xs>0: xs=0; ys+=rowdepth+4; rowdepth=0
    inst=bpy.data.objects.new('Preview_'+row['source_package_id'],None); gallery.collection.objects.link(inst)
    inst.instance_type='COLLECTION'; inst.instance_collection=out
    inst.location=(xs-lo.x,ys-lo.y,0); points.extend([lo+inst.location,hi+inst.location])
    xs+=size.x+4; rowdepth=max(rowdepth,size.y)
low=[min(p[k] for p in points) for k in range(3)]; high=[max(p[k] for p in points) for k in range(3)]
camera_light(gallery,(low,high)); bpy.context.window.scene=gallery
# Remove the old overlapping presentation scene; components live in isolated scenes.
bpy.data.scenes.remove(master_scene)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=Vector([(low[k]+high[k])/2 for k in range(3)])
            area.spaces.active.region_3d.view_distance=max(high[0]-low[0],high[1]-low[1])
bpy.ops.wm.save_as_mainfile(filepath=str(MASTER))
catalog['independent_blend_count']=len(scenes); catalog['ledger_registration']='pending'
catalog['presentation']='separated collection-instance gallery; isolated component scenes with cameras'
dump(BASE/'component_catalog.json',catalog)
# Reopen EVERY independent .blend, not merely the mother library.
spec=importlib.util.spec_from_file_location('standard_validator',VALIDATOR); validator=importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)
reports=[]
for row in catalog['packages']:
    path=ROOT/row['component_blend']; bpy.ops.wm.open_mainfile(filepath=str(path)); bpy.context.view_layer.update()
    expected=bpy.data.scenes['Component_'+row['source_package_id']]; bpy.context.window.scene=expected
    c=bpy.data.collections[row['collection']]; root=bpy.data.objects[row['root_object']]; meshes=[o for o in c.all_objects if o.type=='MESH']
    checks={
        'exact_output_object_set':{o.name for o in meshes}==set(row['objects']),
        'one_component_scene':len(bpy.data.scenes)==1,
        'root_identity':root.parent is None and identity(root.matrix_local),
        'mesh_identity':all(o.parent==root and identity(o.matrix_local) and identity(o.matrix_parent_inverse) for o in meshes),
        'collection_offset_zero':c.instance_offset.length<1e-8,
        'nonempty':bool(meshes),
        'output_membership_unique':all(len(o.users_collection)==1 for o in meshes),
        'camera_ready':expected.camera is not None,
        'not_room_owned':all(not o.get('room_owned_geometry',False) for o in meshes),
    }
    ps=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=[min(p[k] for p in ps) for k in range(3)]; hi=[max(p[k] for p in ps) for k in range(3)]
    checks['bounds_match']=max(abs(a-b) for a,b in zip(lo+hi,row['bounds_lo_m']+row['bounds_hi_m']))<1e-5
    checks['bottom_zero']=abs(lo[2])<1e-5
    # Reuse the standard full material/UV validator without a subprocess per file.
    sys.argv=['validate','--','--all-meshes','--max-materials','4','--shared-palette',str(PAL),'--json',str(path.parent/'validation_game_prop.json')]
    import contextlib, io
    with contextlib.redirect_stdout(io.StringIO()):
        try: validator.main()
        except SystemExit as e: checks['standard_material_uv']=e.code==0
    r={'component_id':row['component_id'],'file':rel(path),'checks':checks,'passed':all(checks.values()),'output_mesh_count':len(meshes)}
    dump(path.parent/'component_probe.json',r); reports.append(r)
    assert r['passed'],r
    print('ISOLATED_FILE_PASS',row['source_package_id'],flush=True)
assert hashfile(SOURCE)==source_hash
summary={'passed':all(r['passed'] for r in reports),'independent_blend_count':len(reports),'output_mesh_count':sum(r['output_mesh_count'] for r in reports),'source_hash_unchanged':True,'source_sha256':source_hash,'files':reports}
dump(BASE/'independent_files_validation.json',summary)
print('ALL_INDEPENDENT_COMPONENTS_PASS',len(reports),flush=True)
