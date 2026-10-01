"""Tower04 reference-led mall; author source only, never edit shared assets.

Blender 4.5 --background --python this_file [-- --no-render]
Uses existing four material datablocks, not newly authored materials.
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
from collections import Counter
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

R = Path(__file__).resolve().parents[2]
OUT = R / 'assets/art/environments/open_world/source/tower_04/v001'
BLEND = OUT / '塔4_曲线天台商场_150x50m_v001.blend'
ASSET = 'ENV-OPENWORLD-TOWER04'
DONOR = R / 'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
PALETTE = R / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
REFERENCE = Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-11766f86-3de6-427e-9297-0676dc9e5c70.png')
NAMES = ['01_精工金属_紫色骨架', '02_细腻哑光_青绿大面', '03_清漆反光_紫粉点缀', '04_柔和自发光_UI灯光']
for d in ('qa', 'previews', 'references', 'component_packages'):
    (OUT / d).mkdir(parents=True, exist_ok=True)
if BLEND.exists():
    assert '--draft-sha' in sys.argv, 'Existing source: create next version instead of overwrite'
    expected = sys.argv[sys.argv.index('--draft-sha')+1]
    assert hashlib.sha256(BLEND.read_bytes()).hexdigest() == expected, 'Draft edited externally; do not overwrite'
random.seed(4004)
locked = {str(p.relative_to(R)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (DONOR, PALETTE, Path(str(PALETTE)+'.import'))}
shutil.copy2(REFERENCE, OUT / 'references/用户参考_曲线商场.png')
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'
sc.unit_settings.scale_length = 1
sc['asset_id'] = ASSET
sc['version'] = 'v001'
sc['block_id'] = 'open_world'
sc['floor_count'] = 5
sc['floor_height_m'] = 5
sc['roof_z_m'] = 25
sc['terrace_z_m'] = 15
sc['asset_ledger'] = 'scenes::资产主表::' + ASSET
sc['scene_design_docs'] = 'docs/v0.1/design/tower04_mall_source.md'
with bpy.data.libraries.load(str(DONOR), link=False) as (available, target):
    assert all(n in available.materials for n in NAMES), available.materials
    target.materials = list(NAMES)
MATS = [bpy.data.materials[n] for n in NAMES]
# Relink appended image path only; do not change original materials' shader values.
for mat in MATS:
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image:
            node.image.filepath = str(PALETTE)
            node.image.reload()
palette = next(n.image for n in MATS[1].node_tree.nodes if n.type == 'TEX_IMAGE')
pixels = list(palette.pixels)
def color(rgb):
    candidates = []
    for row in range(10):
        for col in range(10):
            x = int((col+.5)*512/10); y = int((9-row+.5)*512/10)
            value = pixels[(y*512+x)*4:(y*512+x)*4+3]
            candidates.append((sum((a-b)**2 for a,b in zip(value, rgb)), (col,row)))
    return min(candidates)[1]
CREAM = color((.72,.75,.78)); LIGHT = color((.83,.85,.86))
TILE = color((.61,.68,.71)); TILE2 = color((.53,.62,.65))
DARK = color((.12,.20,.24)); STEEL = color((.28,.40,.45))
BLUE = color((.15,.47,.53)); BLUEHI = color((.37,.65,.69))
WARM = color((.68,.38,.24)); GOLD = color((.90,.56,.17))
GREEN = (4,4); LEAF = (5,4); LEAFHI = (6,4)
WARM = (7,2)
SOIL = color((.22,.24,.16)); TEAL = BLUE; RUST = WARM

# Reuse the project's explicit geometry/PaletteUV primitives, without executing
# its scene builder or material creation section.
helper = R / 'tools/blender/build_skyline_08_source_v001.py'
syntax = ast.parse(helper.read_text(encoding='utf8'))
nodes = [n for n in syntax.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('coll','uv_mesh','Part')]
exec(compile(ast.Module(body=nodes,type_ignores=[]), str(helper), 'exec'), globals())
BasePart = Part
root = coll('塔4_曲线商场_中文资产管理', sc.collection)
src = coll('01_制作组件_按独立资产包',root); src.hide_viewport=True; src.hide_render=True
game = coll('02_游戏输出_独立资产包_v001',root)
display = coll('90_展示与验收_固定灯光相机',root)
categories = [('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('garden','04_曲线景观'),('support','05_环境支持')]
CATS = {k:coll(n,game) for k,n in categories}
SCATS = {k:coll(n+'_制作源',src) for k,n in categories}
catalog=[]

class Part(BasePart):
    def prism(self, points, bottom, top, c=CREAM, m=1):
        points=[Vector((x,y,0)) for x,y in points]
        tris=tessellate_polygon([points]); lookup={tuple(v):i for i,v in enumerate(points)}
        triangles=[tuple(v if isinstance(v,int) else lookup[tuple(v)] for v in t) for t in tris]
        n=len(points)
        verts=[(v.x,v.y,z) for z in (bottom,top) for v in points]
        faces=[tuple(reversed(t)) for t in triangles]+[tuple(i+n for i in t) for t in triangles]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        self.poly(verts,faces,c,m)
    def finish(self):
        gc=coll(self.name+'_资产包',CATS[self.category])
        source_c=coll(self.name+'_制作组件',SCATS[self.category])
        package_id='tower_04/'+self.slug
        gc['package_id']=package_id
        objects=[]
        for emissive in (False,True):
            select=[i for i,m in enumerate(self.mi) if (m==3)==emissive]
            if not select: continue
            used=sorted({j for i in select for j in self.f[i]}); mapping={old:new for new,old in enumerate(used)}
            mesh=bpy.data.meshes.new(self.name+('_灯光网格' if emissive else '_主体网格'))
            mesh.from_pydata([tuple(Vector(self.v[j])-self.origin) for j in used],[],[tuple(mapping[j] for j in self.f[i]) for i in select]); mesh.update()
            uv_mesh(mesh,[self.co[i] for i in select],[0 if emissive else self.mi[i] for i in select],[MATS[3]] if emissive else MATS[:3])
            ob=bpy.data.objects.new(self.name+('_柔和自发光' if emissive else '_主体'),mesh)
            gc.objects.link(ob); ob.location=self.origin
            for key,val in dict(asset_id=ASSET,package_id=package_id,version='v001',component_definition=self.definition,front_direction='-Y',block_id='open_world',fixed_display_attachment=True).items(): ob[key]=val
            so=ob.copy(); so.data=mesh.copy(); so.name=ob.name+'_制作源'; source_c.objects.link(so)
            objects.append(ob)
        mn=[min(v[j] for v in self.v) for j in range(3)]; mx=[max(v[j] for v in self.v) for j in range(3)]
        info=dict(asset_id=ASSET,package_id=package_id,slug=self.slug,display_name=self.name,category=self.category,version='v001',source_blend=BLEND.relative_to(R).as_posix(),collection=gc.name,source_collection=source_c.name,objects=[o.name for o in objects],root_object=objects[0].name,world_position=list(self.origin),local_origin=[0,0,0],front_direction='-Y',bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)],material_roles=NAMES,material_source=DONOR.relative_to(R).as_posix(),animation=False,emissive=any(m==3 for m in self.mi),component_definition=self.definition,dependencies=[],fixed_display_attachment=True,collision_status='not_authored',exported=False,expected_export=self.slug+'.glb',block_id='open_world',floor_range='1F–5F及错层天台',scene_design_docs=['docs/v0.1/design/tower04_mall_source.md'],asset_ledger='scenes::资产主表::'+ASSET)
        folder=OUT/'component_packages'/self.category/self.slug; folder.mkdir(parents=True,exist_ok=True)
        (folder/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8'); catalog.append(info)
        return objects

def ellipse(cx,cy,rx,ry,n=64):
    return [(cx+rx*math.cos(math.tau*i/n),cy+ry*math.sin(math.tau*i/n)) for i in range(n)]

def bezier(a,b,c,d,n=14):
    return [tuple((1-t)**3*a[j]+3*(1-t)**2*t*b[j]+3*(1-t)*t*t*c[j]+t**3*d[j] for j in range(2)) for t in [i/n for i in range(n)]]

def boundary(curves):
    return [q for curve in curves for q in bezier(*curve)]

def sample_rail(p,points,z,closed=True,glass=True):
    pts=list(points)+([points[0]] if closed else [])
    p.path([(*q,z+1.20) for q in pts],.07,LIGHT,0,8)
    p.path([(*q,z+.14) for q in pts],.055,STEEL,0,6)
    for a,b in zip(pts,pts[1:]):
        p.rod((*a,z+.10),(*a,z+1.20),.055,STEEL,0)
        if glass:
            aa=Vector(a); bb=Vector(b); delta=(bb-aa)*.055
            p.poly([(*(aa+delta),z+.20),(*(bb-delta),z+.20),(*(bb-delta),z+1.12),(*(aa+delta),z+1.12)],[(0,1,2,3)],BLUEHI,2)

def facade(slug,name,points,z0,z1,levels,closed=True):
    p=Part(slug,name,'architecture',(0,0,z0),'facade_curve')
    pts=list(points)+([points[0]] if closed else [])
    for a,b in zip(pts,pts[1:]):
        av=Vector(a); bv=Vector(b); edge=bv-av
        p.rod((*a,z0+.30),(*a,z1-.28),.12,STEEL,0)
        for k in range(levels):
            bottom=z0+5*k+.45; top=min(z0+5*(k+1)-.30,z1-.30)
            if top<=bottom: continue
            aa=av+edge*.07; bb=bv-edge*.07
            p.poly([(*aa,bottom),(*bb,bottom),(*bb,top),(*aa,top)],[(0,1,2,3)],BLUE if k%2 else BLUEHI,2)
            # Large restrained diagonal highlight, not a repeating texture.
            if len(p.f)%5==0:
                p.poly([(*(aa+edge*.09),bottom+.12),(*(bb-edge*.08),top-.12),(*aa,top-.12)],[(0,1,2)],TILE,2)
            p.rod((*a,z0+5*k+.26),(*b,z0+5*k+.26),.09,STEEL,0)
    p.finish()

definitions=['ellipse_storey','curved_strip_storey','facade_curve','scalloped_terrace','elliptic_roof_curb','roof_paving','glass_guardrail','lattice_canopy','forked_canopy_column','elliptic_planter','garden_cluster','glass_pavilion','hvac_unit','service_hut','drain_bank','lighting_bollard','entrance_portal','curved_rooftop_stair','fixed_garden_bench']
plan=dict(asset_id=ASSET,version='v001',definition_count=len(definitions),definitions=definitions,footprint_m=[150,50],floor_count=5,floor_height_m=5,highest_body_roof_m=25,terrace_m=15,style='Fortnite式块面、克制的宽倒角、低多边形植被，禁止写实纹理',material_policy='只读取塔楼03既有四材质，不新建或复制材质球；公共色盘外链',reference_layout='左椭圆高体块；中部凹入；前沿波浪露台；后侧长曲线格构顶；右端玻璃亭',locked_asset_hashes=locked)
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')

# Left oval: five real storeys, level slabs rather than a stretched cylinder.
oval=ellipse(-50,-3,24.5,20.5,64)
for level in range(5):
    z=level*5
    p=Part('oval_level_%02d'%(level+1),'左翼椭圆商场_%02d层'%(level+1),'architecture',(-50,-3,z),'ellipse_storey')
    p.prism(oval,z,z+.42,LIGHT)
    p.path([(*q,z+.44) for q in oval+[oval[0]]],.18,CREAM,1,8)
    p.prism(ellipse(-50,-3,23.8,19.8),z+.43,z+.59,TILE)
    # Dark interior shell sits behind the segmented stylized glazing.
    p.prism(ellipse(-50,-3,23.45,19.45),z+.59,z+4.48,DARK)
    p.path([(*q,z+4.60) for q in oval+[oval[0]]],.18,LIGHT,1,8)
    p.finish()
facade('oval_glazing','左翼五层圆弧幕墙',oval,0,25,5)
p=Part('oval_roof','左翼回旋屋顶_环形檐口','floor',(-50,-3,25),'elliptic_roof_curb')
p.prism(oval,24.62,25,CREAM)
for cx,cy,rx,ry,h in [(-50,-3,23.3,19.3,.35),(-41,1,10,8,.80)]:
    ring=ellipse(cx,cy,rx,ry)
    if rx==10:
        # Open returning spiral rather than a closed circular puck.
        ring=[q for i,q in enumerate(ring) if i<51]
        p.prism(ellipse(cx,cy,rx-.45,ry-.45),25,25.28,TILE)
        p.path([(*q,25+h*.5) for q in ring],h*.5,LIGHT,1,8)
    else: p.path([(*q,25+h*.5) for q in ring+[ring[0]]],h*.5,LIGHT,1,8)
for x in range(-68,-30,6):
    extent=18.7*math.sqrt(max(0,1-((x+50)/23)**2))
    p.rod((x,-3-extent,25.022),(x,-3+extent,25.022),.025,TILE2,1,6)
for y in (-14,-8,-2,4,10):
    extent=23.0*math.sqrt(max(0,1-((y+3)/18.7)**2))
    p.rod((-50-extent,y,25.025),(-50+extent,y,25.025),.025,TILE2,1,6)
p.finish()
p=Part('oval_roof_rail','左翼回旋屋顶玻璃护栏','support',(-50,-3,25),'glass_guardrail')
sample_rail(p,ellipse(-50,-3,23.4,19.4,48),25); p.finish()

# Dominant terrace silhouette: exact Bezier boundary, not a rectangular platform.
outline=boundary([
    ((-34,-9),(-23,-2),(-23,-10),(-12,-14)),
    ((-12,-14),(-5,-19),(6,-8),(15,-14)),
    ((15,-14),(30,-16),(42,-26),(53,-24)),
    ((53,-24),(67,-24),(75,-18),(74,-11)),
    ((74,-11),(75,1),(75,12),(70,15)),
    ((70,15),(56,20),(43,18),(30,21)),
    ((30,21),(14,24),(-8,23),(-27,23)),
    ((-27,23),(-39,24),(-43,19),(-43,11)),
    ((-43,11),(-43,3),(-38,-3),(-34,-9)),
])
# Normalize boundary to requested total silhouette width/depth, accounting oval.
# Main combined shell has exact 150m X and 50m Y envelope after 0.5m edge bands.
outline=[(x,y) for x,y in outline]
front=outline[:56]
wing=boundary([
    ((-24,-8),(-7,-10),(12,-9),(26,-13)),
    ((26,-13),(43,-18),(63,-20),(71,-13)),
    ((71,-13),(74,-5),(72,7),(67,10)),
    ((67,10),(35,14),(2,17),(-24,17)),
    ((-24,17),(-31,10),(-31,-4),(-24,-8)),
])
for level in range(3):
    z=level*5
    p=Part('wing_level_%02d'%(level+1),'长翼零售层_%02d层'%(level+1),'architecture',(0,0,z),'curved_strip_storey')
    p.prism(wing,z,z+.42,CREAM)
    center=(19,0)
    inner=[(center[0]+(x-center[0])*.99,y*.965) for x,y in wing]
    p.prism(inner,z+.42,z+4.5,DARK)
    p.path([(*q,z+4.7) for q in wing+[wing[0]]],.18,LIGHT,1,8)
    p.finish()
facade('wing_glazing','长翼三层曲线幕墙',wing,0,15,3)
p=Part('terrace_shell','波浪悬挑露台_连续曲线壳体','architecture',(0,0,14),'scalloped_terrace')
p.prism(outline,13.80,15,LIGHT)
p.path([(*q,14.8) for q in outline+[outline[0]]],.16,CREAM,1,8)
p.finish()
p=Part('terrace_rail','波浪露台_全边界玻璃护栏','support',(0,0,15),'glass_guardrail')
sample_rail(p,outline,15); p.finish()
# Paving follows the outline, with broad main terracotta promenade and segments.
p=Part('promenade','曲线主步道_暖色块面铺装','floor',(0,0,15),'roof_paving')
walk=boundary([((-27,9),(-2,14),(21,11),(65,-7)),((65,-7),(67,-8),(69,-5),(66,-3)),((66,-3),(33,20),(7,19),(-27,13)),((-27,13),(-30,12),(-30,10),(-27,9))])
p.prism(walk,15.012,15.065,WARM)
for x in range(-20,64,6):
    y=12-.000085*(x+10)**3
    p.box((x,y,15.075),(.07,3.4,.025),CREAM,1)
p.finish()
# Retain each local terrace tile as a separate replaceable package, clip to outline.
def inside(x,y,poly):
    yes=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>y)!=(b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: yes=not yes
    return yes
for ix,x in enumerate(range(-32,73,7)):
    for iy,y in enumerate(range(-21,22,7)):
        corners=[(x-3.44,y-3.44),(x+3.44,y-3.44),(x+3.44,y+3.44),(x-3.44,y+3.44)]
        if all(inside(a,b,outline) for a,b in corners) and not inside(x,y,walk):
            p=Part('paving_%02d_%02d'%(ix,iy),'露台铺装_%02d_%02d'%(ix,iy),'floor',(x,y,15),'roof_paving')
            p.prism(corners,15.004,15.020,TILE if (ix+iy)%3 else CREAM); p.finish()

# Vertical piers supporting the suspended terrace: oversize chamfered cylinders.
for i,(x,y) in enumerate([(-20,-13),(7,-16),(36,-21),(63,-20),(72,-1)]):
    p=Part('pier_%02d'%i,'悬挑露台承重柱_%02d'%i,'architecture',(x,y,0),'forked_canopy_column')
    p.rod((x,y,.08),(x,y,13.8),1.25,CREAM,1,20)
    for z in (0.3,5,10,13.4): p.rod((x,y,z),(x,y,z+.12),1.31,LIGHT,1,20)
    p.finish()

# Long leaf/lens canopy. Two continuous curved edges with a real diamond lattice.
def canopy_center(x): return 16-.0010*(x+7)**2
def canopy_z(x): return 22+.027*(35-x)
canopy_x=[-41+i*76/36 for i in range(37)]
width=[5.8*math.sqrt(max(.003,1-((x+3)/38.1)**2)) for x in canopy_x]
topside=[(x,canopy_center(x)+w,canopy_z(x)) for x,w in zip(canopy_x,width)]
bottomside=[(x,canopy_center(x)-w,canopy_z(x)) for x,w in zip(canopy_x,width)]
p=Part('leaf_canopy','长叶形遮阳顶_连续曲线边框','support',(0,0,22),'lattice_canopy')
p.path(topside+list(reversed(bottomside))+[topside[0]],.22,LIGHT,1,10)
for shift in (-.53,0,.53):
    p.path([(x,canopy_center(x)+shift*w,canopy_z(x)) for x,w in zip(canopy_x,width)],.105,CREAM,1,8)
for i in range(len(canopy_x)-1):
    x=canopy_x[i]; xx=canopy_x[i+1]; w=width[i]; ww=width[i+1]
    for j in range(4):
        s0=-1+j*.5; s1=s0+.5
        a=(x,canopy_center(x)+s0*w,canopy_z(x)); b=(xx,canopy_center(xx)+s1*ww,canopy_z(xx))
        c=(x,canopy_center(x)+s1*w,canopy_z(x)); d=(xx,canopy_center(xx)+s0*ww,canopy_z(xx))
        p.rod(a,b,.065,LIGHT,1,6); p.rod(c,d,.065,LIGHT,1,6)
        # Sparse sail plates: lattice is open and reads clearly from the reference.
        if (i+j)%4==0: p.poly([a,b,c],[(0,1,2)],TILE,1)
p.finish()
for i,x in enumerate((-32,-14,4,20,31)):
    y=canopy_center(x); z=canopy_z(x)
    p=Part('canopy_column_%02d'%i,'遮阳棚树形分叉柱_%02d'%i,'support',(x,y,15),'forked_canopy_column')
    p.rod((x,y,15),(x,y,z-2),.40,LIGHT,1,12)
    for dx,dy in [(-1.8,-3.0),(1.8,3.0)]:
        p.rod((x,y,z-3.2),(x+dx,y+dy,z-.08),.21,CREAM,1,10)
    p.rod((x,y,15.02),(x,y,15.30),.60,CREAM,1,16); p.finish()

# Scenic low-poly flora: large chunky masses and stylized palm leaf fans.
def blob(p,x,y,z,r,c):
    verts=[]
    for k,(zz,rr) in enumerate([(-.65,.35),(-.3,.85),(.22,1),(.65,.73),(.92,.30)]):
        verts.extend((x+r*rr*math.cos((j+.18*(k%2))*math.tau/8),y+r*.85*rr*math.sin((j+.18*(k%2))*math.tau/8),z+r*zz) for j in range(8))
    faces=[tuple(reversed(range(8))),tuple(range(32,40))]
    faces.extend((k*8+j,k*8+(j+1)%8,(k+1)*8+(j+1)%8,(k+1)*8+j) for k in range(4) for j in range(8))
    p.poly(verts,faces,c,1)
def palm(p,x,y,z,height=2.7):
    p.rod((x,y,z),(x+.18,y,z+height),.12,WARM,1,8)
    for j in range(7):
        a=j*math.tau/7; dx=math.cos(a); dy=math.sin(a)
        base=Vector((x+.18,y,z+height)); tip=base+Vector((dx*2.2,dy*2.2,-.65))
        mid=base+Vector((dx*1.0,dy*1.0,.35)); side=Vector((-dy*.38,dx*.38,0))
        p.poly([base,mid+side,tip,mid-side],[(0,1,2),(0,2,3)],LEAF if j%2 else LEAFHI,1)
islands=[(-24,-7,9,3.5),(-7,-7,8,3),(15,-4,10,3.2),(41,-12,11,3.8),(62,-12,7,3),(-25,19,9,2.3),(-4,20,8,2),(20,19,8,2),(43,15,6,2)]
for i,(x,y,rx,ry) in enumerate(islands):
    p=Part('planter_%02d'%i,'曲线景观岛_%02d_双层花池'%i,'garden',(x,y,15),'elliptic_planter')
    ring=ellipse(x,y,rx,ry,36)
    p.prism(ring,15.03,15.58,CREAM)
    inner=ellipse(x,y,rx-.36,ry-.36,36); p.prism(inner,15.58,15.60,SOIL)
    p.path([(*q,15.60) for q in ring+[ring[0]]],.095,LIGHT,1,8); p.finish()
    p=Part('vegetation_%02d'%i,'曲线景观岛_%02d_层次灌木棕榈'%i,'garden',(x,y,15.6),'garden_cluster')
    for j in range(20):
        a=j*2.399; rad=math.sqrt((j+.5)/20)*.80
        xx=x+rx*rad*math.cos(a); yy=y+ry*rad*math.sin(a)
        blob(p,xx,yy,16+random.uniform(.1,.8),random.uniform(.60,1.2),[GREEN,LEAF,LEAFHI][j%3])
    for j in range(3):
        xx=x+(j-1)*rx*.47
        palm(p,xx,y+(.5 if j%2 else -.3),15.60,2.5+.4*(j%2))
        if j==1:
            for dx,dy,zz in [(-.7,0,18),(.5,-.4,18.2),(0,.5,18.4)]: blob(p,xx+dx,y+dy,zz,1.2,GREEN)
    for j in range(8):
        a=j*math.tau/8; xx=x+rx*.82*math.cos(a); yy=y+ry*.72*math.sin(a)
        blob(p,xx,yy,16.2,.27,GOLD if j%2 else WARM)
    p.finish()

# Rooftop pavilion: framed glazed volume, pitched glass roof and folded plinth.
p=Part('glass_pavilion','右端玻璃景观亭_框架透明色块','facilities',(53,6,15),'glass_pavilion')
x0,x1,y0,y1=38,69,1,11
p.box((53.5,6,15.18),(31.5,10.5,.36),CREAM,1,.15)
for x in [x0+i*(x1-x0)/8 for i in range(9)]:
    for y in (y0,y1):
        p.rod((x,y,15.3),(x,y,19.25),.085,LIGHT,0)
    p.rod((x,y0,19.25),(x,6,20.55),.075,LIGHT,0)
    p.rod((x,6,20.55),(x,y1,19.25),.075,LIGHT,0)
for a,b in [((x0,y0),(x1,y0)),((x1,y0),(x1,y1)),((x1,y1),(x0,y1)),((x0,y1),(x0,y0))]:
    p.rod((*a,19.25),(*b,19.25),.10,LIGHT,0)
    av=Vector(a); bv=Vector(b); count=max(1,round((bv-av).length/3.8))
    for j in range(count):
        aa=av+(bv-av)*(j+.03)/count; bb=av+(bv-av)*(j+.97)/count
        p.poly([(*aa,15.35),(*bb,15.35),(*bb,19.13),(*aa,19.13)],[(0,1,2,3)],BLUEHI if j%3 else BLUE,2)
for j in range(8):
    xa=x0+j*(x1-x0)/8; xb=xa+(x1-x0)/8
    for yy in (y0,y1):
        p.poly([(xa,yy,19.27),(xb,yy,19.27),(xb,6,20.57),(xa,6,20.57)],[(0,1,2,3)],TILE,2)
        p.rod((xa,yy,19.31),(xb,6,20.62),.055,CREAM,0)
p.rod((x0,6,20.55),(x1,6,20.55),.10,LIGHT,0)
for x in (x0,x1):
    p.poly([(x,y0,19.25),(x,y1,19.25),(x,6,20.55)],[(0,1,2)] if x==x1 else [(2,1,0)],BLUEHI,2)
    p.rod((x,6,19.25),(x,6,20.55),.075,LIGHT,0)
p.finish()

# Upper left rear gallery reproduces raised crescent end seen behind the canopy.
back=boundary([((-64,16),(-70,21),(-64,25),(-52,24)),((-52,24),(-43,24),(-33,20),(-28,18)),((-28,18),(-39,13),(-54,12),(-64,16))])
p=Part('rear_gallery','后侧升高弧形连廊_圆钝端头','architecture',(-48,18,20),'curved_strip_storey')
p.prism(back,19.5,20,LIGHT); p.prism(back,24.65,25,CREAM)
sample_rail(p,back,25); p.finish()
facade('rear_glazing','后侧升高连廊曲线玻璃',back,20,25,1)

# Additional rooftop equipment belongs to discreet service zone, not hero centre.
for i,(x,y) in enumerate([(-18,19),(-11,19)]):
    p=Part('hvac_%02d'%i,'背侧风扇空调_%02d'%i,'facilities',(x,y,15),'hvac_unit')
    p.box((x,y,15.25),(4.6,2.8,.40),STEEL,0,.10)
    p.box((x,y,16.15),(4.3,2.5,1.5),TILE,1,.15)
    for dx in (-1.05,1.05):
        p.rod((x+dx,y,16.86),(x+dx,y,17.0),.88,DARK,1,16)
        ring=[(x+dx+.84*math.cos(j*math.tau/24),y+.84*math.sin(j*math.tau/24),17.05) for j in range(25)]
        p.path(ring,.06,LIGHT,0,6)
        for a in range(4):
            ang=a*math.tau/4
            p.rod((x+dx,y,17.03),(x+dx+.76*math.cos(ang),y+.76*math.sin(ang),17.03),.075,STEEL,0)
    for j in range(10): p.box((x-1.85+j*.4,y-1.28,16.2),(.06,.06,1.0),DARK,1)
    p.finish()
p=Part('stair_hut','天台楼梯出口_门雨棚检修柜','facilities',(-32,12,15),'service_hut')
p.box((-32,12,16.8),(5.0,4.3,3.5),CREAM,1,.15)
p.box((-32,9.80,16.35),(1.8,.13,2.6),DARK,1,.07)
p.box((-32,9.65,16.35),(1.6,.10,2.4),BLUE,1,.06)
p.box((-31.43,9.57,16.35),(.08,.10,.48),GOLD,0,.02)
p.box((-32,9.25,17.80),(3.2,1.5,.18),LIGHT,1,.08)
p.box((-32,12,18.62),(5.3,4.6,.20),TILE,1,.10)
p.box((-32,9.48,17.15),(.70,.04,.12),GOLD,3,.02); p.finish()
for i in range(11):
    x=-21+i*8.1; y=-9-.15*(x+20)
    if not inside(x,y,outline): continue
    p=Part('bollard_%02d'%i,'步道灯柱_%02d'%i,'facilities',(x,y,15),'lighting_bollard')
    p.box((x,y,15.08),(.44,.44,.16),CREAM,1,.05)
    p.box((x,y,15.58),(.25,.25,.96),STEEL,0,.04)
    p.box((x,y,16.06),(.30,.30,.15),GOLD,3,.03)
    p.box((x,y,16.17),(.38,.38,.08),LIGHT,1,.03); p.finish()
p=Part('drain_bank','露台排水沟与检修口','support',(0,0,15),'drain_bank')
for x,y in [(-16,-11),(1,-12),(26,-17),(49,-21),(69,-9)]:
    p.box((x,y,15.04),(3.0,.40,.05),DARK,1)
    for i in range(13): p.box((x-1.4+i*.23,y,15.08),(.07,.38,.04),STEEL,0)
    p.box((x-2.2,y+.9,15.05),(.9,.9,.06),TILE2,1,.07)
p.finish()
p=Part('entry_portal','中段商场主入口_门框及层叠雨棚','facilities',(-16,-8,0),'entrance_portal')
for x in (-21,-11): p.box((x,-10,4.1),(.65,.70,8.0),CREAM,1,.1)
for z,width in ((5,10.5),(5.4,11.5)):
    p.box((-16,-11,z),(width,4.6,.25),LIGHT,1,.12)
for x in (-19,-17,-15,-13):
    p.box((x,-9.80,2.45),(1.8,.10,4.3),BLUE,2,.04)
    p.box((x,-9.92,2.3),(.07,.09,.9),LIGHT,0,.02)
p.box((-16,-13.25,5.25),(5.4,.12,.12),GOLD,3,.03); p.finish()

# Sculptural descending return stair along the oval's right cheek: preserves
# the reference's curved transition instead of a disconnected tall drum.
p=Part('return_stair','左翼回旋层间楼梯_弧形踏步与扶手','architecture',(-50,-3,15),'curved_rooftop_stair')
inner_line=[]; outer_line=[]
for i in range(40):
    a=math.radians(63-76*i/40); b=math.radians(63-76*(i+1)/40)
    h=25-10*(i+1)/40
    def stair_xy(angle,r): return (-50+r*math.cos(angle),-3+(r*.835)*math.sin(angle))
    aa=stair_xy(a,24.6); bb=stair_xy(b,24.6); cc=stair_xy(b,27.9); dd=stair_xy(a,27.9)
    p.prism([aa,bb,cc,dd],h-.42,h+.02,CREAM)
    p.rod((*bb,h+.055),(*cc,h+.055),.045,TILE2,1,6)
    inner_line.append((*aa,h+1.15)); outer_line.append((*dd,h+1.15))
    if i%2==0:
        for q in (aa,dd): p.rod((*q,h),(*q,h+1.15),.07,STEEL,0)
p.path(inner_line,.07,LIGHT,0,8); p.path(outer_line,.07,LIGHT,0,8)
p.finish()
for i,(x,y) in enumerate([(-8,-2),(12,2),(37,-5),(60,-7)]):
    p=Part('garden_bench_%02d'%i,'花园固定长椅_%02d_独立包'%i,'facilities',(x,y,15),'fixed_garden_bench')
    for dx in (-1.8,1.8):
        p.box((x+dx,y,15.32),(.25,1.1,.60),STEEL,0,.05)
        p.box((x+dx,y+.45,15.85),(.25,.20,1.2),STEEL,0,.04)
    for j in range(4):
        p.box((x,y-.45+j*.30,15.64),(4.4,.23,.14),WARM,1,.05)
    for z in (15.97,16.28): p.box((x,y+.48,z),(4.4,.16,.22),WARM,1,.05)
    p.finish()

# Quantified authoring landmarks and complete mirrored catalog.
bpy.context.view_layer.update()
allverts=[o.matrix_world@v.co for o in game.all_objects for v in o.data.vertices]
mn=[min(v[j] for v in allverts) for j in range(3)]; mx=[max(v[j] for v in allverts) for j in range(3)]
# Fit plan once at authoring stage (not an output scale): all vertices, origins and
# manifests are rescaled horizontally together, retaining height and material UV.
sx=150/(mx[0]-mn[0]); sy=50/(mx[1]-mn[1]); offset=((mx[0]+mn[0])/2,(mx[1]+mn[1])/2)
for ob in list(game.all_objects)+list(src.all_objects):
    for v in ob.data.vertices: v.co.x*=sx; v.co.y*=sy
    ob.location.x=(ob.location.x-offset[0])*sx; ob.location.y=(ob.location.y-offset[1])*sy
for info in catalog:
    for key in ('bounds_min','bounds_max','world_position'):
        info[key][0]=(info[key][0]-offset[0])*sx; info[key][1]=(info[key][1]-offset[1])*sy
    info['dimensions'][0]*=sx; info['dimensions'][1]*=sy
    (OUT/'component_packages'/info['category']/info['slug']/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
meta=dict(asset_id=ASSET,building_id='塔4',version='v001',source_blend=BLEND.relative_to(R).as_posix(),floor_count=5,floor_height_m=5,roof_height_m=25,terrace_height_m=15,footprint_m=[150,50],component_definition_count=len(definitions),package_count=len(catalog),packages=catalog,shared_palette=PALETTE.relative_to(R).as_posix(),material_source=DONOR.relative_to(R).as_posix(),new_materials_created=0,material_roles=NAMES,source_status='Blender源已完成',runtime_status='not_exported_not_integrated',block_id='open_world',asset_ledger='scenes::资产主表::'+ASSET,scene_design_docs=['docs/v0.1/design/tower04_mall_source.md'],reference=REFERENCE.name,authoring_horizontal_fit=[sx,sy],locked_asset_hashes=locked)
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')

sc.render.engine='CYCLES'; sc.cycles.samples=40; sc.cycles.use_denoising=True
sc.render.image_settings.file_format='PNG'
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=.55
world=bpy.data.worlds.new('展示环境_不导出'); world.use_nodes=True; sc.world=world
world.node_tree.nodes['Background'].inputs[0].default_value=(.34,.43,.52,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.8
def light(name,kind,pos,power,col,size=50):
    data=bpy.data.lights.new(name,kind); data.energy=power; data.color=col
    ob=bpy.data.objects.new(name,data); display.objects.link(ob); ob.location=pos
    ob.rotation_euler=(Vector((0,0,15))-ob.location).to_track_quat('-Z','Y').to_euler()
    if kind=='AREA': data.size=size
    if kind=='SUN': data.angle=.22
light('主光_柔暖太阳','SUN',(-70,-50,100),3.2,(1,.88,.75))
light('补光_大片冷光','AREA',(-30,-80,70),9000,(.72,.87,1),70)
light('轮廓光','AREA',(30,60,85),12000,(1,.86,.71),65)
def camera(name,pos,target,scale,res):
    data=bpy.data.cameras.new(name); data.type='ORTHO'; data.ortho_scale=scale; data.clip_end=1000
    ob=bpy.data.objects.new(name,data); display.objects.link(ob); ob.location=pos
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    ob['resolution_x']=res[0]; ob['resolution_y']=res[1]
    return ob
cameras=[
    (camera('CAM_参考全景',(142,-180,127),(0,0,12),172,(1920,1152)),'01_塔4_参考全景.png'),
    (camera('CAM_俯视轮廓',(0,-.01,220),(0,0,12),161,(1920,850)),'02_塔4_俯视轮廓.png'),
    (camera('CAM_天台花园',(55,-72,70),(10,0,16),115,(1760,1150)),'03_塔4_天台花园.png'),
    (camera('CAM_左翼转折',(-92,-84,65),(-42,-2,14),87,(1600,1200)),'04_塔4_椭圆左翼.png'),
    (camera('CAM_玻璃亭与格构',(110,-48,59),(48,6,17),67,(1600,1150)),'05_塔4_玻璃亭与遮阳棚.png'),
    (camera('CAM_背侧完整性',(-108,143,101),(0,1,12),177,(1760,1100)),'06_塔4_背侧完整性.png')]
sc.camera=cameras[0][0]; sc.render.resolution_x=1920; sc.render.resolution_y=1152
sc.render.resolution_percentage=100
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    if any(d.type!='CPU' for d in prefs.devices): sc.cycles.device='GPU'
except Exception as exc: print('GPU_FALLBACK',exc,flush=True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.clip_end=1000
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print('TOWER04_SOURCE_SAVED',len(catalog),flush=True)
if '--no-render' not in sys.argv:
    for cam,filename in cameras:
        sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']
        sc.render.filepath=str(OUT/'previews'/filename)
        bpy.ops.render.render(write_still=True); print('TOWER04_RENDER',filename,flush=True)
sc.camera=cameras[0][0]; sc.render.resolution_x=1920; sc.render.resolution_y=1152
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
assert all(hashlib.sha256((R/path).read_bytes()).hexdigest()==sha for path,sha in locked.items())
print('TOWER04_COMPLETE',flush=True)
