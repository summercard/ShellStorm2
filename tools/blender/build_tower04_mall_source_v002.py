"""Tower04: traced rooftop plan and refined stylized fixtures; source-only r2."""
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

R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
import tower04_plan_v002 as P
OUT=R/'assets/art/environments/open_world/source/tower_04/v002'
BLEND=OUT/'塔4_曲线天台商场_150x50m_v002.blend'
ASSET='ENV-OPENWORLD-TOWER04'
DONOR=R/'assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
PREVIOUS=R/'assets/art/environments/open_world/source/tower_04/v001/塔4_曲线天台商场_150x50m_v001.blend'
PALETTE=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
for d in ('references','qa','previews','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
if BLEND.exists():
    assert '--draft-sha' in sys.argv, 'Use next version; draft overwrite requires verified hash'
    assert hashlib.sha256(BLEND.read_bytes()).hexdigest()==sys.argv[sys.argv.index('--draft-sha')+1]
locked={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (DONOR,PREVIOUS,PALETTE,Path(str(PALETTE)+'.import'))}
for name,file in [('用户参考_功能分区.png','8a42fa69-9290-4dc3-83f9-0e2bcba48668'),('用户参考_详细平面.png','114d3d7e-5272-409c-9edb-a3ca0426b56b')]:
    shutil.copy2(Path('C:/Users/ZHUANG~1/AppData/Local/Temp')/('codex-clipboard-'+file+'.png'),OUT/'references'/name)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene; sc.unit_settings.system='METRIC'; sc.unit_settings.scale_length=1
for k,v in dict(asset_id=ASSET,version='v002',block_id='open_world',floor_count=5,floor_height_m=5,roof_z_m=25,terrace_z_m=25,asset_ledger='scenes::资产主表::'+ASSET,scene_design_docs='docs/v0.1/design/tower04_mall_source.md').items(): sc[k]=v
with bpy.data.libraries.load(str(DONOR),link=False) as (a,b): b.materials=list(NAMES)
MATS=[bpy.data.materials[n] for n in NAMES]
for mat in MATS:
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE' and node.image:
            node.image.filepath=str(PALETTE); node.image.reload()
palette=next(n.image for n in MATS[1].node_tree.nodes if n.type=='TEX_IMAGE'); pixels=list(palette.pixels)
def color(rgb):
    choices=[]
    for row in range(10):
        for col in range(10):
            x=int((col+.5)*512/10); y=int((9-row+.5)*512/10)
            choices.append((sum((a-b)**2 for a,b in zip(pixels[(y*512+x)*4:(y*512+x)*4+3],rgb)),(col,row)))
    return min(choices)[1]
CREAM=LIGHT=(9,9); TILE=(9,8); TILE2=(9,7); DARK=(9,0); STEEL=(9,4)
BLUE=color((.17,.43,.49)); BLUEHI=color((.35,.64,.69)); WARM=(7,2); GOLD=color((.80,.52,.16))
GREEN=(6,4); LEAF=(7,4); LEAFHI=(8,4); SOIL=color((.22,.24,.16)); TEAL=BLUE; RUST=WARM
RED=(7,1); WOOD=(7,2)
BLUE=(6,5); BLUEHI=(7,5)
random.seed(40042)
helper=R/'tools/blender/build_skyline_08_source_v001.py'
nodes=[n for n in ast.parse(helper.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('coll','uv_mesh','Part')]
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(helper),'exec'),globals()); BasePart=Part
root=coll('塔4_图纸还原曲线商场_中文资产管理',sc.collection)
src=coll('01_制作组件_按独立资产包',root); src.hide_viewport=True; src.hide_render=True
game=coll('02_游戏输出_独立资产包_v002',root); display=coll('90_展示与验收_固定灯光相机',root)
categories=[('architecture','01_建筑结构'),('floor','02_地面系统'),('facilities','03_天台固定设施'),('garden','04_曲线景观'),('support','05_环境支持')]
CATS={k:coll(n,game) for k,n in categories}; SCATS={k:coll(n+'_制作源',src) for k,n in categories}; catalog=[]
previous_script=R/'tools/blender/build_tower04_mall_source.py'
reuse=[n for n in ast.parse(previous_script.read_text(encoding='utf8')).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('Part','ellipse','facade')]
reuse_code=ast.unparse(ast.Module(body=reuse,type_ignores=[])).replace("'v001'","'v002'").replace('1F–5F及错层天台','1F–5F及连续天台')
exec(compile(reuse_code,str(previous_script),'exec'),globals())
# No large asset can be authored until the two-stage plan review is frozen.
judgment=P.judgment()
assert all(all(v=='pass' for k,v in row['independent_recheck'].items() if k!='alternative') for row in judgment)
(OUT/'layout_judgment.json').write_text(json.dumps(dict(version='v002',unit='metres',up='Z',camera='roof-plane orthographic tracing; vertical structure excluded from roof comparison',pixel_unit_m=.12,pixel_origin=P.PIXEL_ORIGIN,reference_partial_dimensions=True,cropped_east_extension=True,unchanged_assets=locked,rows=judgment),ensure_ascii=False,indent=2),encoding='utf8')

def prism(slug,name,cat,poly,z,h,c=TILE,definition='roof_surface'):
    p=Part(slug,name,cat,(*P.centre(poly),z),definition); p.prism(poly,z,z+h,c); return p

def ribbon(points,left,right):
    out=[]
    for i,q in enumerate(points):
        delta=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        if delta.length<1e-8: delta=Vector((1,0))
        delta.normalize(); normal=Vector((-delta.y,delta.x))
        out.append((Vector(q)+normal*left,Vector(q)+normal*right))
    return [tuple(a) for a,b in out]+[tuple(b) for a,b in reversed(out)]

def offset_polygon(poly,amount):
    area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
    out=[]
    for i,q in enumerate(poly):
        before=Vector(q)-Vector(poly[i-1]); after=Vector(poly[(i+1)%len(poly)])-Vector(q)
        if before.length<.001 or after.length<.001: out.append(q); continue
        before.normalize(); after.normalize(); tangent=(before+after).normalized()
        normal=Vector((-tangent.y,tangent.x))*(1 if area>0 else -1)
        out.append(tuple(Vector(q)+normal*amount))
    return out

def roof_ribbon(slug,name,left,right,z,c):
    p=Part(slug,name,'floor',(0,0,z),'roof_clipped_walkway')
    deck_tri=tessellate_polygon([[Vector((*q,0)) for q in P.DECK]])
    quads=ribbon(P.PROMENADE,left,right); count=len(P.PROMENADE)
    edge_a=quads[:count]; edge_b=list(reversed(quads[count:]))
    def clip(poly,quad):
        sign=1 if sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(quad,quad[1:]+quad[:1]))>0 else -1
        for a,b in zip(quad,quad[1:]+quad[:1]):
            if not poly: break
            new=[]
            def side(q): return sign*((b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0]))
            for aa,bb in zip(poly,poly[1:]+poly[:1]):
                sa,sb=side(aa),side(bb)
                if sa>=-1e-8: new.append(aa)
                if (sa>=0)!=(sb>=0):
                    t=sa/(sa-sb); new.append((aa[0]+(bb[0]-aa[0])*t,aa[1]+(bb[1]-aa[1])*t))
            poly=new
        return poly
    for i in range(count-1):
        quad=[edge_a[i],edge_a[i+1],edge_b[i+1],edge_b[i]]; bb=P.bounds(quad)
        for tri in deck_tri:
            pts=[P.DECK[q] if isinstance(q,int) else (q.x,q.y) for q in tri]; tb=P.bounds(pts)
            if tb[2]<bb[0] or tb[0]>bb[2] or tb[3]<bb[1] or tb[1]>bb[3]: continue
            clipped=clip(pts,quad)
            if len(clipped)<3: continue
            area=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(clipped,clipped[1:]+clipped[:1])))
            if area>.00001: p.prism(clipped,z,z+.012,c)
    return p

def facade(slug,name,points,z0,z1,levels,closed=True):
    p=Part(slug,name,'architecture',(0,0,z0),'facade_curve')
    pts=points[::3]+([points[0]] if closed else [])
    for i,(a,b) in enumerate(zip(pts,pts[1:])):
        av,bv=Vector(a),Vector(b); edge=bv-av
        p.rod((*a,z0+.28),(*a,z1-.2),.065,STEEL,0,8)
        for k in range(levels):
            aa=av+edge*.035; bb=bv-edge*.035; low=z0+5*k+.4; high=z0+5*(k+1)-.24
            p.poly([(*aa,low),(*bb,low),(*bb,high),(*aa,high)],[(0,1,2,3)],BLUEHI if (i+k)%7 else BLUE,2)
            if i%17==5:
                p.poly([(*aa,low+.12),(*(aa+edge*.12),low+.12),(*bb,high-.14),(*(bb-edge*.12),high-.14)],[(0,1,2,3)],TILE2,2)
            p.rod((*a,z0+k*5+.26),(*b,z0+k*5+.26),.045,STEEL,0,8)
    p.finish()

def rail(p,points,z,closed=True,glass=True):
    pts=points+([points[0]] if closed else [])
    for h,r,c in [(1.2,.045,LIGHT),(.16,.035,STEEL)]: p.path([(*q,z+h) for q in pts],r,c,0,8)
    dist=0
    for a,b in zip(pts,pts[1:]):
        av=Vector(a); bv=Vector(b); edge=bv-av
        if edge.length<.001: continue
        if glass:
            aa=av+edge*.025; bb=bv-edge*.025
            p.poly([(*aa,z+.22),(*bb,z+.22),(*bb,z+1.1),(*aa,z+1.1)],[(0,1,2,3)],BLUEHI,2)
        dist+=edge.length
        if dist>=1.5:
            dist=0; p.box((*a,z+.05),(.24,.24,.10),STEEL,0,.03)
            p.rod((*a,z+.1),(*a,z+1.2),.035,STEEL,0,8)
            for dx in (-.075,.075):
                for dy in (-.075,.075): p.rod((a[0]+dx,a[1]+dy,z+.1),(a[0]+dx,a[1]+dy,z+.13),.026,LIGHT,0,6)
            for h in (.26,1.05): p.box((*a,z+h),(.13,.12,.11),LIGHT,0,.02)

def ellipsoid(p,centre,radii,c,m=1,n=12,rings=8):
    x,y,z=centre; rx,ry,rz=radii; v=[]
    for k in range(rings+1):
        phi=math.pi*(k+.06)/(rings+.12)
        v.extend((x+rx*math.sin(phi)*math.cos(j*math.tau/n),y+ry*math.sin(phi)*math.sin(j*math.tau/n),z+rz*math.cos(phi)) for j in range(n))
    f=[tuple(reversed(range(n))),tuple(range(rings*n,(rings+1)*n))]
    f.extend((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j) for k in range(rings) for j in range(n))
    p.poly(v,f,c,m)

def leaf(p,base,angle,length,width,c,up=.4):
    base=Vector(base); axis=Vector((math.cos(angle),math.sin(angle),0)); side=Vector((-axis.y,axis.x,0))
    mid=base+axis*length*.48+Vector((0,0,up)); tip=base+axis*length+Vector((0,0,-.22*length))
    p.poly([base,mid+side*width,tip,mid-side*width,mid+Vector((0,0,.08))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],c)

def plant(p,x,y,z,kind=0,size=1):
    if kind==0:
        h=2.4*size; p.rod((x,y,z),(x+.1,y,z+h),.10*size,WOOD,1,8)
        for j in range(9): leaf(p,(x+.1,y,z+h),j*math.tau/9,1.7*size,.24*size,LEAF if j%2 else LEAFHI,.45*size)
    elif kind==1:
        p.rod((x,y,z),(x,y,z+2.1*size),.13*size,WOOD,1,8)
        for dx,dy,dz,r in [(-.45,0,2.5,.75),(.45,.15,2.7,.75),(0,-.3,3.1,.85),(0,.35,2.2,.66)]:
            ellipsoid(p,(x+dx*size,y+dy*size,z+dz*size),(r*size,r*size,.75*r*size),[GREEN,LEAF,LEAFHI][int(abs(dx)*10)%3],n=10,rings=5)
    elif kind==2:
        for j in range(9): leaf(p,(x,y,z+.2),j*math.tau/9,.65*size,.12*size,LEAFHI,.45*size)
    else:
        for dx,dy,dz in [(-.3,0,.4),(.25,.15,.5),(0,-.18,.65)]:
            ellipsoid(p,(x+dx*size,y+dy*size,z+dz*size),(.46*size,.40*size,.43*size),GREEN if kind==3 else LEAF,n=10,rings=5)

def plants(slug,poly,z,density=1):
    p=Part(slug,slug.replace('vegetation','景观植被'),'garden',(*P.centre(poly),z),'layered_planting')
    b=P.bounds(poly); c=P.centre(poly); seeds=[]
    for i in range(int((b[2]-b[0])*(b[3]-b[1])*density*.35)):
        q=(random.uniform(b[0]+.4,b[2]-.4),random.uniform(b[1]+.4,b[3]-.4))
        if not P.inside(q,poly): continue
        if min((math.dist(q,v) for v in seeds),default=9)<.70: continue
        seeds.append(q); plant(p,*q,z,3+i%2,random.uniform(.85,1.3))
    for i,q in enumerate(seeds[::max(1,len(seeds)//4)]): plant(p,*q,z,i%2,random.uniform(.8,1.05))
    for i,q in enumerate(seeds[::4]):
        for j in range(3): ellipsoid(p,(q[0]+j*.13,q[1],z+.50),(.12,.12,.12),GOLD if i%2 else RED,n=8,rings=4)
    p.finish()

# Calibration test: floor outline only; plan axes are explicitly orthographic.
test=prism('terrace_shell','图纸还原_连续天台月牙凹口','architecture',P.DECK,23.8,1.2,LIGHT,'traced_roof_deck')
test.path([(*q,24.72) for q in P.DECK+[P.DECK[0]]],.05,CREAM,1,8); test.finish()
calibration=bpy.data.cameras.new('CAM_图纸校准'); calibration.type='ORTHO'; calibration.ortho_scale=173.76
calib=bpy.data.objects.new(calibration.name,calibration); display.objects.link(calib); calib.location=(2.4,-23.16,250); calib.rotation_euler=(0,0,0)
calib['reference_resolution']=[1448,1086]; calib['pixel_origin']=P.PIXEL_ORIGIN; calib['metres_per_pixel']=.12
sc.camera=calib; sc.render.resolution_x=1448; sc.render.resolution_y=1086
bpy.context.view_layer.update()
from bpy_extras.object_utils import world_to_camera_view
def screen_point(q):
    v=world_to_camera_view(sc,calib,Vector((*q,25))); return (v.x*1448,(1-v.y)*1086)
errors=[]
for row in judgment:
    if row['slug']=='terrace_shell': points=P.DECK
    elif row['slug']=='leaf_canopy': points=P.CANOPY
    elif row['slug']=='glass_pavilion': points=P.PAVILION
    elif row['slug']=='lawn_court': points=P.LAWN
    elif row['slug']=='oval_roof': points=ellipse(*P.CIRCLE_CENTER,*P.CIRCLE_RADII,72)
    else: points=P.ISLANDS[int(row['slug'][-2:])]
    projected=P.bounds([screen_point(q) for q in points]); target=row['reference_bbox_px']
    e=max(abs(a-b) for a,b in zip(projected,target))
    row['calibrated_roof_plane_error_px']=e
    row['camera_check']='pass' if e<1 else 'fail'
    if e>=1: errors.append(row['slug'])
assert not errors, ('camera calibration failed',errors)
(OUT/'qa/layout_calibration.json').write_text(json.dumps(dict(passed=True,rows=judgment,camera='CAM_图纸校准',independent_top_view='metric reference-plane curves'),ensure_ascii=False,indent=2),encoding='utf8')
if '--blockout-only' in sys.argv:
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'qa/布局校准草模.blend')); raise SystemExit(0)

# Main retail body: smaller elliptical roof and five readable storeys.
cx,cy=P.CIRCLE_CENTER; rx,ry=P.CIRCLE_RADII
oval=ellipse(cx,cy,rx,ry,72)
for i in range(5):
    p=prism('oval_level_%02d'%(i+1),'左翼回旋商场_%02d层'%(i+1),'architecture',oval,i*5,.38,LIGHT,'ellipse_storey')
    p.prism(ellipse(cx,cy,rx-.22,ry-.22,72),i*5+.38,i*5+4.65,DARK)
    p.path([(*q,i*5+4.82) for q in oval+[oval[0]]],.14,LIGHT,1,8); p.finish()
facade('oval_glazing','左翼五层弧形幕墙',oval,0,25,5)
p=prism('oval_roof','左楼屋顶_回旋缺口及同标高接口','floor',oval,24.78,.22,TILE,'elliptic_roof_curb')
for rr in (1,.90):
    line=ellipse(cx,cy,rx*rr,ry*rr,72)
    p.path([(*q,25.02 if rr==1 else 25.06) for q in line+[line[0]]],.05,CREAM,1,8)
spiral=[(cx+rx*.81*math.cos(math.radians(2+i*1.1)),cy+ry*.81*math.sin(math.radians(2+i*1.1))) for i in range(67)]
p.path([(*q,25.35) for q in spiral],.22,LIGHT,1,10)
for x in range(int(cx-rx)+2,int(cx+rx),3):
    extent=ry*.9*math.sqrt(max(0,1-((x-cx)/(rx*.92))**2)); p.rod((x,cy-extent,25.014),(x,cy+extent,25.014),.013,TILE2,1,6)
for y in range(int(cy-ry)+2,int(cy+ry),3):
    extent=rx*.91*math.sqrt(max(0,1-((y-cy)/(ry*.92))**2)); p.rod((cx-extent,y,25.015),(cx+extent,y,25.015),.013,TILE2,1,6)
p.finish()
p=Part('oval_roof_rail','左楼玻璃栏杆_北侧接连廊留口','support',(cx,cy,25),'glass_guardrail')
segments=[(175,360),(0,31),(103,145)]
for start,end in segments:
    line=[(cx+(rx-.18)*math.cos(math.radians(a)),cy+(ry-.18)*math.sin(math.radians(a))) for a in range(start,end+1,3)]
    rail(p,line,25,False)
p.finish()
# Five-storey curved east wing only follows its reference roof, not a box filling void.
wing=offset_polygon(P.DECK,.20)
for i in range(5):
    p=prism('wing_level_%02d'%(i+1),'长翼曲线商场_%02d层'%(i+1),'architecture',wing,i*5,.32,LIGHT,'curved_strip_storey')
    c=P.centre(wing); inner=[(c[0]+(x-c[0])*.993,c[1]+(y-c[1])*.985) for x,y in wing]
    p.prism(inner,i*5+.35,i*5+4.65,DARK); p.finish()
facade('wing_glazing','长翼曲线幕墙_退缩框架',wing,0,25,5)
# Hollow north arcade walls and piers are supports, not a filled crescent island.
for i,uv in enumerate([(158,223),(365,268),(534,330),(595,458),(803,455),(1129,496)]):
    x,y=P.xy(uv); p=Part('pier_%02d'%i,'连廊结构承重圆柱_%02d'%i,'architecture',(x,y,0),'terrace_pier')
    p.rod((x,y,0),(x,y,23.8),.70,LIGHT,1,18)
    for z in (0,5,10,15,20,23.5): p.rod((x,y,z),(x,y,z+.1),.73,TILE,1,18)
    p.finish()
p=Part('terrace_rail','曲线平台玻璃护栏_节点基座夹件','support',(0,0,25),'glass_guardrail')
# Open only the two short interfaces adjacent to the circular roof.
rail_line=offset_polygon(P.DECK,.16)
rail(p,rail_line[:180],25,False); rail(p,rail_line[191:],25,False); p.finish()
p=prism('roof_paving','连续天台灰米色铺装_曲线轮廓','floor',P.DECK,25,.015,TILE,'roof_paving')
for x in range(-70,76,4):
    for y in range(-22,25,4):
        if P.inside((x,y),P.DECK) and P.inside((x+3.8,y),P.DECK) and P.inside((x+3.8,y+3.8),P.DECK) and P.inside((x,y+3.8),P.DECK):
            p.prism([(x,y),(x+3.8,y),(x+3.8,y+3.8),(x,y+3.8)],25.016,25.023,CREAM if (x+y)%3==0 else TILE)
p.finish()
p=roof_ribbon('slow_lane','两米慢行带_连续转折导向',1,-1,25.03,RED)
for i,q in enumerate(P.PROMENADE):
    if i%7==0:
        a=Vector(q); tangent=Vector(P.PROMENADE[min(i+1,len(P.PROMENADE)-1)])-Vector(P.PROMENADE[max(0,i-1)])
        tangent.normalize(); normal=Vector((-tangent.y,tangent.x))
        aa,bb=tuple(a-normal*.94),tuple(a+normal*.94)
        if P.inside(aa,P.DECK) and P.inside(bb,P.DECK): p.rod((*aa,25.055),(*bb,25.055),.018,CREAM,1,6)
p.finish()
p=roof_ribbon('main_walk','四米主步道_慢行带旁宽通路',1,5,25.024,CREAM); p.finish()

# Canopy: warped traced leaf, framed triangular cells and alternating glazing sails.
p=Part('leaf_canopy','长曲线叶形顶棚_三角采光板及格构','support',(*P.centre(P.CANOPY),29.8),'traced_canopy')
N=len(P.TOP); height=29.8
def grid(i,j):
    a=Vector(P.BOTTOM[i]); b=Vector(P.TOP[i]); q=a+(b-a)*j/4
    return (*q,height+.27*math.sin(math.pi*j/4))
outer=[(*q,height) for q in P.TOP+list(reversed(P.BOTTOM))]
p.path(outer+[outer[0]],.16,LIGHT,0,10)
for j in range(5): p.path([grid(i,j) for i in range(N)],.075,LIGHT,0,8)
for i in range(N-1):
    for j in range(4):
        a,b,c,d=grid(i,j),grid(i+1,j),grid(i+1,j+1),grid(i,j+1)
        p.rod(a,c,.055,CREAM,0,6); p.rod(a,d,.055,LIGHT,0,6)
        if (i+j)%3!=0:
            def inset(tri):
                center=sum((Vector(q) for q in tri),Vector())/3
                return [tuple(center+(Vector(q)-center)*.86) for q in tri]
            p.poly(inset([a,b,c]),[(0,1,2)],BLUEHI if (i+j)%4==0 else TILE,2)
            p.poly(inset([a,c,d]),[(0,1,2)],LIGHT if (i+j)%5==0 else TILE,1)
        if j==2 and i%3==0:
            p.rod((a[0],a[1],a[2]-.08),(a[0],a[1],a[2]+.08),.13,STEEL,0,12)
            for k in range(4):
                p.rod((a[0]+.075*math.cos(k*math.pi/2),a[1]+.075*math.sin(k*math.pi/2),a[2]+.08),(a[0]+.075*math.cos(k*math.pi/2),a[1]+.075*math.sin(k*math.pi/2),a[2]+.12),.022,LIGHT,0,6)
p.finish()
for i,index in enumerate((5,14,23,32,40)):
    x,y=P.centre([P.BOTTOM[index],P.TOP[index]])
    p=Part('canopy_column_%02d'%i,'Y形钢柱_%02d_底板节点连接'%i,'support',(x,y,25),'forked_canopy_column')
    p.box((x,y,25.07),(.9,.9,.14),STEEL,0,.06)
    for dx in (-.32,.32):
        for dy in (-.32,.32):
            p.rod((x+dx,y+dy,25.14),(x+dx,y+dy,25.24),.055,LIGHT,0,6)
    p.rod((x,y,25.14),(x,y,28.0),.30,LIGHT,0,16)
    p.rod((x,y,25.2),(x,y,25.6),.33,CREAM,0,16)
    for q in (P.BOTTOM[index],P.TOP[index]):
        end=Vector((*q,29.7)); start=Vector((x,y,27.2))
        p.rod(start,end,.17,LIGHT,0,10)
        p.rod(start+Vector((0,0,.48)),end-Vector((0,0,.16)),.065,STEEL,0,8)
        p.box((end.x,end.y,29.65),(.55,.44,.14),STEEL,0,.045)
    p.box((x,y,27.63),(.70,.48,.35),CREAM,0,.06); p.finish()

# Independently authored teardrop/kidney/round planters, not repeated ellipses.
for i,poly in enumerate(P.ISLANDS):
    c=P.centre(poly); inner=[(c[0]+(x-c[0])*.91,c[1]+(y-c[1])*.91) for x,y in poly]
    p=prism('planter_%02d'%i,'图纸景观岛_%02d_异形坐凳花池'%i,'garden',poly,25.025,.575,LIGHT,'traced_planter')
    p.prism(inner,25.601,25.62,SOIL)
    p.path([(*q,25.57) for q in poly+[poly[0]]],.07,CREAM,1,8)
    # Wooden sit-wall slats on south rim, anchored to the planter only.
    lower=[q for q in poly if q[1]<c[1]-.20]
    for j,q in enumerate(lower[::3]):
        p.box((*q,25.62),(.28,.7,.10),WOOD,1,.035)
    p.finish(); plants('vegetation_%02d'%i,inner,25.62,2)

# Visible linear planting seams run just south of the canopy, as in the plan.
for i,(start,end) in enumerate([(2,9),(12,20),(23,30),(33,39)]):
    line=[(x,y-.55) for x,y in P.BOTTOM[start:end]]
    poly=ribbon(line,.32,-.32)
    p=prism('canopy_planter_%02d'%i,'棚边连续绿带_%02d_分段种植槽'%i,'garden',poly,25.025,.55,LIGHT,'linear_planter')
    inner=ribbon(line,.24,-.24); p.prism(inner,25.576,25.60,SOIL); p.finish()
    p=Part('canopy_green_%02d'%i,'棚边绿带_%02d_灌木与叶簇'%i,'garden',(*P.centre(poly),25.60),'linear_planting')
    for j,q in enumerate(line):
        plant(p,*q,25.6,3,.65)
        if j%3==0: plant(p,*q,25.6,2,.8)
    p.finish()
for i,uv in enumerate([(133,174),(197,165),(139,211),(284,278)]):
    x,y=P.xy(uv); poly=ellipse(x,y,1.55,.85,28)
    p=prism('plaza_planter_%02d'%i,'屋顶广场边缘花池_%02d'%i,'garden',poly,25.025,.575,LIGHT,'plaza_planter')
    p.prism(ellipse(x,y,1.37,.69,28),25.60,25.62,SOIL); p.finish(); plants('plaza_green_%02d'%i,ellipse(x,y,1.32,.66,28),25.62,2)
p=prism('lawn_court','右端开放草坪庭院_弯曲种植边界','garden',P.LAWN,25.027,.10,GREEN,'traced_lawn_court')
p.path([(*q,25.13) for q in P.LAWN+[P.LAWN[0]]],.075,LIGHT,1,8); p.finish()
# Trees stay at the lawn perimeter; the centre is an unobstructed activity area.
for i,uv in enumerate([(992,403),(1007,454),(1058,475),(1112,475),(1154,403),(1058,385)]):
    q=P.xy(uv); ring=ellipse(*q,1.8,1.3,24)
    p=prism('court_planter_%02d'%i,'庭院边缘小花池_%02d'%i,'garden',ring,25.13,.35,LIGHT,'garden_border')
    p.prism(ellipse(*q,1.63,1.16,24),25.48,25.50,SOIL); p.finish()
    plants('court_vegetation_%02d'%i,ellipse(*q,1.5,1.05,24),25.50,2)

# Angled glass box: local geometry transformed once around its frozen centre.
p=Part('glass_pavilion','斜置玻璃活动盒子_天窗门扇和内构架','facilities',(*P.PAVILION_CENTER,25),'glass_pavilion')
angle=P.PAVILION_ANGLE; ca=math.cos(angle); sa=math.sin(angle); ox,oy=P.PAVILION_CENTER
start=len(p.v)
L=math.dist(P.PAVILION[0],P.PAVILION[1]); W=math.dist(P.PAVILION[1],P.PAVILION[2])
p.box((0,0,25.15),(L+.2,W+.2,.30),LIGHT,1,.08)
for x in [-L/2+i*L/8 for i in range(9)]:
    for y in (-W/2,W/2):
        p.box((x,y,27.05),(.12,.13,3.7),LIGHT,0,.025)
        p.box((x,y,25.32),(.28,.26,.17),STEEL,0,.02)
    p.rod((x,-W/2,28.85),(x,0,29.20),.065,LIGHT,0)
    p.rod((x,0,29.20),(x,W/2,28.85),.065,LIGHT,0)
for side in (-1,1):
    yy=side*W/2
    for h in (25.3,26.2,28.85): p.box((0,yy,h),(L,.14,.13),LIGHT,0,.025)
    for i in range(8):
        xx=-L/2+i*L/8; ww=L/8
        p.poly([(xx+.10,yy,25.35),(xx+ww-.10,yy,25.35),(xx+ww-.10,yy,28.76),(xx+.10,yy,28.76)],[(0,1,2,3)],BLUEHI if i%3 else BLUE,2)
        # Broad reflection stripe preserves stylized glass without new shaders.
        p.poly([(xx+.22,yy-.005*side,25.55),(xx+.52,yy-.005*side,25.55),(xx+ww-.18,yy-.005*side,28.60),(xx+ww-.48,yy-.005*side,28.60)],[(0,1,2,3)],TILE,2)
        p.poly([(xx+.1,yy,28.9),(xx+ww-.1,yy,28.9),(xx+ww-.1,0,29.25),(xx+.1,0,29.25)],[(0,1,2,3)],TILE,2)
        p.rod((xx,yy,28.96),(xx+ww,0,29.25),.045,LIGHT,0,6)
for x in (-L/2,L/2):
    p.poly([(x,-W/2,25.3),(x,W/2,25.3),(x,W/2,28.85),(x,0,29.2),(x,-W/2,28.85)],[(0,1,2,3,4)],BLUEHI,2)
    for y in (-W/4,0,W/4): p.box((x,y,27.0),(.12,.12,3.45),LIGHT,0,.025)
    p.rod((x,-W/2,28.85),(x,W/2,28.85),.065,LIGHT,0)
# Two metre sliding entrance, handles, runner and repeated broad panel divisions.
for x in (-1,1):
    p.box((x*.5,-W/2-.11,26.5),(.96,.07,2.35),BLUE,2,.03)
    for dx in (-.46,.46): p.box((x*.5+dx,-W/2-.17,26.5),(.055,.07,2.4),LIGHT,0,.015)
    p.rod((x*.11,-W/2-.22,26.1),(x*.11,-W/2-.22,26.8),.04,CREAM,0)
p.box((0,-W/2-.12,27.8),(2.2,.25,.18),STEEL,0,.04)
p.box((0,-W/2-.10,25.34),(2.3,.32,.06),STEEL,0,.025)
for i,v in enumerate(p.v):
    x,y,z=v; p.v[i]=(ox+ca*x-sa*y,oy+sa*x+ca*y,z)
p.finish()

# Fixed display sculpture in the designated court, not gameplay pickup geometry.
x,y=P.xy((1138,440)); p=Part('court_sculpture','庭院白兔雕塑_固定展示附件','facilities',(x,y,25.13),'fixed_display_sculpture')
p.rod((x,y,25.13),(x,y,25.25),1.35,TILE,1,32)
for center,r in [((x,y,26.22),(.62,.52,.84)),((x,y-.1,27.20),(.65,.55,.64)),((x-.30,y-.02,28.14),(.20,.24,.85)),((x+.27,y-.02,28.14),(.20,.24,.78)),((x-.45,y-.32,25.56),(.43,.6,.30)),((x+.45,y-.32,25.56),(.43,.6,.30)),((x,y+.45,26.1),(.27,.25,.28))]: ellipsoid(p,center,r,LIGHT,n=16,rings=8)
for dx in (-.24,.24): ellipsoid(p,(x+dx,y-.61,27.30),(.06,.035,.08),DARK,n=8,rings=4)
ellipsoid(p,(x,y-.65,27.09),(.08,.035,.06),RED,n=8,rings=4)
ellipsoid(p,(x+1.3,y+.18,26.0),(.6,.6,.7),RED,n=16,rings=8); p.finish()

# Refined benches, combined litter bins and small pedestal lights on safe edges.
for i,uv in enumerate([(313,254),(433,290),(690,449),(845,449),(977,441)]):
    x,y=P.xy(uv); p=Part('garden_bench_%02d'%i,'独立座椅_%02d_弧背木条金属脚'%i,'facilities',(x,y,25),'fixed_garden_bench')
    for dx in (-1.3,1.3):
        p.box((x+dx,y,25.08),(.48,.80,.16),STEEL,0,.05)
        p.box((x+dx,y+.2,25.45),(.16,.5,.65),STEEL,0,.035)
        p.rod((x+dx,y+.28,25.55),(x+dx,y+.52,26.32),.06,LIGHT,0)
        p.rod((x+dx,y-.32,25.7),(x+dx,y-.32,26.04),.05,STEEL,0)
        p.rod((x+dx,y-.32,26.04),(x+dx,y+.45,26.04),.05,LIGHT,0)
    for k in range(5): p.box((x,y-.38+k*.17,25.78),(3.2,.13,.14),WOOD,1,.035)
    for k in range(3): p.box((x,y+.43+k*.06,25.96+k*.15),(3.2,.12,.12),WOOD,1,.03)
    for dx in (-1.3,1.3):
        for dy in (-.3,.3): p.rod((x+dx,y+dy,25.16),(x+dx,y+dy,25.19),.035,LIGHT,0,6)
    p.finish()
for i,uv in enumerate([(279,260),(561,337),(715,472),(871,470),(968,379),(1084,513)]):
    x,y=P.xy(uv); p=Part('bollard_%02d'%i,'步道照明_%02d_百叶透光基座'%i,'facilities',(x,y,25),'lighting_bollard')
    p.box((x,y,25.07),(.5,.5,.14),STEEL,0,.06)
    p.box((x,y,25.54),(.26,.26,.86),TILE,1,.04)
    p.box((x,y,26.05),(.30,.30,.20),GOLD,3,.03)
    for zz in (25.96,26.03,26.10): p.box((x,y,zz),(.32,.32,.035),STEEL,0,.015)
    p.box((x,y,26.18),(.40,.40,.10),LIGHT,1,.04); p.finish()
for i,uv in enumerate([(340,276),(989,388)]):
    x,y=P.xy(uv); p=Part('litter_bin_%02d'%i,'分类垃圾箱_%02d_门缝投口踏板'%i,'facilities',(x,y,25),'fixed_litter_bin')
    p.box((x,y,25.12),(1.25,.65,.24),STEEL,0,.06)
    for dx in (-.31,.31):
        p.box((x+dx,y,25.75),(.55,.57,1.25),TILE,1,.09)
        p.box((x+dx,y-.30,25.73),(.47,.05,.87),CREAM,1,.035)
        p.box((x+dx,y-.32,26.14),(.32,.08,.17),DARK,1,.05)
        p.box((x+dx,y-.34,25.83),(.12,.03,.08),BLUE if dx<0 else GREEN,1,.015)
        p.box((x+dx,y-.44,25.16),(.26,.2,.07),STEEL,0,.025)
    p.finish()

# Service equipment is screened on the rear side. No invented units on the plaza.
fan_nodes=[n for n in ast.parse(helper.read_text(encoding='utf8')).body if isinstance(n,ast.FunctionDef) and n.name in ('fan_top','vent_front','bolts')]
exec(compile(ast.Module(body=fan_nodes,type_ignores=[]),str(helper),'exec'),globals())
for i,uv in enumerate([(473,249),(497,256)]):
    x,y=P.xy(uv); p=Part('hvac_%02d'%i,'背侧空调_%02d_扇叶格栅柜门减振脚'%i,'facilities',(x,y,25),'hvac_unit')
    for dx in (-.82,.82):
        for dy in (-.47,.47):
            p.box((x+dx,y+dy,25.13),(.28,.28,.26),DARK,1,.035)
            p.box((x+dx,y+dy,25.27),(.42,.4,.08),STEEL,0,.025)
    p.box((x,y,25.91),(2.25,1.50,1.20),TILE,1,.12)
    p.box((x,y,26.54),(2.33,1.58,.14),LIGHT,1,.05)
    fan_top(p,x,y,26.64,.56)
    vent_front(p,x-.47,y-.78,25.94,.78,.78)
    p.box((x+.60,y-.80,25.9),(.61,.08,.97),CREAM,1,.035)
    for z in (25.6,26.15): p.box((x+.9,y-.855,z),(.05,.07,.13),STEEL,0,.015)
    p.box((x+.47,y-.86,25.93),(.04,.08,.20),STEEL,0,.015)
    p.box((x+.61,y-.86,26.21),(.20,.02,.08),BLUE,2,.01)
    p.rod((x+.6,y+.7,25.45),(x+.6,y+.9,25.45),.075,STEEL,0,10)
    p.finish()
p=Part('service_screen','设备侧半高百叶屏风_不阻主步道','support',(*P.xy((487,263)),25),'service_screen')
for zz in [25.2+i*.14 for i in range(11)]:
    x,y=P.xy((487,263)); p.box((x,y,zz),(6.0,.12,.075),STEEL,0,.02)
for u in (462,512):
    x,y=P.xy((u,263)); p.box((x,y,25.82),(.14,.20,1.64),LIGHT,0,.025)
p.finish()
# Small drains follow known paving edges and remain separate maintenance fixtures.
for i,uv in enumerate([(341,285),(693,467),(965,485),(1159,505)]):
    x,y=P.xy(uv); p=Part('drain_%02d'%i,'检修排水_%02d_格栅沉槽提手'%i,'support',(x,y,25),'drain_bank')
    p.box((x,y,25.03),(2.10,.35,.045),DARK,1,.015)
    for j in range(16): p.box((x-.98+j*.13,y,25.055),(.045,.32,.035),STEEL,0,.01)
    p.box((x+1.5,y,25.04),(.65,.65,.05),TILE2,1,.04)
    p.rod((x+1.40,y,25.075),(x+1.60,y,25.075),.025,STEEL,0,6); p.finish()

# Saved packages, exact shape truth and component ownership are separately audited.
definitions=sorted({p['component_definition'] for p in catalog})
meta=dict(asset_id=ASSET,building_id='塔4',version='v002',source_blend=BLEND.relative_to(R).as_posix(),floor_count=5,floor_height_m=5,roof_height_m=25,terrace_height_m=25,footprint_m=[150,50],component_definition_count=len(definitions),package_count=len(catalog),packages=catalog,shared_palette=PALETTE.relative_to(R).as_posix(),material_source=DONOR.relative_to(R).as_posix(),new_materials_created=0,material_roles=NAMES,source_status='pending_saved_audit',runtime_status='not_exported_not_integrated',block_id='open_world',asset_ledger='scenes::资产主表::'+ASSET,scene_design_docs=['docs/v0.1/design/tower04_mall_source.md'],locked_asset_hashes=locked,reference='详细平面优先，功能分区校核；东端裁切补全',no_post_build_scaling=True,reference_projection='roof-plane orthographic',uncertainties=['参考图为带透视的示意平面，未提供CAD；局部尺寸链不等于整体150m','东侧裁切范围外为补全；不可见内部商铺未制作'])
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_plan.json').write_text(json.dumps(dict(definitions=definitions,reference_rows=judgment,scope='整个塔4源可改；v001、塔2/3、共享材质/贴图、关卡及运行时完全锁定',footprint_m=[150,50],canopy_height_m=4.8,guardrail_height_m=1.2,planter_height_m=.6,slow_lane_m=2,main_walk_m=4),ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(p['category']+'/'+p['slug']+' — '+p['display_name'] for p in catalog),encoding='utf8')

# Fixed v001 comparison camera is retained; separate roof plan / detail cameras.
sc.render.engine='CYCLES'; sc.cycles.samples=48; sc.cycles.use_denoising=True
sc.render.image_settings.file_format='PNG'; sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=.55
world=bpy.data.worlds.new('展示环境_不导出'); world.use_nodes=True; sc.world=world
world.node_tree.nodes['Background'].inputs[0].default_value=(.34,.43,.52,1); world.node_tree.nodes['Background'].inputs[1].default_value=.8
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
    ob['resolution_x']=res[0]; ob['resolution_y']=res[1]; return ob
cameras=[
 (camera('CAM_参考全景',(142,-180,127),(0,0,12),172,(1920,1152)),'01_塔4_参考全景.png'),
 (camera('CAM_俯视轮廓',(0,0,220),(0,0,25),160,(1920,760)),'02_塔4_俯视轮廓.png'),
 (camera('CAM_天台花园',(25,-72,87),(3,0,25),96,(1760,1150)),'03_塔4_天台花园.png'),
 (camera('CAM_左翼转折',(-92,-84,65),(-42,-2,14),87,(1600,1200)),'04_塔4_椭圆左翼.png'),
 (camera('CAM_玻璃亭与格构',(82,-46,73),(35,-4,25),57,(1760,1150)),'05_塔4_玻璃亭与遮阳棚.png'),
 (camera('CAM_设备节点',(1,-8,39),P.xy((491,258))+(26,),13,(1600,1200)),'06_塔4_近景设备与节点.png')]
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for d in prefs.devices: d.use=d.type!='CPU'
    if any(d.type!='CPU' for d in prefs.devices): sc.cycles.device='GPU'
except Exception as exc: print('GPU_FALLBACK',exc,flush=True)
sc.camera=cameras[0][0]; sc.render.resolution_x=1920; sc.render.resolution_y=1152
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D': area.spaces.active.region_3d.view_perspective='CAMERA'; area.spaces.active.clip_end=1000; area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('TOWER04_R2_SOURCE_SAVED',len(catalog),flush=True)
if '--no-render' not in sys.argv:
    for cam,name in cameras:
        sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/name)
        bpy.ops.render.render(write_still=True); print('TOWER04_R2_RENDER',name,flush=True)
sc.camera=cameras[0][0]; sc.render.resolution_x=1920; sc.render.resolution_y=1152
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
assert all(hashlib.sha256((R/path).read_bytes()).hexdigest()==sha for path,sha in locked.items())
print('TOWER04_R2_COMPLETE',flush=True)
