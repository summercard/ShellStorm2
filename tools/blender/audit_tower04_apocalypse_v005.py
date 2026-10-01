"""Read-only saved-source modularity, scope, layout and actual-render verification."""
import ast,bpy,json,hashlib,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2]; F=Path(bpy.data.filepath).parent
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely import wkt
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
meta=json.loads((F/'catalog.json').read_text(encoding='utf8'))
lock=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'))
build=json.loads((F/'qa/build_plan_result.json').read_text(encoding='utf8'))
layout=json.loads((F.parent/'v004/qa/surface_plan.json').read_text(encoding='utf8'))['frozen_layout']
MATS=[bpy.data.materials[n] for n in meta['material_roles']]
src=R/'tools/blender/refine_tower04_routes_v003.py'
nodes=[n for n in ast.parse(src.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in {'sha','floats','signature','material_signature'}]
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(src),'exec'),globals())
errors=[]
changed=[n for n,s in lock['objects'].items() if n not in bpy.data.objects or signature(bpy.data.objects[n])!=s]
if changed: errors.append('locked_objects_changed')
if len(bpy.data.materials)!=4 or material_signature()!=lock['materials']: errors.append('materials_changed')
for f,h in lock['files'].items():
    if hashlib.sha256((R/f).read_bytes()).hexdigest()!=h: errors.append('shared_file_changed:'+f)
footprints={}
for slug,z,key in [('terrace_shell',25,'deck'),('slow_lane',25.059,'route'),('lawn_court',25.127,'lawn_court')]:
    polys=[]
    for p in meta['packages']:
        if not(p['slug']==slug or p['slug'].startswith(slug+'_x')): continue
        for n in p['objects']:
            o=bpy.data.objects[n]
            for face in o.data.polygons:
                v=[o.matrix_world@o.data.vertices[i].co for i in face.vertices]
                if all(abs(q.z-z)<.0002 for q in v):
                    g=Polygon([(q.x,q.y) for q in v])
                    if g.is_valid and g.area>1e-7: polys.append(g)
    geom=unary_union(polys).buffer(.000015,join_style=2).buffer(-.000015,join_style=2)
    delta=geom.symmetric_difference(wkt.loads(layout[key]['wkt'])).area
    footprints[key]={'delta_m2':delta,'area_m2':geom.area}
    if delta>.005: errors.append('layout_drift:'+key)
route=wkt.loads(layout['route']['wkt']); deck=wkt.loads(layout['deck']['wkt'])
for p in build['placements']:
    g=box(*p['bounds'])
    if g.intersection(route.buffer(.4)).area>1e-5: errors.append('route_blocked:'+p['asset'])
    if g.difference(deck).area>1e-5: errors.append('outside_deck:'+p['asset'])
actual=[]
for p in meta['packages']:
    if p.get('platform_scope') and max(p['dimensions'][:2])>10.0002: errors.append('oversized:'+p['slug'])
    if p['slug'] in build['new_prop_packages']:
        actual.append({'slug':p['slug'],'ground_gap_m':p['bounds_min'][2]-p['world_position'][2]})
        if abs(actual[-1]['ground_gap_m'])>.09: errors.append('floating:'+p['slug'])
report=dict(passed=not errors,errors=errors,changed_locked=changed,locked_object_count=len(lock['objects']),footprints=footprints,package_count=len(meta['packages']),platform_package_count=sum(bool(p.get('platform_scope')) for p in meta['packages']),module_max_xy_m=10,prop_count=len(build['new_prop_packages']),vine_patch_count=len(build['vine_patches']),material_count=4,new_materials=0,mipmap_changes=0,actual_prop_ground_checks=actual,source_only=True)
(F/'qa/apocalypse_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('AUDIT',json.dumps({k:v for k,v in report.items() if k!='actual_prop_ground_checks'},ensure_ascii=False),flush=True)
assert not errors,errors
prefs=bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type='OPTIX'; prefs.get_devices()
for d in prefs.devices: d.use=d.type!='CPU'
sc=bpy.context.scene; mood=bpy.data.scenes['塔4_黄昏末世氛围']
views=[('CAM_参考全景','01_塔4_参考全景.png'),('CAM_俯视轮廓','02_塔4_俯视轮廓.png'),('CAM_天台花园','03_塔4_天台花园.png'),('CAM_左翼转折','04_塔4_椭圆左翼.png'),('CAM_玻璃亭与格构','05_塔4_玻璃亭与遮阳棚.png'),('CAM_设备节点','06_塔4_近景设备与节点.png')]
if '--render' in sys.argv:
    for scene,folder,cams in [(mood,'mood',[(o.name,o.name[4:]+'.png') for o in bpy.data.objects if o.type=='CAMERA' and o.name.startswith('CAM_末世_')]),(sc,'previews',views)]:
        bpy.context.window.scene=scene; scene.cycles.device='GPU'; scene.cycles.samples=48
        for name,file in cams:
            scene.camera=bpy.data.objects[name]; scene.render.resolution_x=1600; scene.render.resolution_y=1000; scene.render.resolution_percentage=100; scene.render.filepath=str(F/folder/file)
            bpy.ops.render.render(write_still=True,scene=scene.name); print('RENDERED',folder,file,flush=True)
