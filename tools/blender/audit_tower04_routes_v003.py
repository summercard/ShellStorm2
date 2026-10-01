"""Reopen-only scoped audit and optional same-camera renders; never save Blend."""
import ast
import bpy
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
F=Path(bpy.data.filepath).parent
sys.path.insert(0,str(Path(__file__).parent))
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely.geometry import Polygon,LineString,box,Point
from shapely.ops import unary_union
import tower04_routes_v003 as P
cat=json.loads((F/'catalog.json').read_text(encoding='utf8'))
baseline=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'))
NAMES=cat['material_roles']; MATS=[bpy.data.materials[n] for n in NAMES]
path=R/'tools/blender/refine_tower04_routes_v003.py'
defs=[n for n in ast.parse(path.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in ('sha','floats','signature','material_signature')]
exec(compile(ast.Module(body=defs,type_ignores=[]),'scoped-signature','exec'),globals())
bpy.context.view_layer.update()
now={name:signature(bpy.data.objects[name]) for name in baseline['objects']}
errors=[]
if now!=baseline['objects']: errors.append('locked_object_signature')
if material_signature()!=baseline['materials']: errors.append('material_signature')
for path,h in baseline['files'].items():
    if hashlib.sha256((R/path).read_bytes()).hexdigest()!=h: errors.append('locked_file:'+path)
game=bpy.data.collections['02_游戏输出_独立资产包_v003']
slow=next(p for p in cat['packages'] if p['slug']=='slow_lane')
ob=bpy.data.objects[slow['root_object']]
polys=[]
for f in ob.data.polygons:
    q=[ob.matrix_world@ob.data.vertices[v].co for v in f.vertices]
    if all(abs(v.z-25.058)<.0001 for v in q):
        g=Polygon([(v.x,v.y) for v in q])
        if g.is_valid and g.area>1e-6: polys.append(g)
actual=unary_union(polys)
resolved=json.loads((F/'route_centerlines.json').read_text(encoding='utf8'))
expected=unary_union([LineString(e['points']).buffer(1,quad_segs=6) for e in resolved['routes']])
if actual.symmetric_difference(expected).area>.02: errors.append('saved_route_surface')
obstacles=[]
for p in cat['packages']:
    slug=p['slug']
    if p['category']=='facilities' and slug!='court_sculpture':
        # Glass pavilion has a rotated true footprint, not its entire world AABB.
        if slug=='glass_pavilion': g=Polygon(P.OLD.PAVILION)
        else: g=box(*p['bounds_min'][:2],*p['bounds_max'][:2])
    elif slug.startswith('canopy_column_'):
        c=p['world_position']; g=box(c[0]-.45,c[1]-.45,c[0]+.45,c[1]+.45)
    elif slug=='service_screen': g=box(*p['bounds_min'][:2],*p['bounds_max'][:2])
    else: continue
    area=actual.intersection(g).area
    if area>.005: obstacles.append(dict(slug=slug,overlap_m2=area))
if obstacles: errors.append('route_hits_locked_obstacle')
raw=[o.matrix_world@v.co for o in game.all_objects if o.type=='MESH' for v in o.data.vertices]
mn=[min(v[j] for v in raw) for j in range(3)]; mx=[max(v[j] for v in raw) for j in range(3)]
if abs(mx[0]-mn[0]-150)>.003 or abs(mx[1]-mn[1]-50)>.003: errors.append('footprint_150x50')
report=dict(passed=not errors,version='v003',stage='reopened_saved_blend',errors=errors,locked_object_count=len(now),locked_match=now==baseline['objects'],old_signatures=baseline['objects'],new_signatures=now,material_signature_match=material_signature()==baseline['materials'],material_count=len(bpy.data.materials),saved_route_connected=actual.geom_type=='Polygon',saved_route_loop_holes=len(actual.interiors) if actual.geom_type=='Polygon' else None,route_symmetric_difference_m2=actual.symmetric_difference(expected).area,obstacle_overlaps=obstacles,footprint_m=[mx[j]-mn[j] for j in (0,1)],new_materials_created=0,mipmap_changes=0)
(F/'qa/reference_plan_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k not in ('old_signatures','new_signatures')},ensure_ascii=False,indent=2),flush=True)
if '--render' in sys.argv or '--plan-preview' in sys.argv:
    sc=bpy.context.scene
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
        for d in prefs.devices: d.use=d.type!='CPU'
        sc.cycles.device='GPU'
    except Exception: pass
    if '--render' in sys.argv:
        names=[('CAM_参考全景','01_塔4_参考全景.png'),('CAM_俯视轮廓','02_塔4_俯视轮廓.png'),('CAM_天台花园','03_塔4_天台花园.png'),('CAM_左翼转折','04_塔4_椭圆左翼.png'),('CAM_玻璃亭与格构','05_塔4_玻璃亭与遮阳棚.png'),('CAM_设备节点','06_塔4_近景设备与节点.png')]
        for cam,file in names:
            sc.camera=bpy.data.objects[cam]; sc.render.resolution_x=sc.camera['resolution_x']; sc.render.resolution_y=sc.camera['resolution_y']; sc.render.filepath=str(F/'previews'/file)
            bpy.ops.render.render(write_still=True); print('ROUTE_RENDER',file,flush=True)
    for o in game.all_objects:
        slug=o.get('package_id','').split('/')[-1]
        if slug=='leaf_canopy' or slug.startswith(('vegetation_','court_vegetation_','plaza_green_','canopy_green_')): o.hide_render=True
    sc.camera=bpy.data.objects['CAM_俯视轮廓']; sc.render.resolution_x=1920; sc.render.resolution_y=760; sc.render.filepath=str(F/'qa/07_本步路线与绿化平面.png')
    bpy.ops.render.render(write_still=True)
raise SystemExit(0 if not errors else 1)
