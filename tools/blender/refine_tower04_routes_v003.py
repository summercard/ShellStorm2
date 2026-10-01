"""Scoped Tower04 roof/route/planting edit. Never execute the whole-scene builder.

Usage: blender --background --factory-startup --python-exit-code 1 --python
this_file -- --geometry-libs <Shapely site-packages> [--no-render]
"""
import ast
import bpy
import hashlib
import json
import math
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
if '--geometry-libs' in sys.argv:
    sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union, substring
from shapely.affinity import translate
from shapely import constrained_delaunay_triangles
import tower04_routes_v003 as P

OLD=R/'assets/art/environments/open_world/source/tower_04/v002'
OUT=OLD.parent/'v003'
BLEND=OUT/'塔4_曲线天台商场_150x50m_v003.blend'
PREVIOUS=OLD/'塔4_曲线天台商场_150x50m_v002.blend'
ASSET='ENV-OPENWORLD-TOWER04'
PALETTE=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
DONOR=R/'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
reference=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-fdc635e4-17b1-4715-b4c8-0df66d8ecd4a.png')
for d in ('qa','previews','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
if BLEND.exists():
    assert '--draft-sha' in sys.argv and hashlib.sha256(BLEND.read_bytes()).hexdigest()==sys.argv[sys.argv.index('--draft-sha')+1], 'Existing draft changed; use a new revision'
shutil.copy2(reference,OUT/'references/用户参考_本步天台流线.png')
oldmeta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))
editable={p['slug'] for p in oldmeta['packages'] if p['category']=='garden'}|{'terrace_shell','terrace_rail','roof_paving','slow_lane','main_walk'}
locked_files={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (PREVIOUS,DONOR,PALETTE,Path(str(PALETTE)+'.import'))}

# STAGE A: judgement from annotated floor paths; buildings are fixed anchors.
limit=box(-74.95,-24.95,74.95,24.95)
deck=unary_union([Polygon(P.OLD.DECK)]+[Polygon(p) for p in (P.REAR_PATCH,P.FRONT_PATCH,P.PLAZA_PATCH,P.EAST_PATCH)]).intersection(limit)
assert deck.geom_type=='Polygon' and deck.is_valid and not deck.interiors
obstacles=[]
for item in oldmeta['packages']:
    slug=item['slug']
    if item['category']=='facilities' and slug!='court_sculpture':
        g=Polygon(P.OLD.PAVILION) if slug=='glass_pavilion' else box(*item['bounds_min'][:2],*item['bounds_max'][:2])
    elif slug.startswith('canopy_column_'):
        x,y=item['world_position'][:2]; g=box(x-.45,y-.45,x+.45,y+.45)
    elif slug=='service_screen': g=box(*item['bounds_min'][:2],*item['bounds_max'][:2])
    else: continue
    obstacles.append((slug,g))
def avoid(line,inflated):
    """Replace only obstructed local intervals by the shorter safe curb arc."""
    hit=line.intersection(inflated)
    segments=[hit] if hit.geom_type=='LineString' else [q for q in getattr(hit,'geoms',[]) if q.geom_type=='LineString']
    ranges=sorted((line.project(Point(q.coords[0])),line.project(Point(q.coords[-1]))) for q in segments if q.length>.001)
    if not ranges: return line
    out=[]; last=0
    ring=LineString(inflated.exterior.coords)
    def wrapped(a,b):
        if a<=b: return list(substring(ring,a,b).coords)
        return list(substring(ring,a,ring.length).coords)+list(substring(ring,0,b).coords)[1:]
    for aa,bb in ranges:
        lo,hi=sorted((aa,bb))
        assert lo>.0001 and hi<line.length-.0001, 'Named route node is obstructed: adjust anchor first'
        prefix=substring(line,last,lo)
        out.extend(list(prefix.coords))
        a=ring.project(line.interpolate(lo)); b=ring.project(line.interpolate(hi))
        candidates=[wrapped(a,b),list(reversed(wrapped(b,a)))]
        safe=[q for q in candidates if LineString(q).buffer(1.01,quad_segs=4).difference(deck).area<.02]
        assert safe, 'No roof-contained local bypass'
        out.extend(min(safe,key=lambda q:LineString(q).length)[1:]); last=hi
    out.extend(list(substring(line,last,line.length).coords)[1:])
    return LineString(out)
lines=[LineString(e['points']) for e in P.ROUTES]
original_lines=list(lines)
blocked=unary_union([g.buffer(1.35,quad_segs=8) for _,g in obstacles])
blocked_parts=[blocked] if blocked.geom_type=='Polygon' else list(blocked.geoms)
for iteration in range(3):
    for g in blocked_parts: lines=[avoid(line,g) for line in lines]
    if not any(line.buffer(1,quad_segs=6).intersection(g).area>.005 for line in lines for _,g in obstacles): break
remaining=[(i,slug,line.buffer(1,quad_segs=6).intersection(g).area) for i,line in enumerate(lines) for slug,g in obstacles if line.buffer(1,quad_segs=6).intersection(g).area>.005]
assert not remaining, remaining
detour=max(a.hausdorff_distance(b) for a,b in zip(lines,original_lines))
assert detour<5, ('Local bypass departed reference',detour)
resolved_routes=[dict(e,points=list(line.coords)) for e,line in zip(P.ROUTES,lines)]
(OUT/'route_centerlines.json').write_text(json.dumps(dict(version='v003',route_width_m=2,max_local_detour_m=detour,obstacle_policy='fixed objects retained; minimum 0.25m gap to 2m running band',routes=resolved_routes),ensure_ascii=False,indent=2),encoding='utf8')
route=unary_union([l.buffer(1,quad_segs=6) for l in lines])
assert route.geom_type=='Polygon' and route.is_valid and len(route.interiors)==2
# The band must be fully inside the floor; geometry is not silently clipped.
assert route.difference(deck).area<.01, ('route outside roof',route.difference(deck).area)
garden_clear=route.buffer(.35)
greens=[Polygon(q).difference(garden_clear).intersection(deck.buffer(-.32)) for q in P.ISLANDS]
greens[0]=translate(Polygon(P.ISLANDS[0]),yoff=1.55).difference(garden_clear).intersection(deck.buffer(-.32))
lawn=Polygon(P.LAWN).difference(garden_clear).intersection(deck.buffer(-.32))
court=[Polygon(q).difference(garden_clear).intersection(lawn) for q in P.COURT_BEDS]
plaza=[Polygon(q).difference(garden_clear).intersection(deck.buffer(-.45)) for q in P.PLAZA_BEDS]
# Floor contact, not tree crowns, defines the planting edge. The plan overlay
# hides these thin north/outer curbs; resolve them inside the fixed 50m envelope.
court[2]=translate(Polygon(P.COURT_BEDS[2]),yoff=1.8).difference(garden_clear).intersection(lawn)
for i,line in enumerate(([(-54,24.1),(-51,23.6),(-48,22.9)], [(-70,15.6),(-68.8,17.7)], [(-71.5,5),(-69.4,6.5)]),1):
    plaza[i]=LineString(line).buffer(.42,quad_segs=4).difference(garden_clear).intersection(deck.buffer(-.45))
assert all(q.geom_type=='Polygon' and q.area>1 for q in greens+[lawn]+court+plaza), [(q.geom_type,q.area) for q in greens+[lawn]+court+plaza]

# STAGE B: independent topology/bbox/semantic recheck. Not a camera identity test.
adj={n:set() for n in P.NODES}
for e in P.ROUTES: adj[e['start']].add(e['end']); adj[e['end']].add(e['start'])
visited=set(); stack=['west']
while stack:
    n=stack.pop()
    if n not in visited: visited.add(n); stack.extend(adj[n]-visited)
cycles=len(P.ROUTES)-len(visited)+1
assert len(visited)==len(P.NODES) and cycles==2 and len(adj['plaza'])==3 and len(adj['fork'])==3 and len(adj['middle'])==3
assert adj['pavilion_entry']=={'pavilion_fork'}
rows=[]
for i,g in enumerate(greens+[lawn]):
    px=[P.pixel(q) for q in g.exterior.coords]
    reference_px=(P.ISLANDS_PX+[P.LAWN_PX])[i]
    bb=P.bounds(px); rb=P.bounds(reference_px)
    center_error=[abs((bb[j]+bb[j+2]-rb[j]-rb[j+2])/2)/s for j,s in enumerate((1424,700))]
    size_error=[abs((bb[j+2]-bb[j])-(rb[j+2]-rb[j]))/s for j,s in enumerate((1424,700))]
    assert max(center_error)<.05 and max(size_error)<.08
    rows.append(dict(slug=('planter_%02d'%i if i<4 else 'lawn_court'),type='reference_planting_footprint',world_position=[g.centroid.x,g.centroid.y,25.025],world_size=[g.bounds[2]-g.bounds[0],g.bounds[3]-g.bounds[1]],rotation_z=0,local_axes='world XY traced silhouette; not a rotated preset ellipse',reference_bbox_px=rb,resolved_bbox_px=bb,normalised_center_error=center_error,normalised_size_error=size_error,anchor=['中央左绿岛，跑道下支路环绕','中央右绿岛，位于主线南侧及庭院西侧','棚尾后方景观花园，玻璃亭西侧','左广场分流口内侧','玻璃亭南侧开放草坪，雕塑锁定'][i],contact_z=25.025,occlusion='existing canopy/pavilion above floor; annotation arrows excluded',judgment='批准制作',independent_recheck='topology, floor bounds and independently sampled image bbox passed'))
judgment=dict(version='v003',scope='step1 only roof routes and greenery; all other objects immutable',stage_A='pixel-floor tracing and fixed-building anchor judgement',stage_B='independent bbox and semantic graph review',approved=True,projection='weak-perspective art-plane affine calibration; not surveyed CAD or identity camera proof',affine_pixel_to_world=P.M,anchors=[dict(pixel=[274,342],world=[-56.52,-5.16],meaning='existing circular building centre'),dict(pixel=[357,82],world=[-59,23.5],meaning='north plaza head within fixed 50m width'),dict(pixel=[1224,376],world=[41.58,4.44],meaning='existing glass pavilion floor centre, roof height offset excluded')],independent_canopy_tip_residual_m=math.dist(P.xy((1060,365)),(30.12,4.56)),cropped_east='existing east endpoint retained; invisible segment art-completed',route_width_m=2,connected=True,cycles=cycles,graph={k:sorted(v) for k,v in adj.items()},rows=rows)
(OUT/'layout_judgment.json').write_text(json.dumps(judgment,ensure_ascii=False,indent=2),encoding='utf8')
assert judgment['approved']

bpy.ops.wm.open_mainfile(filepath=str(PREVIOUS)); sc=bpy.context.scene
game=bpy.data.collections['02_游戏输出_独立资产包_v002']
src=bpy.data.collections['01_制作组件_按独立资产包']
display=bpy.data.collections['90_展示与验收_固定灯光相机']
NAMES=oldmeta['material_roles']; MATS=[bpy.data.materials[n] for n in NAMES]
CREAM=LIGHT=(9,9); TILE=(9,8); TILE2=(9,7); DARK=(9,0); STEEL=(9,4)
BLUE=(6,5); BLUEHI=(7,5); RED=(7,1); WOOD=(7,2)
GREEN=(6,4); LEAF=(7,4); LEAFHI=(8,4); GOLD=(7,3); SOIL=(5,4)
RUST=WARM=WOOD

def sha(value): return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf8')).hexdigest()
def floats(v): return [round(float(x),6) for x in v]
def signature(o):
    d=dict(name=o.name,type=o.type,parent=o.parent.name if o.parent else None,world=[floats(r) for r in o.matrix_world],dimensions=floats(o.dimensions),collections=sorted(c.name for c in o.users_collection),visibility=[o.hide_render,o.hide_viewport],properties={k:str(o[k]) for k in o.keys()},modifiers=[str(m) for m in o.modifiers],animation=str(o.animation_data))
    if o.type=='MESH':
        d.update(vertices=[floats(v.co) for v in o.data.vertices],edges=[list(e.vertices) for e in o.data.edges],faces=[[list(p.vertices),p.material_index,p.use_smooth] for p in o.data.polygons],materials=[m.name for m in o.data.materials],uv=[dict(name=u.name,render=u.active_render,active=u==o.data.uv_layers.active,loops=[floats(v.uv) for v in u.data]) for u in o.data.uv_layers])
    elif o.type=='CAMERA': d.update(lens=o.data.lens,ortho_scale=o.data.ortho_scale,clip_start=o.data.clip_start,clip_end=o.data.clip_end,camera_type=o.data.type)
    elif o.type=='LIGHT': d.update(energy=o.data.energy,color=floats(o.data.color),kind=o.data.type,size=getattr(o.data,'size',None),angle=getattr(o.data,'angle',None))
    return sha(d)
def material_signature():
    nodes=[n for n in ast.parse((R/'tools/blender/audit_tower04_mall_source.py').read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name=='signature']
    ns={}; exec(compile(ast.Module(body=nodes,type_ignores=[]),'material-signature','exec'),ns)
    return sha({m.name:ns['signature'](m) for m in MATS})
locked_objects=[o for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in editable]
before={o.name:signature(o) for o in locked_objects}; mat_before=material_signature()
render_before=dict(engine=sc.render.engine,look=sc.view_settings.look,view=sc.view_settings.view_transform,exposure=sc.view_settings.exposure,samples=sc.cycles.samples,world=sha([(n.name,[str(s.default_value) for s in n.inputs if hasattr(s,'default_value')]) for n in sc.world.node_tree.nodes]))
(OUT/'qa/locked_before.json').write_text(json.dumps(dict(objects=before,materials=mat_before,render=render_before,files=locked_files),ensure_ascii=False,indent=2),encoding='utf8')

# Reuse only audited geometry methods, not their scene/material builder code.
def load_defs(filename,names):
    path=R/'tools/blender'/filename
    nodes=[n for n in ast.parse(path.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(path),'exec'),globals())
load_defs('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'}); BasePart=Part
load_defs('build_tower04_mall_source.py',{'Part','ellipse'}); OriginalPart=Part
load_defs('build_tower04_mall_source_v002.py',{'rail','ellipsoid','leaf','plant','ribbon'})
categories={'architecture':'01_建筑结构','floor':'02_地面系统','garden':'04_曲线景观','support':'05_环境支持','facilities':'03_天台固定设施'}
CATS={k:bpy.data.collections[n] for k,n in categories.items()}; SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in categories.items()}
catalog=[]
for p in oldmeta['packages']:
    if p['slug'] in editable:
        for field in ('collection','source_collection'):
            col=bpy.data.collections[p[field]]
            for o in list(col.objects):
                mesh=o.data; bpy.data.objects.remove(o,do_unlink=True)
                if mesh.users==0: bpy.data.meshes.remove(mesh)
            bpy.data.collections.remove(col)
    else:
        info=dict(p); info['component_revision']=p['version']; info['version']='v003'; info['source_blend']=BLEND.relative_to(R).as_posix(); catalog.append(info)

class Part(OriginalPart):
    def finish(self):
        # Change metadata version in the existing geometry helper, not materials.
        objects=super().finish()
        info=catalog[-1]; info['version']='v003'; info['component_revision']='v003'; info['floor_range']='1F–5F及连续天台'
        for o in objects:
            o['version']='v003'
            for so in bpy.data.collections[info['source_collection']].objects: so['version']='v003'
        return objects
    def solid(self,g,bottom,top,c,m=1):
        # Constrained triangulation supports holes (route network loops).
        for poly in parts(g):
            for t in constrained_delaunay_triangles(poly).geoms:
                q=list(t.exterior.coords)[:-1]
                self.poly([(*v,bottom) for v in q]+[(*v,top) for v in q],[(2,1,0),(3,4,5)],c,m)
            for ring in [poly.exterior]+list(poly.interiors):
                for a,b in zip(ring.coords,list(ring.coords)[1:]): self.poly([(*a,bottom),(*b,bottom),(*b,top),(*a,top)],[(0,1,2,3)],c,m)

def parts(g): return [g] if g.geom_type=='Polygon' else [p for p in g.geoms if p.geom_type=='Polygon' and p.area>.001]
def shape(slug,name,category,g,z,h,c,definition):
    p=Part(slug,name,category,(g.centroid.x,g.centroid.y,z),definition); p.solid(g,z,z+h,c); return p
def outline(p,g,z,r,c):
    for poly in parts(g):
        for ring in [poly.exterior]+list(poly.interiors): p.path([(*q,z) for q in ring.coords],r,c,1,8)

p=shape('terrace_shell','天台平台_保留月牙凹口与局部路线悬挑','architecture',deck,23.8,1.2,LIGHT,'traced_roof_deck')
outline(p,deck,24.72,.05,CREAM); p.finish()
p=shape('roof_paving','天台铺装_回环跑道与分区地面','floor',deck,25,.023,TILE,'roof_paving')
# Large restrained paving panels: identical material language, no textures.
for x in range(-70,75,4):
    for y in range(-22,25,4):
        g=box(x,y,x+3.8,y+3.8)
        if deck.contains(g): p.solid(g,25.023,25.026,CREAM if (x+y)%3==0 else TILE)
p.finish()
# Buffer union means no coplanar overlapping strips or disconnected junctions.
p=shape('slow_lane','天台跑道_广场回环绿岛绕行与玻璃亭支路','floor',route,25.04,.018,RED,'roof_route_network')
outline(p,route,25.06,.018,CREAM); p.finish()
walk=route.buffer(2).difference(route.buffer(.04))
for g in greens+[lawn]: walk=walk.difference(g.buffer(.18))
walk=walk.intersection(deck)
p=shape('main_walk','天台主步道_红色慢行带外侧通路','floor',walk,25.029,.007,CREAM,'roof_clipped_walkway'); p.finish()

# Guardrail only follows its roof host; preserve openings next to the left roof.
edge=deck.buffer(-.16).exterior
opening=Polygon([(x,y) for x,y in ellipse(*P.OLD.CIRCLE_CENTER,16.9,12.9,80)]).buffer(.65)
rail_lines=LineString(edge.coords).difference(opening)
p=Part('terrace_rail','天台边缘护栏_随平台保留左楼接口','support',(0,0,25),'glass_guardrail')
for line in ([rail_lines] if rail_lines.geom_type=='LineString' else rail_lines.geoms):
    if line.length>.3: rail(p,list(line.coords),25,False)
p.finish()

random.seed(40043)
def planting(slug,name,g,z,trees=True):
    p=Part(slug,name,'garden',(g.centroid.x,g.centroid.y,z),'layered_planting')
    seeds=[]; b=g.bounds
    for i in range(max(10,int(g.area*1.2))):
        q=(random.uniform(b[0],b[2]),random.uniform(b[1],b[3]))
        if not g.buffer(-.42).contains(Point(q)) or min((math.dist(q,s) for s in seeds),default=99)<.7: continue
        if not deck.buffer(-1).contains(Point(q)) or route.buffer(.90).contains(Point(q)): continue
        seeds.append(q); plant(p,*q,z,3+i%2,.70)
    if trees:
        count=0; tree_seeds=[]
        for q in seeds:
            if g.buffer(-1.3).contains(Point(q)) and deck.buffer(-2).contains(Point(q)) and not route.buffer(2.1).contains(Point(q)) and all(math.dist(q,s)>3.2 for s in tree_seeds):
                plant(p,*q,z,count%2,.85); count+=1; tree_seeds.append(q)
                if count==2: break
    if not p.v:
        q=g.representative_point(); plant(p,q.x,q.y,z,2,.40)
    p.finish()

def bed(slug,name,g,z=.0,height=.575,plants_slug=None,trees=True):
    z=25.025+z; p=shape(slug,name,'garden',g,z,height,LIGHT,'traced_planter')
    inner=g.buffer(-.22)
    if inner.is_empty: inner=g.buffer(-.1)
    p.solid(inner,z+height+.001,z+height+.025,SOIL)
    outline(p,g,z+height-.03,.055,CREAM); p.finish()
    planting(plants_slug or slug.replace('planter','vegetation'),name+'_植被',inner,z+height+.025,trees)
for i,g in enumerate(greens): bed('planter_%02d'%i,['中央左绿岛_跑道环绕','中央右长形绿岛_分流口内侧','后侧景观花园_棚尾玻璃亭之间','左侧广场分流绿岛'][i],g,plants_slug='vegetation_%02d'%i)
p=shape('lawn_court','右侧开放草坪_沿庭院边界保留雕塑','garden',lawn,25.027,.10,GREEN,'traced_lawn_court')
outline(p,lawn,25.13,.065,LIGHT); p.finish()
for i,g in enumerate(court): bed('court_planter_%02d'%i,'庭院边缘异形绿带_%02d'%i,g,z=.105,height=.35,plants_slug='court_vegetation_%02d'%i)
for i,g in enumerate(plaza): bed('plaza_planter_%02d'%i,'广场外缘连续绿带_%02d'%i,g,plants_slug='plaza_green_%02d'%i,trees=False)
# Under-canopy narrow seams follow their existing fixed canopy edge; route cutouts
# keep all forks open. They are landscaping only, not moved steel/canopy geometry.
for i,(a,b) in enumerate([(2,9),(12,20),(23,30),(33,39)]):
    line=[(x,y-.55) for x,y in P.OLD.BOTTOM[a:b]]
    g=LineString(line).buffer(.32,cap_style=2).difference(garden_clear).intersection(deck.buffer(-.3))
    if g.is_empty or g.area<.3:
        line=[(x,y-.55) for x,y in P.OLD.TOP[a:b]]
        g=LineString(line).buffer(.32,cap_style=2).difference(garden_clear).intersection(deck.buffer(-.3))
    assert not g.is_empty
    bed('canopy_planter_%02d'%i,'棚边分段绿带_%02d'%i,g,plants_slug='canopy_green_%02d'%i,trees=False)

bpy.context.view_layer.update()
assert before=={name:signature(bpy.data.objects[name]) for name in before}, 'Out-of-scope object changed'
assert material_signature()==mat_before and len(bpy.data.materials)==4
for path,digest in locked_files.items(): assert hashlib.sha256((R/path).read_bytes()).hexdigest()==digest
game.name='02_游戏输出_独立资产包_v003'; sc['version']='v003'; sc['scope']='步骤1：天台路线与绿化布局；其它不变'
oldorder={p['slug']:i for i,p in enumerate(oldmeta['packages'])}
catalog.sort(key=lambda p:oldorder[p['slug']])
for info in catalog:
    folder=OUT/'component_packages'/info['category']/info['slug']; folder.mkdir(parents=True,exist_ok=True)
    (folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
meta=dict(oldmeta); meta.update(version='v003',source_blend=BLEND.relative_to(R).as_posix(),packages=catalog,source_status='step1_roof_routes_pending_saved_audit',locked_asset_hashes=locked_files,scope='roof routes/greenery only; buildings/canopy/pavilion/equipment untouched',reference=reference.name)
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')
(OUT/'component_plan.json').write_text(json.dumps(dict(version='v003',editable_packages=sorted(editable),locked_packages=sorted(p['slug'] for p in catalog if p['slug'] not in editable),attached_border='terrace rail follows roof perimeter only',route_graph=adj if False else judgment['graph'],new_materials=0,mipmap_changes=0,runtime='not_exported'),ensure_ascii=False,indent=2),encoding='utf8')

# Restore original render state and fixed camera after helper previews.
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    if any(d.type!='CPU' for d in prefs.devices): sc.cycles.device='GPU'
except Exception: pass
saved_camera=sc.camera; saved_res=(sc.render.resolution_x,sc.render.resolution_y); saved_path=sc.render.filepath
if '--no-render' not in sys.argv:
    names=[('CAM_参考全景','01_塔4_参考全景.png'),('CAM_俯视轮廓','02_塔4_俯视轮廓.png'),('CAM_天台花园','03_塔4_天台花园.png'),('CAM_左翼转折','04_塔4_椭圆左翼.png'),('CAM_玻璃亭与格构','05_塔4_玻璃亭与遮阳棚.png'),('CAM_设备节点','06_塔4_近景设备与节点.png')]
    for cam,file in names:
        sc.camera=bpy.data.objects[cam]; sc.render.resolution_x=sc.camera['resolution_x']; sc.render.resolution_y=sc.camera['resolution_y']; sc.render.filepath=str(OUT/'previews'/file)
        bpy.ops.render.render(write_still=True); print('ROUTE_PREVIEW',file,flush=True)
    # Ground-plan-only inspection: canopy and tall trees no longer hide the path.
    hidden=[]
    for o in game.all_objects:
        slug=o.get('package_id','').split('/')[-1]
        if slug=='leaf_canopy' or slug.startswith(('vegetation_','court_vegetation_','plaza_green_','canopy_green_')):
            hidden.append((o,o.hide_render)); o.hide_render=True
    sc.camera=bpy.data.objects['CAM_俯视轮廓']; sc.render.resolution_x=1920; sc.render.resolution_y=760; sc.render.filepath=str(OUT/'qa/07_本步路线与绿化平面.png')
    bpy.ops.render.render(write_still=True)
    for o,v in hidden: o.hide_render=v
sc.camera=saved_camera; sc.render.resolution_x,sc.render.resolution_y=saved_res; sc.render.filepath=saved_path
after={name:signature(bpy.data.objects[name]) for name in before}
assert before==after and material_signature()==mat_before
sc['step1_locked_object_count']=len(before)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report=dict(passed=True,stage='in_memory_before_save; reopen audit required',version='v003',editable_packages=sorted(editable),locked_object_count=len(before),locked_match=before==after,old_signatures=before,new_signatures=after,material_signature_before=mat_before,material_signature_after=material_signature(),new_materials=0,original_files_unchanged=True,route_area_m2=route.area,route_width_m=2,route_components=1,route_cycles=cycles,route_outside_roof_m2=route.difference(deck).area,garden_route_overlap_m2=sum(g.intersection(route).area for g in greens+[lawn]),notes=['reference is perspective diagram, not CAD','cropped east continuation retained','other structures and props intentionally not optimized in this step'])
(OUT/'qa/route_scope_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('TOWER04_ROUTES_SAVED',str(BLEND),flush=True)
