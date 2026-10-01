"""Reference-led Tower04 platform: modular construction, restrained apocalypse.
Run Blender factory-startup --python this_file -- --geometry-libs <Shapely>.
Only selected helper definitions are evaluated; existing scene builders never run.
"""
import ast,bpy,hashlib,json,math,random,shutil,sys
from pathlib import Path
from collections import defaultdict
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,sys.argv[sys.argv.index('--geometry-libs')+1])
from shapely.geometry import Polygon,Point,LineString,box
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles,wkt
OLD=R/'assets/art/environments/open_world/source/tower_04/v004'; OUT=OLD.parent/'v005'
PREVIOUS=OLD/'塔4_曲线天台商场_150x50m_v004.blend'; BLEND=OUT/'塔4_末世平台模块化_150x50m_v005.blend'
ASSET='ENV-OPENWORLD-TOWER04'; PALETTE=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
DONOR=R/'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
for d in ('qa','previews','mood','component_packages','references'): (OUT/d).mkdir(parents=True,exist_ok=True)
if BLEND.exists():
    assert '--draft-sha' in sys.argv and hashlib.sha256(BLEND.read_bytes()).hexdigest()==sys.argv[sys.argv.index('--draft-sha')+1],'Draft changed externally'
refs=['934be9b1-7b88-4861-ab09-64d85cc6fd76','4dead061-75b1-4dc8-a4f2-1a4e5340ebe0','550575ce-c477-4ad1-9d49-b33ced5066ad','41cb4d0c-a177-4d27-93d5-fb9575172dd1','a5877c9b-e374-432d-be4c-8aeef12279fa','aaf2c967-bfcb-45c0-add2-b609863575bf']
for i,v in enumerate(refs):
    f=Path('C:/Users/ZHUANG~1/AppData/Local/Temp')/('codex-clipboard-'+v+'.png')
    shutil.copy2(f,OUT/'references'/f'参考_{i+1:02d}_末世平台.png')
shutil.copy2(OLD/'route_centerlines.json',OUT/'route_centerlines.json')
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8')); oldmap={p['slug']:p for p in meta['packages']}
layout=json.loads((OLD/'qa/surface_plan.json').read_text(encoding='utf8'))['frozen_layout']
deck=wkt.loads(layout['deck']['wkt']); route=wkt.loads(layout['route']['wkt'])
greens={s:wkt.loads(v['wkt']) for s,v in layout.items() if s not in ('route','deck')}
def zone(x): return 'A' if x< -45 else 'B' if x< -15 else 'C' if x<25 else 'D' if x<55 else 'E'
zones={'A':'入口广场','B':'棚下西段','C':'中央花池与棚下东段','D':'右侧庭院营地','E':'东端补给区'}
locked_slugs={s for s in oldmap if s.startswith(('oval_level_','wing_level_','pier_')) or s in ('oval_glazing','wing_glazing')}
editable=set(oldmap)-locked_slugs
planning=dict(version='v005',scope='platform at z>=23.8; lower architecture locked',zone_names=zones,editable_packages=sorted(editable),locked_packages=sorted(locked_slugs),module_max_xy_m=10,grid_origin_m=[-75,-25],new_definitions=['camp_tent','ibc_water_tank','reinforced_supply_case','wood_supply_crate','steel_drum','folding_solar_panel','wood_pallet','fixed_jerry_can','contained_vine_patch'],source_only=True,new_materials=0,mipmap_changes=0,principles=['Exact cut planes; no arbitrary object relocation','Intact small assets; one semantic asset per leaf collection','Each floor panel retains its own weathering','Two-tone track and navigation centerlines preserved','Vines are localized accents, not a facade blanket'])
(OUT/'component_plan.json').write_text(json.dumps(planning,ensure_ascii=False,indent=2),encoding='utf8')
bpy.ops.wm.open_mainfile(filepath=str(PREVIOUS)); sc=bpy.context.scene
game=bpy.data.collections['02_游戏输出_独立资产包_v004']; display=bpy.data.collections['90_展示与验收_固定灯光相机']
NAMES=meta['material_roles']; MATS=[bpy.data.materials[n] for n in NAMES]
CREAM=LIGHT=(9,9); TILE=(9,8); TILE2=(9,7); DARK=(9,1); STEEL=(9,4)
BLUE=(6,5); BLUEHI=(7,5); RED=(7,1); WOOD=(6,2); WARM=RUST=(5,2)
GREEN=(6,4); LEAF=(7,4); LEAFHI=(8,4); GOLD=(7,3); SOIL=(5,4)
def load_defs(file,names):
    p=R/'tools/blender'/file; nodes=[n for n in ast.parse(p.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(p),'exec'),globals())
load_defs('refine_tower04_routes_v003.py',{'sha','floats','signature','material_signature'})
before={o.name:signature(o) for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in editable}
mat_before=material_signature(); files={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (PREVIOUS,DONOR,PALETTE,Path(str(PALETTE)+'.import'),OLD/'route_centerlines.json')}
(OUT/'qa/locked_before.json').write_text(json.dumps(dict(objects=before,materials=mat_before,files=files),ensure_ascii=False,indent=2),encoding='utf8')
load_defs('build_skyline_08_source_v001.py',{'coll','uv_mesh','Part'}); BasePart=Part
load_defs('build_tower04_mall_source.py',{'Part','ellipse'}); OriginalPart=Part
load_defs('refine_tower04_surface_v004.py',{'parts','Part'}); SurfacePart=Part
load_defs('build_tower04_mall_source_v002.py',{'ellipsoid','leaf'})
cats={'architecture':'01_建筑结构','floor':'02_地面系统','garden':'04_曲线景观','support':'05_环境支持','facilities':'03_天台固定设施'}
CATS={k:bpy.data.collections[n] for k,n in cats.items()}; SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in cats.items()}
catalog=[]; decomposition={}; counters=defaultdict(int); new_props=[]; vine_records=[]
class Part(SurfacePart):
    def finish(self):
        obs=OriginalPart.finish(self); info=catalog[-1]; info.update(version='v005',component_revision='v005',floor_range='连续天台25m',zone_id=zone(self.origin.x),zone_name=zones[zone(self.origin.x)])
        for o in obs+list(bpy.data.collections[info['source_collection']].objects): o['version']='v005'; o['zone_id']=info['zone_id']
        return obs
def cut(poly,axis,value,keep_greater):
    if not poly: return []
    result=[]
    for a,b in zip(poly,[*poly[1:],poly[0]]):
        ain=(a[axis]>=value-1e-8) if keep_greater else (a[axis]<=value+1e-8)
        bin=(b[axis]>=value-1e-8) if keep_greater else (b[axis]<=value+1e-8)
        if ain: result.append(a)
        if ain!=bin:
            t=(value-a[axis])/(b[axis]-a[axis]); q=tuple(a[k]+t*(b[k]-a[k]) for k in range(3)); result.append(q)
    clean=[]
    for q in result:
        if not clean or math.dist(q,clean[-1])>1e-7: clean.append(q)
    if len(clean)>1 and math.dist(clean[0],clean[-1])<1e-7: clean.pop()
    return clean
def area3(v):
    return sum((Vector(v[i])-Vector(v[0])).cross(Vector(v[i+1])-Vector(v[0])).length/2 for i in range(1,len(v)-1))
def facecell(o,f):
    uv=o.data.uv_layers.active
    return (int(sum(uv.data[i].uv.x for i in f.loop_indices)/len(f.loop_indices)*10),int((1-sum(uv.data[i].uv.y for i in f.loop_indices)/len(f.loop_indices))*10))
def inherit(item):
    p=Part(item['slug'],item['display_name'],item['category'],item['world_position'],item['component_definition'])
    rng=random.Random(item['slug']+'v005')
    for n in item['objects']:
        o=bpy.data.objects[n]
        for f in o.data.polygons:
            v=[tuple(o.matrix_world@o.data.vertices[i].co) for i in f.vertices]; c=facecell(o,f); m=MATS.index(o.data.materials[f.material_index])
            is_canopy=item['slug']=='leaf_canopy'
            # Remove only infill sheets; all frame members remain straight/intact.
            if is_canopy and len(v)==3 and m in (1,2) and area3(v)>.1:
                if rng.random()<.62: counters['canopy_infill_removed']+=1; continue
                if rng.random()<.35:
                    a,b,c0=map(Vector,v); v=[tuple(a),tuple(b),tuple((b+c0)*.5),tuple((a+c0)*.5)]
            if item['slug']=='glass_pavilion' and m==2 and area3(v)>.4 and rng.random()<.32:
                # Keep attached shards at pane corners; never remove the mullions.
                a,b,c0=map(Vector,v[:3]); v=[tuple(a),tuple(a+(b-a)*.53),tuple(a+(c0-a)*.36)]; counters['pavilion_panes_broken']+=1
            if item['category'] in ('support','facilities') and m==0 and rng.random()<.085: c=RUST
            p.poly(v,[tuple(range(len(v)))],c,m)
    return p
def geometry_polygon(p,z):
    pp=[]
    for f in p.f:
        v=[p.v[i] for i in f]
        if all(abs(q[2]-z)<.0003 for q in v):
            g=Polygon([(q[0],q[1]) for q in v])
            if g.is_valid and g.area>1e-6: pp.append(g)
    return unary_union(pp)
def patch(p,g,z,c,m=1):
    for a in parts(g):
        for t in constrained_delaunay_triangles(a).geoms: p.poly([(*q,z) for q in list(t.exterior.coords)[:-1]],[(0,1,2)],c,m)
def blade(p,x,y,z,angle,length=.35,c=LEAF):
    d=Vector((math.cos(angle),math.sin(angle),0)); n=Vector((-d.y,d.x,0)); root=Vector((x,y,z)); tip=root+d*length+Vector((0,0,length*.45)); mid=root+d*length*.46+Vector((0,0,length*.35))
    p.poly([root,mid+n*length*.19,tip,mid-n*length*.19,mid+Vector((0,0,.025))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],c)
def floor_weather(p,slug):
    rng=random.Random(slug+'floor'); g=geometry_polygon(p,25.055)
    if g.is_empty: return
    b=g.bounds; center=g.representative_point()
    if rng.random()<.43:
        angle=rng.uniform(0,math.tau); scale=rng.uniform(.55,1.1)
        points=[(center.x+scale*(u*math.cos(angle)-v*math.sin(angle)),center.y+scale*(u*math.sin(angle)+v*math.cos(angle))) for u,v in [(-.65,-.20),(-.30,.04),(-.10,-.03),(.20,.21),(.67,.32)]]
        crack=LineString(points).buffer(.012,join_style=2).intersection(g.buffer(-.015)); patch(p,crack,25.060,(9,4)); counters['cracked_tiles']+=1
    if rng.random()<.34:
        edge=LineString(g.exterior.coords); q=edge.interpolate(rng.random()*edge.length)
        angle=rng.uniform(0,math.tau); length=rng.uniform(.25,.7); width=rng.uniform(.10,.28)
        points=[]
        for i in range(13):
            t=i*math.tau/13; r=rng.uniform(.5,1.0); u=math.cos(t)*length*r; v=math.sin(t)*width*r
            points.append((q.x+u*math.cos(angle)-v*math.sin(angle),q.y+u*math.sin(angle)+v*math.cos(angle)))
        dirt=Polygon(points).intersection(g)
        patch(p,dirt,25.058,(9,7)); patch(p,dirt.buffer(-.035),25.059,(9,6)); counters['scuffed_tiles']+=1
    if rng.random()<.07 and g.area>2:
        poly=Polygon([(center.x+math.cos(i*math.tau/9)*(.30+rng.random()*.34),center.y+math.sin(i*math.tau/9)*(.17+rng.random()*.14)) for i in range(9)])
        patch(p,poly.intersection(g.buffer(-.06)),25.062,(8,5),2); counters['puddle_tiles']+=1
    if rng.random()<.12:
        inset=g.buffer(-.55)
        if inset.is_empty: return
        q=inset.representative_point()
        for i in range(4): blade(p,q.x-.15+i*.08,q.y+.2,25.059,i*1.3,.20+(i%2)*.12,LEAF if i%2 else GREEN)
        counters['weed_tiles']+=1
def split_finish(p,item):
    # Sutherland-Hodgman clipping preserves exact existing world-space assembly.
    # 10m X/Y boundaries; short props stay intact and are never arbitrarily cut.
    if max(item['dimensions'][:2])<=10:
        p.finish(); catalog[-1]['previous_package_id']=item['package_id']; decomposition[item['slug']]=[p.slug]; return
    out={}
    for ff,c,m in zip(p.f,p.co,p.mi):
        vv=[p.v[i] for i in ff]; x0=min(v[0] for v in vv); x1=max(v[0] for v in vv); y0=min(v[1] for v in vv); y1=max(v[1] for v in vv)
        for ix in range(math.floor((x0+75)/10),max(math.floor((x0+75)/10),math.floor((x1+75-1e-8)/10))+1):
            for iy in range(math.floor((y0+25)/10),max(math.floor((y0+25)/10),math.floor((y1+25-1e-8)/10))+1):
                left=-75+ix*10; bottom=-25+iy*10
                q=cut(cut(cut(cut(vv,0,left,True),0,left+10,False),1,bottom,True),1,bottom+10,False)
                if len(q)<3 or area3(q)<1e-8: continue
                key=(ix,iy)
                if key not in out:
                    slug=f'{p.slug}_x{ix:02d}_y{iy:02d}'; out[key]=Part(slug,p.name[:12]+f'_区块{ix:02d}_{iy:02d}',p.category,(left+5,bottom+5,p.origin.z),p.definition)
                out[key].poly(q,[tuple(range(len(q)))],c,m)
    assert out,p.slug
    decomposition[p.slug]=[]
    for (ix,iy),q in sorted(out.items()):
        q.finish(); catalog[-1].update(previous_package_id=item['package_id'],assembly_grid=[ix,iy],cut_bounds_xy=[-75+ix*10,-25+iy*10,-65+ix*10,-15+iy*10],interfaces='shared exact world cut planes; visible surface continuity preserved')
        decomposition[p.slug].append(q.slug)

# Read source surfaces before removing authorized output/source pairs.
made={}
for item in meta['packages']:
    if item['slug'] in editable:
        p=inherit(item)
        if p.slug.startswith('tile_r'): floor_weather(p,p.slug)
        made[item['slug']]=p
for item in meta['packages']:
    if item['slug'] in locked_slugs:
        info=dict(item); info.update(version='v005',source_blend=BLEND.relative_to(R).as_posix(),platform_scope=False); catalog.append(info); continue
    for key in ('collection','source_collection'):
        col=bpy.data.collections[item[key]]
        for o in list(col.objects):
            data=o.data; bpy.data.objects.remove(o,do_unlink=True)
            if data.users==0: bpy.data.meshes.remove(data)
        bpy.data.collections.remove(col)
    split_finish(made[item['slug']],item)
print('PLATFORM_SPLIT_COMPLETE',len(catalog),flush=True)

# Curated clear-ground layout: footprints checked against route, beds and anchors.
obstacles=[route.buffer(.42)]
for s,g in greens.items():
    if s!='lawn_court': obstacles.append(g.buffer(.22))
for s,p in oldmap.items():
    if p['category']=='facilities':
        if s=='glass_pavilion':
            sys.path.insert(0,str(R/'tools/blender')); import tower04_plan_v002 as OP
            obstacles.append(Polygon(OP.PAVILION).buffer(.20))
        else: obstacles.append(box(*p['bounds_min'][:2],*p['bounds_max'][:2]).buffer(.2))
    if s.startswith('canopy_column_'):
        x,y=p['world_position'][:2]; obstacles.append(box(x-.65,y-.65,x+.65,y+.65))
blocked=unary_union(obstacles); placements=[]; safe_deck=deck.buffer(-.35)
def ground(x,y): return 25.127 if greens['lawn_court'].contains(Point(x,y)) else 25.055
def place(preferred,w,d,label,max_shift=11):
    global blocked
    candidates=[]
    for dx in range(-int(max_shift*2),int(max_shift*2)+1):
        for dy in range(-24,25):
            x=preferred[0]+dx*.5; y=preferred[1]+dy*.5
            if abs(x-preferred[0])>max_shift: continue
            g=box(x-w/2,y-d/2,x+w/2,y+d/2)
            if safe_deck.contains(g) and not g.intersects(blocked): candidates.append((dx*dx+dy*dy,x,y,g))
    assert candidates,('No safe placement',label,preferred,w,d)
    _,x,y,g=min(candidates,key=lambda q:q[0]); blocked=unary_union([blocked,g.buffer(.18)])
    placements.append(dict(asset=label,position=[x,y,ground(x,y)],bounds=list(g.bounds),zone_id=zone(x),route_overlap_m2=g.intersection(route).area))
    return x,y
def newpart(kind,label,x,y,z=25.13):
    i=counters[kind]; counters[kind]+=1; slug=f'{kind}_{i:02d}'; return Part(slug,label+f'_{i:02d}','facilities',(x,y,z),kind)
def finish_prop(p):
    if p.definition=='camp_tent':
        p.v=[(p.origin.x+(v[0]-p.origin.x)*.69,p.origin.y+(v[1]-p.origin.y)*.69,v[2]) for v in p.v]
    p.finish(); catalog[-1]['platform_scope']=True; new_props.append(p.slug)
def bolt(p,x,y,z,r=.035): p.rod((x,y,z),(x,y,z+.025),r,LIGHT,0,6)
def woodcrate(x,y,z=25.13,size=1.05):
    p=newpart('wood_supply_crate','木质补给箱_板缝斜撑护角',x,y,z); s=size
    p.box((x,y,z+s*.5),(s,s*.86,s),WOOD,1,.035)
    for i in range(5):
        xx=x-s*.42+i*s*.21; p.box((xx,y-s*.438,z+s*.5),(.026,.025,s*.88),RUST)
    for dy in (-s*.46,s*.46):
        for dz in (.12,.86): p.box((x,y+dy,z+s*dz),(s+.07,.07,.10),GOLD,1,.012)
        p.rod((x-s*.42,y+dy-.05,z+.18*s),(x+s*.42,y+dy-.05,z+.82*s),.045,GOLD,1,4)
    for dx in (-.42*s,.42*s):
        for dy in (-.42*s,.42*s): p.box((x+dx,y+dy,z+s*.52),(.09,.09,s+.03),STEEL,0,.018)
    p.box((x,y-s*.49,z+s*.64),(.22,.016,.15),TILE,1,.012); finish_prop(p)
def case(x,y,z=25.13):
    p=newpart('reinforced_supply_case','护角物资箱_箱盖扣件与把手',x,y,z)
    p.box((x,y,z+.43),(1.35,.82,.84),(5,4),1,.06); p.box((x,y,z+.87),(1.42,.88,.12),(6,4),1,.045)
    for dx in (-.57,.57):
        p.box((x+dx,y,z+.45),(.10,.88,.82),STEEL,0,.022)
        for dy in (-.43,.43):
            p.box((x+dx,y+dy,z+.84),(.14,.08,.23),TILE2,0,.02); bolt(p,x+dx,y+dy,z+.96)
    p.rod((x-.22,y-.49,z+.56),(x+.22,y-.49,z+.56),.035,STEEL,0,8)
    for dx in (-.23,.23): p.rod((x+dx,y-.43,z+.67),(x+dx,y-.49,z+.56),.035,STEEL,0,8)
    p.box((x+.23,y-.43,z+.31),(.27,.018,.14),TILE,1,.008); finish_prop(p)
def water(x,y,z=25.13):
    p=newpart('ibc_water_tank','笼式储水箱_托盘阀门水管',x,y,z)
    p.box((x,y,z+.10),(1.42,1.22,.20),STEEL,0,.04)
    for xx in (-.48,0,.48): p.box((x+xx,y,z+.04),(.2,1.1,.08),DARK)
    p.box((x,y,z+.83),(1.24,1.03,1.32),TILE,1,.09)
    for zz in (.31,.65,1.0,1.37):
        p.path([(x-.67,y-.57,z+zz),(x+.67,y-.57,z+zz),(x+.67,y+.57,z+zz),(x-.67,y+.57,z+zz),(x-.67,y-.57,z+zz)],.032,STEEL,0,6)
    for dx in (-.65,-.22,.22,.65):
        for dy in (-.57,.57): p.rod((x+dx,y+dy,z+.22),(x+dx,y+dy,z+1.44),.031,STEEL,0,6)
    for dy in (-.23,.23):
        for dx in (-.67,.67): p.rod((x+dx,y+dy,z+.22),(x+dx,y+dy,z+1.44),.031,STEEL,0,6)
    p.rod((x,y,z+1.46),(x,y,z+1.55),.17,DARK,1,16)
    p.rod((x,y-.49,z+.30),(x,y-.72,z+.30),.07,STEEL,0,10)
    p.box((x,y-.73,z+.40),(.24,.08,.045),RED,1,.015)
    p.box((x+.24,y-.532,z+.92),(.30,.012,.20),CREAM,1,.015); finish_prop(p)
def drum(x,y,z=25.13,c=BLUE):
    p=newpart('steel_drum','金属储物桶_卷边加强圈与封口',x,y,z)
    p.rod((x,y,z+.06),(x,y,z+1.05),.36,c,0,20)
    for h in (.07,.31,.79,1.04): p.rod((x,y,z+h-.026),(x,y,z+h+.026),.377,STEEL,0,20)
    p.rod((x+.15,y+.08,z+1.07),(x+.15,y+.08,z+1.095),.065,DARK,0,10)
    for i in range(3):
        a=i*.8+1; p.poly([(x+.365*math.cos(a),y+.365*math.sin(a),z+.4),(x+.365*math.cos(a+.3),y+.365*math.sin(a+.3),z+.47),(x+.365*math.cos(a+.2),y+.365*math.sin(a+.2),z+.65)],[(0,1,2)],RUST,0)
    finish_prop(p)
def solar(x,y,z=25.13):
    p=newpart('folding_solar_panel','折叠光伏板_分格电池与三角支架',x,y,z)
    origin=Vector((x,y-.52,z+.22)); u=Vector((1,0,0)); v=Vector((0,.55,.84))
    def pt(a,b): return origin+u*a+v*b
    p.poly([pt(-.85,0),pt(.85,0),pt(.85,1.7),pt(-.85,1.7)],[(0,1,2,3)],(8,6),2)
    for a in (-.89,.89): p.rod(pt(a,0),pt(a,1.74),.045,TILE2,0,8)
    for b in (0,1.74): p.rod(pt(-.89,b),pt(.89,b),.045,TILE2,0,8)
    for j in range(6):
        for k in range(4):
            a=-.80+k*.40; b=.06+j*.27
            p.poly([pt(a,b)+Vector((0,-.008,.005)),pt(a+.35,b)+Vector((0,-.008,.005)),pt(a+.35,b+.22)+Vector((0,-.008,.005)),pt(a,b+.22)+Vector((0,-.008,.005))],[(0,1,2,3)],(4,6),2)
    for a in (-.72,.72):
        p.rod(pt(a,1.55),(x+a,y+.72,z+.08),.045,STEEL,0,8); p.rod((x+a,y-.55,z+.08),(x+a,y+.72,z+.08),.045,STEEL,0,8)
    finish_prop(p)
def tent(x,y,z=25.13):
    p=newpart('camp_tent','营地帆布棚_脊梁垂边拉绳与支脚',x,y,z)
    # Honest framed canopy: 4.2 x 2.8m, center ridge 2.65m, sides 2.10m.
    for dx in (-2.1,2.1):
        for dy in (-1.4,1.4):
            p.box((x+dx,y+dy,z+.04),(.25,.25,.08),STEEL,0,.03)
            p.rod((x+dx,y+dy,z+.08),(x+dx,y+dy,z+2.14),.045,STEEL,0,8)
            p.rod((x+dx,y+dy,z+2.05),(x+dx*1.3,y+dy*1.35,z+.05),.012,GOLD,1,6)
            p.rod((x+dx*1.3,y+dy*1.35,z),(x+dx*1.3,y+dy*1.35,z+.16),.025,STEEL,0,6)
    for xx in (x-2.1,x,x+2.1):
        p.rod((xx,y-1.4,z+2.1),(xx,y,z+2.65),.04,STEEL,0,8); p.rod((xx,y,z+2.65),(xx,y+1.4,z+2.1),.04,STEEL,0,8)
    p.rod((x-2.18,y,z+2.65),(x+2.18,y,z+2.65),.045,STEEL,0,8)
    for side in (-1,1):
        for j in range(6):
            a=x-2.25+j*.75; b=a+.75; edge=z+2.07
            def cloth(u,v):
                return (a+.75*u,y+side*1.6*v,z+2.68-.61*v-.095*math.sin(math.pi*u)*math.sin(math.pi*v)-.035*math.sin(math.pi*u)*v)
            for uu in range(4):
                for vv in range(5):
                    p.poly([cloth(uu/4,vv/5),cloth((uu+1)/4,vv/5),cloth((uu+1)/4,(vv+1)/5),cloth(uu/4,(vv+1)/5)],[(0,1,2,3)],(6,4) if j%3 else (7,4))
            for uu in range(4):
                a0=cloth(uu/4,1); b0=cloth((uu+1)/4,1)
                p.poly([a0,b0,(b0[0],b0[1]-.025*side,b0[2]-.18),(a0[0],a0[1]-.025*side,a0[2]-.18)],[(0,1,2,3)],(6,4))
            p.path([cloth(0,v/5) for v in range(6)],.008,(7,4),1,6)
    # Rear curtain and rolled front side returns leave a clearly open doorway.
    for j in range(8):
        a=x-2.1+j*.525; b=a+.525; yy=y+1.38+(.055 if j%2 else 0)
        p.poly([(a,yy,z+.10),(b,yy,z+.10),(b,yy,z+2.12),(a,yy,z+2.12)],[(0,1,2,3)],(5,4) if j%2 else (6,4))
    for dx in (-1.9,1.9): p.rod((x+dx,y-1.4,z+.35),(x+dx,y-1.4,z+1.98),.11,(6,4),1,10)
    p.rod((x,y-.2,z+2.6),(x,y-.2,z+2.3),.02,STEEL,0)
    p.box((x,y-.2,z+2.21),(.20,.20,.23),GOLD,3,.03); p.box((x,y-.2,z+2.36),(.26,.26,.045),STEEL,0,.02)
    finish_prop(p)

camp_centers=[]
for i,pref in enumerate([(-63,16),(-32,14),(-8,5),(31,-6),(43,-8),(55,-18)]):
    x,y=place(pref,3.9,2.9,f'camp_{i:02d}',max_shift=13); camp_centers.append((x,y)); tent(x,y,ground(x,y))
    # Independent props, arranged at the sides, never welded into a camp mega-mesh.
    recipes=[(water,(x+3.8,y),1.55,1.55),(case,(x-3.5,y-.6),1.5,1.1),(woodcrate,(x-3.4,y+1),1.2,1.2),(solar,(x+2.8,y-2.8),1.95,1.8),(drum,(x-2.7,y-2.7),.85,.85)]
    for j,(fn,pref,w,d) in enumerate(recipes):
        xx,yy=place(pref,w,d,f'camp_{i:02d}_prop_{j}',max_shift=9); fn(xx,yy,ground(xx,yy))

# Secondary supplies form small grouped stories near shelter entrances.
for i,(x,y) in enumerate(camp_centers):
    for j,fn in enumerate((case,woodcrate,drum)):
        xx,yy=place((x+2.6-j*2.4,y+2.8),1.5 if j==0 else 1.2,1.1 if j==0 else 1.2,f'camp_{i:02d}_secondary_{j}',max_shift=8); fn(xx,yy,ground(xx,yy))

# Restrained localized growth. Each patch <=3m XY and has a specific host.
def vine(x,y,z,length,host,index):
    p=Part(f'vine_patch_{index:02d}',f'局部藤蔓_{index:02d}_宿主挂点','garden',(x,y,z-length),'contained_vine_patch')
    rng=random.Random(50500+index)
    for strand in range(3):
        pts=[(x+(strand-1)*.23+.13*math.sin(i*.8+strand),y+.10*math.cos(i*.7+strand),z-i*length/11) for i in range(12)]
        p.path(pts,.016,SOIL,1,6)
        for j,(xx,yy,zz) in enumerate(pts[1:]):
            for side in (-1,1): blade(p,xx,yy,zz,side*1.7+strand*.6,.18+rng.random()*.12,LEAF if j%3 else GREEN)
    p.finish(); options=[q for q in catalog if q.get('previous_package_id')=='tower_04/'+host or q['slug']==host]
    if options:
        nearest=min(options,key=lambda q:math.dist(q['world_position'][:2],[x,y])); catalog[-1]['dependencies']=[nearest['package_id']]
    vine_records.append(dict(slug=p.slug,host=host,position=[x,y,z],length_m=length))
anchors=[(-44.1,16.85,28.25,2.35,'canopy_column_00'),(20.4,4.5,28.25,2.1,'canopy_column_03'),(-43,19.8,29.75,1.8,'leaf_canopy'),(-16,11.9,29.75,1.5,'leaf_canopy'),(11,5.7,29.75,1.45,'leaf_canopy'),(28,4.7,29.75,1.7,'leaf_canopy')]
# Find known boundary positions; outside drop attaches to the platform, not air.
edge=LineString(deck.buffer(-.55).exterior.coords)
for distance in (16,50,91,142,181,235):
    q=edge.interpolate(min(distance,edge.length-.1)); anchors.append((q.x,q.y,25.15,1.3,'terrace_shell'))
for i,a in enumerate(anchors): vine(*a,i)

# Small foliage clusters rooted in beds, never placed over the running corridor.
for i,(s,g) in enumerate(greens.items()):
    if s=='lawn_court': continue
    center=g.representative_point(); p=Part(f'bed_growth_{i:02d}',f'花池局部返野叶簇_{i:02d}','garden',(center.x,center.y,25.6),'contained_bed_growth')
    rng=random.Random(505+i)
    for j in range(min(20,max(3,int(g.area*.8)))):
        xx=rng.uniform(g.bounds[0],g.bounds[2]); yy=rng.uniform(g.bounds[1],g.bounds[3])
        if not g.buffer(-.25).contains(Point(xx,yy)): continue
        zz=25.52 if s.startswith('court_') else 25.65
        for k in range(6): blade(p,xx,yy,zz,k*math.tau/6,.28+(k%3)*.11,LEAF if k%2 else (7,3))
    if p.v:
        # Dense rear garden is spatially split too; no patch crosses 10m cells.
        bounds=[max(v[k] for v in p.v)-min(v[k] for v in p.v) for k in range(3)]
        split_finish(p,dict(slug=p.slug,dimensions=bounds,package_id='tower_04/'+s))

bpy.context.view_layer.update()
assert before=={n:signature(bpy.data.objects[n]) for n in before},'Locked structure or original lighting changed'
assert material_signature()==mat_before and len(bpy.data.materials)==4
game.name='02_游戏输出_独立资产包_v005'; sc['version']='v005'; sc['scope']='末世平台分区与独立组件；下部建筑锁定'
# Add spatial browsing branches under each category; leaves remain independent.
for category,parent in CATS.items():
    bins={}
    for info in catalog:
        if info['category']!=category or info['slug'] in locked_slugs: continue
        key=info.get('zone_id',zone(info['world_position'][0]))
        if key not in bins: bins[key]=coll(key+'区_'+zones[key]+'_'+cats[category],parent)
        c=bpy.data.collections[info['collection']]
        if c.name in parent.children: parent.children.unlink(c)
        bins[key].children.link(c)
        info['zone_id']=key; info['zone_name']=zones[key]; info['platform_scope']=True
        assert max(info['dimensions'][:2])<=10.0002,('Oversized platform leaf',info['slug'],info['dimensions'])

# A dedicated atmosphere scene shares the asset geometry, with its own light rig.
rig=coll('91_黄昏氛围_仅展示',sc.collection)
def camera(name,pos,target,lens=32):
    data=bpy.data.cameras.new(name); data.lens=lens; data.clip_start=.1; data.clip_end=1000
    o=bpy.data.objects.new(name,data); rig.objects.link(o); o.location=pos; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); o['resolution_x']=1600; o['resolution_y']=1000; return o
camera('CAM_末世_平台总览',(126,-146,127),(0,2,25),47)
camera('CAM_末世_棚下主街',(-47,10.2,27.0),(15,4,27.1),25)
camera('CAM_末世_右侧营地',(58,-18,28.0),(35,-3,26.8),34)
camera('CAM_末世_棚柱节点',(28,-5.4,27.1),(20.4,4.5,28.1),30)
cx,cy=camp_centers[3]; camera('CAM_末世_营地设施近景',(cx+7,cy-7,27.5),(cx,cy,26.2),38)
camera('CAM_末世_地表近景',(11,-6,27.1),(8,-2,25.1),40)
sun_data=bpy.data.lights.new('末世夕阳','SUN'); sun_data.energy=4.5; sun_data.color=(1.0,.51,.22); sun_data.angle=.13
sun=bpy.data.objects.new(sun_data.name,sun_data); rig.objects.link(sun); sun.rotation_euler=Vector((40,60,-65)).to_track_quat('-Z','Y').to_euler()
fill_data=bpy.data.lights.new('天空冷色柔光','AREA'); fill_data.energy=6000; fill_data.color=(.68,.79,1); fill_data.shape='DISK'; fill_data.size=80
fill=bpy.data.objects.new(fill_data.name,fill_data); rig.objects.link(fill); fill.location=(0,0,80)
mood=sc.copy(); mood.name='塔4_黄昏末世氛围'; mood.use_fake_user=True; mood.world=sc.world.copy(); mood.world.name='黄昏天空_独立展示环境'
mood.world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.21,.29,1); mood.world.node_tree.nodes['Background'].inputs[1].default_value=.60
mood.view_settings.exposure=.70; mood.camera=bpy.data.objects['CAM_末世_平台总览']
def layer(root,name):
    if root.collection.name==name: return root
    for c in root.children:
        found=layer(c,name)
        if found:return found
layer(sc.view_layers[0].layer_collection,rig.name).exclude=True
layer(mood.view_layers[0].layer_collection,display.name).exclude=True
sc['mood_scene']=mood.name
by_id={p['package_id']:p for p in catalog}
for info in catalog:
    previous=oldmap.get(info.get('previous_package_id','').split('/')[-1])
    if not previous: continue
    for key in ('tile_row','tile_column','tile_fragment'):
        if key in previous: info[key]=previous[key]
    deps=[]
    for dep in previous.get('dependencies',[]):
        if dep in by_id: deps.append(dep); continue
        candidates=[q for q in catalog if q.get('previous_package_id')==dep]
        a=box(*info['bounds_min'][:2],*info['bounds_max'][:2])
        touching=[q for q in candidates if a.intersects(box(*q['bounds_min'][:2],*q['bounds_max'][:2]))]
        if not touching and candidates: touching=[min(candidates,key=lambda q:math.dist(q['world_position'][:2],info['world_position'][:2]))]
        deps.extend(q['package_id'] for q in touching)
    if deps: info['dependencies']=sorted(set(deps))
assert all(d in by_id for p in catalog for d in p.get('dependencies',[]))
for info in catalog:
    folder=OUT/'component_packages'/info['category']/info['slug']; folder.mkdir(parents=True,exist_ok=True)
    (folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
meta.update(version='v005',source_blend=BLEND.relative_to(R).as_posix(),packages=catalog,package_count=len(catalog),component_definition_count=len({p['component_definition'] for p in catalog}),source_status='apocalypse_platform_pending_validation',locked_asset_hashes=files,scope=planning['scope'])
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p.get('zone_id','LOCKED')+'/'+p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')
report=dict(stage='built_pending_reopen',locked_objects=len(before),locked_match=before=={n:signature(bpy.data.objects[n]) for n in before},decomposition=decomposition,placements=placements,camp_centers=camp_centers,new_prop_packages=new_props,vine_patches=vine_records,counters=dict(counters),module_limit_xy_m=10,materials=4,new_materials=0,original_files=files)
(OUT/'qa/build_plan_result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
assert before=={n:signature(bpy.data.objects[n]) for n in before}
assert mat_before==material_signature() and len(bpy.data.materials)==4
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('APOCALYPSE_SAVED',str(BLEND),len(catalog),dict(counters),flush=True)
