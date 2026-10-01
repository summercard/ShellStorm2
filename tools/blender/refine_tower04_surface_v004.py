"""Tower04 close-range surface stage. Opens v003; never executes a scene builder.

blender --background --factory-startup --python-exit-code 1 --python this.py --
  --geometry-libs <cp311 shapely site-packages> [--draft-sha <approved draft>]
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
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely.geometry import Polygon,LineString,Point,box
from shapely.ops import unary_union,substring
from shapely import constrained_delaunay_triangles
OLD=R/'assets/art/environments/open_world/source/tower_04/v003'
OUT=OLD.parent/'v004'; BLEND=OUT/'塔4_曲线天台商场_150x50m_v004.blend'
PREVIOUS=OLD/'塔4_曲线天台商场_150x50m_v003.blend'
ASSET='ENV-OPENWORLD-TOWER04'
PALETTE=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
DONOR=R/'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
for d in ('qa/closeups','previews','component_packages','references'): (OUT/d).mkdir(parents=True,exist_ok=True)
if BLEND.exists():
    assert '--draft-sha' in sys.argv and hashlib.sha256(BLEND.read_bytes()).hexdigest()==sys.argv[sys.argv.index('--draft-sha')+1], 'External draft change; no overwrite'
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))
oldmap={p['slug']:p for p in meta['packages']}
editable={'roof_paving','main_walk','slow_lane','lawn_court','garden_bench_04','litter_bin_01','bollard_04','bollard_05'}|{s for s in oldmap if s.startswith('court_planter_')}
files={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (PREVIOUS,DONOR,PALETTE,Path(str(PALETTE)+'.import'),OLD/'route_centerlines.json')}
for file in (OLD/'references').glob('*.png'): shutil.copy2(file,OUT/'references'/file.name)
shutil.copy2(OLD/'route_centerlines.json',OUT/'route_centerlines.json')
bpy.ops.wm.open_mainfile(filepath=str(PREVIOUS)); sc=bpy.context.scene
game=bpy.data.collections['02_游戏输出_独立资产包_v003']; display=bpy.data.collections['90_展示与验收_固定灯光相机']
NAMES=meta['material_roles']; MATS=[bpy.data.materials[n] for n in NAMES]
CREAM=LIGHT=(9,9); TILE=(9,8); TILE2=(9,7); DARK=(9,0); STEEL=(9,4)
BLUE=(6,5); BLUEHI=(7,5); RED=(7,1); TRACK_B=(8,1); WOOD=(7,2)
GREEN=(6,4); LEAF=(7,4); LEAFHI=(8,4); GOLD=(7,3); SOIL=(5,4); RUST=WARM=WOOD
def load_defs(file,names):
    path=R/'tools/blender'/file
    nodes=[n for n in ast.parse(path.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(path),'exec'),globals())
load_defs('refine_tower04_routes_v003.py',{'sha','floats','signature','material_signature','parts'})
def parts(g):
    if g.is_empty: return []
    if g.geom_type=='Polygon': return [g]
    return [p for p in g.geoms if p.geom_type=='Polygon' and p.area>1e-9]
before={o.name:signature(o) for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in editable}
mat_before=material_signature()
def surface(slug,z):
    out=[]
    for name in oldmap[slug]['objects']:
        o=bpy.data.objects[name]
        for f in o.data.polygons:
            vv=[o.matrix_world@o.data.vertices[i].co for i in f.vertices]
            if all(abs(v.z-z)<.00015 for v in vv):
                p=Polygon([(v.x,v.y) for v in vv])
                if p.is_valid and p.area>1e-7: out.append(p)
    assert out, (slug,z)
    return unary_union(out).buffer(0)
deck=surface('terrace_shell',25); route=surface('slow_lane',25.058); lawn=surface('lawn_court',25.127)
green={s:surface(s,25.6 if s.startswith('planter_') or s.startswith(('plaza_planter_','canopy_planter_')) else 25.48) for s in oldmap if s.startswith(('planter_','court_planter_','plaza_planter_','canopy_planter_'))}
green['lawn_court']=lawn
layout={s:dict(area_m2=g.area,wkt=g.wkt) for s,g in dict(deck=deck,route=route,**green).items()}
(OUT/'qa/locked_before.json').write_text(json.dumps(dict(objects=before,materials=mat_before,files=files),ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_plan.json').write_text(json.dumps(dict(version='v004',editable_packages=sorted(editable),attached='floor panel bevel/joint/inspection cover stays in its panel; court planter coping stays with planter',locked_packages=sorted(set(oldmap)-editable),new_materials=0,mipmap_changes=0,layout_frozen_from='v003 saved mesh',runtime='not_exported'),ensure_ascii=False,indent=2),encoding='utf8')
load_defs('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'}); BasePart=Part
load_defs('build_tower04_mall_source.py',{'Part','ellipse'}); OriginalPart=Part
load_defs('build_tower04_mall_source_v002.py',{'ellipsoid','leaf'})
cats={'architecture':'01_建筑结构','floor':'02_地面系统','garden':'04_曲线景观','support':'05_环境支持','facilities':'03_天台固定设施'}
CATS={k:bpy.data.collections[n] for k,n in cats.items()}; SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in cats.items()}
catalog=[]
class Part(OriginalPart):
    def solid(self,g,z0,z1,c,m=1):
        for poly in parts(g):
            for t in constrained_delaunay_triangles(poly).geoms:
                q=list(t.exterior.coords)[:-1]
                self.poly([(*v,z0) for v in q]+[(*v,z1) for v in q],[(2,1,0),(3,4,5)],c,m)
            for ring in [poly.exterior]+list(poly.interiors):
                q=list(ring.coords)
                for a,b in zip(q,q[1:]): self.poly([(*a,z0),(*b,z0),(*b,z1),(*a,z1)],[(0,1,2,3)],c,m)
    def bevelsolid(self,g,z0,z1,c,b=.012,m=1):
        # Real sloping upper lip, no coplanar color sticker or material modifier.
        for poly in parts(g):
            inner=poly.buffer(-b,join_style=2)
            if inner.is_empty or inner.area<.005:
                self.solid(poly,z0,z1,c,m); continue
            self.solid(poly,z0,z1-b,c,m)
            self.solid(inner,z1-b,z1,c,m)
            lip=poly.difference(inner)
            for t in constrained_delaunay_triangles(lip).geoms:
                vv=[]
                for x,y in list(t.exterior.coords)[:-1]:
                    d=poly.boundary.distance(Point(x,y)); vv.append((x,y,z1-b+min(1,d/b)*b))
                self.poly(vv,[(0,1,2)],c,m)
    def finish(self):
        result=super().finish(); p=catalog[-1]; p.update(version='v004',component_revision='v004',floor_range='连续天台25m')
        for o in result+list(bpy.data.collections[p['source_collection']].objects): o['version']='v004'
        return result
def shape(slug,name,cat,g,z0,z1,c,definition):
    p=Part(slug,name,cat,(g.centroid.x,g.centroid.y,z0),definition); p.solid(g,z0,z1,c); return p
def inherit(slug):
    info=oldmap[slug]; p=Part(slug,info['display_name'],info['category'],info['world_position'],info['component_definition'])
    for name in info['objects']:
        o=bpy.data.objects[name]; uv=o.data.uv_layers.active
        for f in o.data.polygons:
            loops=list(f.loop_indices); cx=sum(uv.data[i].uv.x for i in loops)/len(loops); cy=sum(uv.data[i].uv.y for i in loops)/len(loops)
            cell=(int(cx*10),int((1-cy)*10)); mat=MATS.index(o.data.materials[f.material_index])
            p.poly([tuple(o.matrix_world@o.data.vertices[i].co) for i in f.vertices],[tuple(range(len(f.vertices)))],cell,mat)
    return p
inherited={s:inherit(s) for s in editable if s.startswith('court_planter_') or s in ('garden_bench_04','litter_bin_01','bollard_04','bollard_05')}
for info in meta['packages']:
    if info['slug'] not in editable:
        v=dict(info); v.update(version='v004',component_revision=info.get('component_revision',info['version']),source_blend=BLEND.relative_to(R).as_posix()); catalog.append(v); continue
    for key in ('collection','source_collection'):
        col=bpy.data.collections[info[key]]
        for o in list(col.objects):
            mesh=o.data; bpy.data.objects.remove(o,do_unlink=True)
            if mesh.users==0: bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(col)

# Continuous recessed substrate; individual physical slabs own their chamfers.
p=shape('roof_paving','天台铺装基层_沉缝无叠面','floor',deck,25,25.022,TILE2,'roof_joint_substrate'); p.finish()
trim=route.buffer(.14,join_style=2).difference(route).intersection(deck)
occupied=unary_union(list(green.values())+[route.buffer(.155)])
holes=[]
for info in meta['packages']:
    if info['slug'].startswith('drain_') or info['slug']=='glass_pavilion':
        if info['slug']=='glass_pavilion':
            # Four real floor corners, not the rotated pavilion's AABB.
            sys.path.insert(0,str(R/'tools/blender')); import tower04_plan_v002 as oldplan
            holes.append(Polygon(oldplan.PAVILION).buffer(.04))
        else: holes.append(box(*info['bounds_min'][:2],*info['bounds_max'][:2]).buffer(.035))
paving=deck.difference(occupied).difference(unary_union(holes))
walk_edge=unary_union([g.buffer(.15).difference(g) for s,g in green.items() if s!='lawn_court']).intersection(paving)
paving=paving.difference(walk_edge)
tiles=[]
for row,y in enumerate([ -25+i*1.5 for i in range(34)]):
    stagger=1.5 if row%2 else 0
    for col,x in enumerate([-76.5+stagger+i*3 for i in range(52)]):
        raw=box(x+.018,y+.018,x+2.982,y+1.482).intersection(paving)
        for k,g in enumerate(parts(raw)):
            if g.area<.045: continue
            slug=f'tile_r{row:02d}_c{col:02d}_{k}'; p=Part(slug,f'天台板_{row:02d}行_{col:02d}列_{k}_倒角沉缝','floor',(g.centroid.x,g.centroid.y,25.022),'roof_paver_3x1p5')
            p.bevelsolid(g,25.022,25.055,CREAM if (row*11+col*7)%13 else TILE,b=.008)
            p.finish(); catalog[-1].update(tile_row=row,tile_column=col,tile_fragment=k,joint_gap_m=.036,bevel_m=.008,nominal_panel_m=[3,1.5],surface_z_m=25.055,dependencies=['tower_04/roof_paving']); tiles.append(g)
print('TOWER04_PAVER_COUNT',len(tiles),flush=True)
# Walk identity retained as a narrow flush apron, never overlays entire slabs.
p=shape('main_walk','主步道花池贴边_齐平灰色收口','floor',walk_edge,25.022,25.054,TILE,'walkway_planter_apron'); p.finish()

# Segment by station along each frozen branch. First branch owns junctions.
p=shape('slow_lane','两米跑道_邻色分段与实体倒角压边','floor',route,25.024,25.040,RED,'two_adjacent_palette_segment_track')
route_data=json.loads((OLD/'route_centerlines.json').read_text(encoding='utf8'))
claimed=Polygon(); colored=[]; color_b=[]; segments=[]
for ei,entry in enumerate(route_data['routes']):
    line=LineString(entry['points']); owner=line.buffer(1.01,quad_segs=6).intersection(route).difference(claimed)
    covered=Polygon()
    for si in range(math.ceil(line.length/7.5)):
        a=si*7.5; b=min(line.length,(si+1)*7.5)
        g=substring(line,a,b).buffer(1.5,cap_style=2,quad_segs=6).intersection(owner).difference(covered)
        if g.area<.003: continue
        c=RED if (si+ei)%2==0 else TRACK_B
        if c==TRACK_B: color_b.append(g)
        colored.append(g); covered=unary_union([covered,g]); segments.append(dict(branch=entry['start']+'-'+entry['end'],station=[a,b],palette_cell=c,area_m2=g.area))
    rest=owner.difference(covered)
    if rest.area>.00001: colored.append(rest)
    claimed=unary_union([claimed,owner])
rest=route.difference(claimed)
if rest.area>.00001: colored.append(rest)
# Only two exhaustive complement meshes, not independently clipped overlays.
# Keeps small junction fragments closed after the Blender float32 round-trip.
gb=unary_union(color_b).simplify(.00002,preserve_topology=True).intersection(route)
ga=route.difference(gb)
p.solid(ga,25.040,25.059,RED); p.solid(gb,25.040,25.059,TRACK_B)
colored=[ga,gb]
p.bevelsolid(trim,25.024,25.064,CREAM,b=.014)
p.finish(); catalog[-1].update(track_width_m=2,track_palette_cells=[RED,TRACK_B],station_segment_m=7.5,attached_edge_width_m=.14)

# Turf is broad, restrained mowing panels, not high-frequency grass/noise.
p=shape('lawn_court','开放草坪_分带草皮沉边与排水收口','garden',lawn,25.027,25.113,GREEN,'traced_lawn_detailed_surface')
lawn_inner=lawn.buffer(-.16)
p.solid(lawn.difference(lawn_inner),25.113,25.127,LIGHT)
turf=[]
for i in range(20):
    g=box(20+i*2.0,-25,22+i*2.0,20).intersection(lawn_inner)
    if g.area>.005:
        p.solid(g,25.113,25.127,LEAF if i%4==1 else GREEN); turf.append(g)
        # Subtle 12mm turf roll joint, flat and safe; no scene-wide texture.
        seam=LineString([(20+i*2,-25),(20+i*2,20)]).buffer(.006).intersection(lawn_inner)
        p.solid(seam,25.127,25.130,(5,4))
# A few graphic tufts confined inside edge; center remains an open usable lawn.
random.seed(40404); tufts=0
clear=lawn_inner.difference(unary_union([g.buffer(.30) for s,g in green.items() if s.startswith('court_planter_')]))
for i in range(105):
    x=random.uniform(lawn.bounds[0],lawn.bounds[2]); y=random.uniform(lawn.bounds[1],lawn.bounds[3]); q=Point(x,y)
    if not clear.buffer(-.35).contains(q) or clear.boundary.distance(q)>1.6: continue
    if q.distance(Point(*oldmap['court_sculpture']['world_position'][:2]))<2.4: continue
    if any(box(*oldmap[s]['bounds_min'][:2],*oldmap[s]['bounds_max'][:2]).buffer(.4).contains(q) for s in ('garden_bench_04','litter_bin_01','bollard_04','bollard_05')): continue
    for j in range(3):
        dx=(j-1)*.06; p.poly([(x+dx-.035,y,25.127),(x+dx+.035,y,25.127),(x+dx+.08,y+.08,25.31-j*.04)],[(0,1,2)],LEAF if j%2 else GREEN)
    tufts+=1
p.finish(); catalog[-1].update(turf_joint_width_m=.012,tuft_count=tufts,layout_footprint_unchanged=True)

# Keep original grass-court facility positions and shape, add attached details.
for slug,p in inherited.items():
    x,y,z=oldmap[slug]['world_position']
    if slug.startswith('court_planter_'):
        g=green[slug]; edge=g.buffer(-.025).difference(g.buffer(-.19))
        p.bevelsolid(edge,25.48,25.56,CREAM,b=.02)
        ring=LineString(g.buffer(-.11).exterior.coords)
        for i in range(math.ceil(ring.length/1.5)):
            q=ring.interpolate(i*1.5); t=ring.interpolate(min(ring.length,i*1.5+.015)); d=Vector((t.x-q.x,t.y-q.y));
            if d.length<1e-7: continue
            d.normalize(); normal=Vector((-d.y,d.x)); a=Vector((q.x,q.y))-normal*.075; b=Vector((q.x,q.y))+normal*.075
            p.rod((*a,25.561),(*b,25.561),.009,TILE2,1,6)
        # Raised inner shadow lip and a broad soil perimeter inside the coping.
        soil_edge=g.buffer(-.21).difference(g.buffer(-.31)); p.solid(soil_edge,25.50,25.505,SOIL)
    elif slug=='garden_bench_04':
        for dx in (-1.3,1.3):
            for dy in (-.30,.30):
                p.rod((x+dx,y+dy,25.18),(x+dx,y+dy,25.21),.044,LIGHT,0,8)
            for j in range(5): p.rod((x+dx,y-.38+j*.17,25.85),(x+dx,y-.38+j*.17,25.86),.024,STEEL,0,8)
        p.rod((x-1.40,y+.25,25.62),(x+1.40,y+.25,25.62),.055,STEEL,0,10)
        for dx in (-1.63,1.63): p.box((x+dx,y-.04,25.78),(.045,.87,.17),TILE2,0,.015)
    elif slug=='litter_bin_01':
        for dx in (-.31,.31):
            p.box((x+dx,y-.353,26.075),(.38,.065,.05),STEEL,0,.012)
            for zz in (25.45,25.99): p.box((x+dx+.24,y-.354,zz),(.04,.035,.12),STEEL,0,.01)
            p.box((x+dx+.15,y-.353,25.77),(.035,.035,.13),STEEL,0,.01)
            for k in range(3): p.box((x+dx,y+.297,25.50+k*.1),(.32,.022,.035),DARK,1,.01)
            p.rod((x+dx,y,26.38),(x+dx,y,26.405),.17,LIGHT,1,16)
    else:
        for dx in (-.16,.16):
            for dy in (-.16,.16): p.rod((x+dx,y+dy,25.14),(x+dx,y+dy,25.17),.03,LIGHT,0,8)
        p.box((x,y-.139,25.45),(.18,.015,.30),TILE2,1,.02)
        p.rod((x,y-.152,25.46),(x,y-.17,25.46),.03,STEEL,0,8)
    p.finish(); catalog[-1]['dependencies']=['tower_04/lawn_court']

bpy.context.view_layer.update()
assert before=={n:signature(bpy.data.objects[n]) for n in before},'Unplanned edit'
assert mat_before==material_signature() and len(bpy.data.materials)==4
for f,h in files.items(): assert hashlib.sha256((R/f).read_bytes()).hexdigest()==h
game.name='02_游戏输出_独立资产包_v004'; sc['version']='v004'; sc['scope']='步骤2：近景地板、双邻色跑道压边与草坪附属设施；路线布局及建筑锁定'
for info in catalog:
    folder=OUT/'component_packages'/info['category']/info['slug']; folder.mkdir(parents=True,exist_ok=True)
    (folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
meta.update(version='v004',source_blend=BLEND.relative_to(R).as_posix(),packages=catalog,package_count=len(catalog),component_definition_count=len({p['component_definition'] for p in catalog}),source_status='step2_close_range_pending_saved_audit',locked_asset_hashes=files,scope='close range surfaces and grass court attachments only; frozen v003 layout')
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')
plan=dict(passed=True,locked_match=True,old_signatures=before,material_signature_before=mat_before,frozen_layout=layout,tile_count=len(tiles),tile_area_m2=sum(g.area for g in tiles),track_segments=segments,track_surface_area_m2=unary_union(colored).area,track_surface_gap_m2=route.difference(unary_union(colored)).area,track_surface_overlap_m2=sum(g.area for g in colored)-unary_union(colored).area,edge_width_m=.14,paver_gap_m=.036,paver_bevel_m=.008,surface_levels_m=dict(substrate=25.022,paver=25.055,track=25.059,track_coping=25.064,turf=25.127),new_materials=0,mipmap_changes=0,tuft_count=tufts)
(OUT/'qa/surface_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')

# Same cameras for before/after. Additional closeups use actual eye-height views.
closeups=[('CAM_近景_跑道压边',(10,-8.5,27.05),(5,-7.7,25.15),34),('CAM_近景_草坪设施',(36,-17,27.15),(32.5,-7.5,25.7),38),('CAM_近景_地板接缝',(11,-6,27.10),(8,-2,25.10),40),('CAM_近景_庭院花池',(49,-18,27.35),(44,-12,25.5),40)]
for name,pos,target,lens in closeups:
    data=bpy.data.cameras.new(name); data.lens=lens; data.clip_start=.10; data.clip_end=300
    cam=bpy.data.objects.new(name,data); display.objects.link(cam); cam.location=pos; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler(); cam['resolution_x']=1600; cam['resolution_y']=1000
sc['close_range_validation']='four fixed 1.7–2.3m-above-surface inspection cameras; pending renders'
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('TOWER04_SURFACE_SAVED',str(BLEND),flush=True)
