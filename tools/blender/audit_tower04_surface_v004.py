"""Reopen Tower04 v004, measure real meshes, render matching close-range QA."""
import ast
import bpy
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely.geometry import Polygon,Point
from shapely.ops import unary_union
from shapely import wkt
F=Path(bpy.data.filepath).parent
meta=json.loads((F/'catalog.json').read_text(encoding='utf8'))
plan=json.loads((F/'qa/surface_plan.json').read_text(encoding='utf8'))
locked=json.loads((F/'qa/locked_before.json').read_text(encoding='utf8'))
def defs(file,names):
    p=R/'tools/blender'/file
    ns=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in names]
    exec(compile(ast.Module(body=ns,type_ignores=[]),str(p),'exec'),globals())
defs('refine_tower04_routes_v003.py',{'sha','floats','signature','material_signature'})
MATS=[bpy.data.materials[n] for n in meta['material_roles']]
def face_shape(slug,z):
    item=next(p for p in meta['packages'] if p['slug']==slug); tris=[]
    for name in item['objects']:
        o=bpy.data.objects[name]
        for f in o.data.polygons:
            v=[o.matrix_world@o.data.vertices[i].co for i in f.vertices]
            if all(abs(q.z-z)<.0002 for q in v):
                g=Polygon([(q.x,q.y) for q in v])
                if g.is_valid and g.area>1e-7: tris.append(g)
    # Blender float32 round-trip at independently triangulated segment seams.
    # Weld only 0.015mm cracks for topology; area check still uses 0.005m² limit.
    return unary_union(tris).buffer(.000015,join_style=2).buffer(-.000015,join_style=2)
after={n:signature(bpy.data.objects[n]) for n in locked['objects']}
diff=[n for n,h in locked['objects'].items() if after[n]!=h]
errors=[]
if diff: errors.append('locked_objects_changed')
if material_signature()!=locked['materials'] or len(bpy.data.materials)!=4: errors.append('material_change')
for file,h in locked['files'].items():
    if hashlib.sha256((R/file).read_bytes()).hexdigest()!=h: errors.append('file_changed:'+file)
route=face_shape('slow_lane',25.059); lawn=face_shape('lawn_court',25.127); deck=face_shape('terrace_shell',25)
footprints={}
for s,g in dict(route=route,lawn_court=lawn,deck=deck).items():
    old=wkt.loads(plan['frozen_layout'][s]['wkt']); delta=g.symmetric_difference(old).area
    footprints[s]=dict(delta_m2=delta,old_area_m2=old.area,new_area_m2=g.area)
    if delta>.005: errors.append('layout_changed:'+s)
if route.geom_type!='Polygon' or len(route.interiors)!=2: errors.append('route_topology')
if plan['track_surface_gap_m2']>.001 or plan['track_surface_overlap_m2']>.001: errors.append('track_gap_or_overlap')
item=next(p for p in meta['packages'] if p['slug']=='slow_lane'); cells=set(); color_areas={}
for name in item['objects']:
    o=bpy.data.objects[name]; uv=o.data.uv_layers.active
    for f in o.data.polygons:
        v=[o.matrix_world@o.data.vertices[i].co for i in f.vertices]
        if not all(abs(q.z-25.059)<.0002 for q in v): continue
        cx=sum(uv.data[i].uv.x for i in f.loop_indices)/len(f.loop_indices); cy=sum(uv.data[i].uv.y for i in f.loop_indices)/len(f.loop_indices)
        c=(int(cx*10),int((1-cy)*10)); cells.add(c); color_areas[str(c)]=color_areas.get(str(c),0)+Polygon([(q.x,q.y) for q in v]).area
if cells!={(7,1),(8,1)}: errors.append('two_adjacent_colors')
tiles=[p for p in meta['packages'] if p['slug'].startswith('tile_r')]
if len(tiles)!=plan['tile_count'] or len({(p['tile_row'],p['tile_column'],p['tile_fragment']) for p in tiles})!=len(tiles): errors.append('tile_indexing')
for p in tiles:
    if abs(p['bounds_max'][2]-25.055)>.0001: errors.append('tile_height:'+p['slug'])
    if len(p['objects'])!=1 or p['dependencies']!=['tower_04/roof_paving']: errors.append('tile_ownership:'+p['slug'])
result=dict(passed=not errors,errors=errors,version='v004',locked_object_count=len(after),locked_match=not diff,old_signatures=locked['objects'],new_signatures=after,material_signature_before=locked['materials'],material_signature_after=material_signature(),footprints=footprints,track_colors=sorted(cells),track_color_areas_m2=color_areas,route_components=1 if route.geom_type=='Polygon' else len(route.geoms),route_loop_count=len(route.interiors) if route.geom_type=='Polygon' else None,tile_count=len(tiles),new_materials=0,mipmap_changes=0,close_range_cameras=4,topology_weld_tolerance_m=.000015,runtime='not_exported')
(F/'qa/surface_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print('TOWER04_SURFACE_AUDIT',json.dumps({k:v for k,v in result.items() if k not in ('old_signatures','new_signatures')},ensure_ascii=False),flush=True)
assert not errors,errors
sc=bpy.context.scene
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    if any(d.type!='CPU' for d in prefs.devices): sc.cycles.device='GPU'
except Exception: pass
if '--render' in sys.argv:
    views=[('CAM_参考全景','01_塔4_参考全景.png'),('CAM_俯视轮廓','02_塔4_俯视轮廓.png'),('CAM_天台花园','03_塔4_天台花园.png'),('CAM_左翼转折','04_塔4_椭圆左翼.png'),('CAM_玻璃亭与格构','05_塔4_玻璃亭与遮阳棚.png'),('CAM_设备节点','06_塔4_近景设备与节点.png')]
    for name,file in views:
        sc.camera=bpy.data.objects[name]; sc.render.resolution_x=sc.camera['resolution_x']; sc.render.resolution_y=sc.camera['resolution_y']; sc.render.filepath=str(F/'previews'/file)
        bpy.ops.render.render(write_still=True); print('SURFACE_PREVIEW',file,flush=True)
    for name in ('CAM_近景_跑道压边','CAM_近景_草坪设施','CAM_近景_地板接缝','CAM_近景_庭院花池'):
        sc.camera=bpy.data.objects[name]; sc.render.resolution_x=1600; sc.render.resolution_y=1000; sc.cycles.samples=64; sc.render.filepath=str(F/'qa/closeups'/(name[4:]+'.png'))
        bpy.ops.render.render(write_still=True); print('CLOSEUP_PREVIEW',name,flush=True)
if '--before' in sys.argv:
    cameras=[(o.name,tuple(o.location),tuple(o.rotation_euler),o.data.lens) for o in bpy.data.objects if o.type=='CAMERA' and o.name.startswith('CAM_近景_')]
    source=R/'assets/art/environments/open_world/source/tower_04/v003/塔4_曲线天台商场_150x50m_v003.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source)); sc=bpy.context.scene; sc.cycles.device='GPU'; sc.cycles.samples=64
    for name,pos,rot,lens in cameras:
        c=bpy.data.cameras.new(name); c.lens=lens; c.clip_start=.1; c.clip_end=300; ob=bpy.data.objects.new(name,c); sc.collection.objects.link(ob); ob.location=pos; ob.rotation_euler=rot; sc.camera=ob
        sc.render.resolution_x=1600; sc.render.resolution_y=1000; sc.render.filepath=str(F/'qa/closeups'/('修改前_'+name[4:]+'.png'))
        bpy.ops.render.render(write_still=True); print('BEFORE_CLOSEUP',name,flush=True)
# Audit/render never saves or changes the delivered source.
