# -*- coding: utf-8 -*-
"""ShellStorm2 rooftop courtyard: editable, palette-only component source."""

import sys as _art_source_sys
from pathlib import Path as _ArtSourcePath
_art_source_sys.path.insert(0, str(_ArtSourcePath(__file__).resolve().parents[1]))
from art_source_paths import source_path
import bpy, math, random, json, os, hashlib
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2')
OUT=R/'outputs/rooftop_courtyard_v001'
BASE=R/'assets/art/environments/rooftop_courtyard_3d'
SRC=source_path(BASE/'source/prp_rooftop_courtyard/prp_rooftop_courtyard_source_v001.blend')
PAL=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
random.seed(1007)
# The original session has already been backed up; new scene leaves it intact.
if bpy.data.scenes.get('复古天台庭院_v001'):
    old=bpy.data.scenes['复古天台庭院_v001']
    for ob in list(old.objects):bpy.data.objects.remove(ob,do_unlink=True)
    for c in list(bpy.data.collections):
        if c.name!='Collection':bpy.data.collections.remove(c)
    bpy.data.scenes.remove(old)
for ob in list(bpy.data.objects):
    if ob.name in ('Cube','Camera','Light'):bpy.data.objects.remove(ob,do_unlink=True)
scene=bpy.data.scenes.new('复古天台庭院_v001'); bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene['AssetID']='PRP-ROOFTOP-COURTYARD-3D'; scene['block_id']='rooftop'; scene['floor_range']='100F'
scene['design_scope']='15x10m fixed courtyard; no gameplay services; no existing rooftop overwrite'
scene['scene_design_docs']='docs/v0.1/05.1_关卡区块设计.md; docs/v0.1/07_技术施工_基地设施.md; docs/v0.1/10_资产与内容规范.md'
scene['asset_ledger']='ledger_index.json::scenes::资产主表 / 3D-设施'
root=bpy.data.collections.new('复古天台庭院_中文资产管理'); scene.collection.children.link(root)
def coll(name,parent):
    c=bpy.data.collections.new(name); parent.children.link(c); return c
source=coll('01_制作组件_按设施拆分',root)
output=coll('02_游戏输出_独立资产包_v001',root)
display=coll('90_展示与验收_灯光相机',root)
image=bpy.data.images.load(str(PAL),check_existing=True); image.filepath=str(PAL)
roles=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,name in enumerate(roles):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes=True
    n=m.node_tree.nodes; n.clear(); uv=n.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
    tx=n.new('ShaderNodeTexImage'); tx.image=image; tx.interpolation='Closest'
    bs=n.new('ShaderNodeBsdfPrincipled'); out=n.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(uv.outputs['UV'],tx.inputs['Vector']); m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
    bs.inputs['Metallic'].default_value=[.84,.02,.15,0][i]
    bs.inputs['Roughness'].default_value=[.3,.74,.16,.36][i]
    bs.inputs['Coat Weight'].default_value=[.12,0,.65,0][i]
    if i==3:
        m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=1.35
    m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface']); mats.append(m)
# Palette cells are (column, row from bottom). No new private palette.
CEMENT=(9,2); LIGHT=(9,0); WALL=(9,1); INK=(9,9); WOOD=(8,0); WOODLIGHT=(8,7); WOODDARK=(9,7)
RUST=(1,7); RED=(4,8); GOLD=(6,9); GREEN=(6,5); PAPER=(8,6); STEEL=(9,4); GLASS=(9,3)
packages=[]; cur=None
class Builder:
    def __init__(self,slug,name,origin=(0,0,0),kind='fixed_display_attachment'):
        self.slug=slug; self.name=name; self.origin=Vector(origin); self.kind=kind
        self.v=[]; self.f=[]; self.colors=[]; self.roles=[]; self.anim=[]
        self.collection=coll(name+'_资产包',output)
        self.empty=bpy.data.objects.new('prp_'+slug+'_root',None); self.collection.objects.link(self.empty); self.empty.location=origin
        self.empty['package_id']=slug; self.empty['asset_version']='v001'; self.empty['fixed_display_attachment']=kind=='fixed_display_attachment'
        self.empty['block_id']='rooftop'; self.empty['floor_range']='100F'
        packages.append(self)
    def mesh(self,verts,faces,color=WOOD,role=1):
        start=len(self.v); self.v.extend([tuple(Vector(p)-self.origin) for p in verts]); self.f.extend([tuple(start+i for i in f) for f in faces]); self.colors.extend([color]*len(faces)); self.roles.extend([role]*len(faces))
    def finish(self):
        meshes=[]
        for emissive in (False,True):
            ids=[i for i,r in enumerate(self.roles) if (r==3)==emissive]
            if not ids: continue
            verts=[]; faces=[]; colors=[]; roles2=[]; remap={}
            for i in ids:
                face=[]
                for ix in self.f[i]:
                    if ix not in remap: remap[ix]=len(verts); verts.append(self.v[ix])
                    face.append(remap[ix])
                faces.append(face); colors.append(self.colors[i]); roles2.append(self.roles[i])
            me=bpy.data.meshes.new(self.slug+('_em' if emissive else '_body')); me.from_pydata(verts,[],faces); me.update()
            for mat in ([mats[3]] if emissive else mats[:3]): me.materials.append(mat)
            ob=bpy.data.objects.new(self.name+('_柔和自发光' if emissive else '_主体'),me); self.collection.objects.link(ob); ob.parent=self.empty
            for p,r in zip(me.polygons,roles2): p.material_index=0 if emissive else r
            uv=me.uv_layers.new(name='PaletteUV'); uv.active_render=True
            for p,c in zip(me.polygons,colors):
                for j,li in enumerate(p.loop_indices):
                    a=2*math.pi*j/len(p.loop_indices); uv.data[li].uv=((c[0]+.5)/10+.025*math.cos(a),(c[1]+.5)/10+.025*math.sin(a))
            ob['package_id']=self.slug; ob['fixed_display_attachment']=True
            meshes.append(ob)
        return meshes

def use(slug,name,origin=(0,0,0),kind='fixed_display_attachment'):
    global cur; cur=Builder(slug,name,origin,kind); return cur

def box(p,s,color=WOOD,role=1,rot=0):
    x,y,z=p; a,b,c=[d/2 for d in s]; co=math.cos(rot); si=math.sin(rot)
    vs=[]
    for xx,yy,zz in [(-a,-b,-c),(-a,-b,c),(-a,b,-c),(-a,b,c),(a,-b,-c),(a,-b,c),(a,b,-c),(a,b,c)]: vs.append((x+xx*co-yy*si,y+xx*si+yy*co,z+zz))
    cur.mesh(vs,[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)],color,role)

def rod(a,b,r=.02,color=INK,role=0,n=10,r2=None):
    a,b=Vector(a),Vector(b); d=(b-a).normalized(); t=d.cross(Vector((0,0,1)))
    if t.length<.001:t=d.cross(Vector((0,1,0)))
    t.normalize(); q=d.cross(t); vs=[]
    for p,rad in [(a,r),(b,r if r2 is None else r2)]:
        for i in range(n): vs.append(tuple(p+rad*(t*math.cos(i*math.tau/n)+q*math.sin(i*math.tau/n))))
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    cur.mesh(vs,fs,color,role)

def tube(points,r=.02,color=INK,role=0,n=7):
    for a,b in zip(points,points[1:]): rod(a,b,r,color,role,n)

def ring(p,r=.4,th=.018,color=STEEL,role=0,n=40,plane='XY'):
    x,y,z=p; pts=[]
    for i in range(n+1):
        a=i*math.tau/n; xx,yy=r*math.cos(a),r*math.sin(a)
        pts.append((x+xx,y+yy,z) if plane=='XY' else ((x+xx,y,z+yy) if plane=='XZ' else (x,y+xx,z+yy)))
    tube(pts,th,color,role,6)

def lathe(p,profile,color=WOOD,role=1,n=24):
    x,y,z=p; vs=[]
    for rad,h in profile:
        for i in range(n):vs.append((x+rad*math.cos(i*math.tau/n),y+rad*math.sin(i*math.tau/n),z+h))
    fs=[]
    for j in range(len(profile)-1):
        for i in range(n): fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    cur.mesh(vs,fs,color,role)

def sphere(p,s,color=LIGHT,role=1,n=16,m=8):
    vs=[]
    for j in range(m+1):
        t=.001+(math.pi-.002)*j/m
        for i in range(n):
            a=math.tau*i/n; vs.append((p[0]+s[0]*math.sin(t)*math.cos(a),p[1]+s[1]*math.sin(t)*math.sin(a),p[2]+s[2]*math.cos(t)))
    fs=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(m) for i in range(n)]
    fs +=[tuple(reversed(range(n))),tuple(range(n*m,n*(m+1)))];cur.mesh(vs,fs,color,role)

def leaf(p,a,length=.2,width=.065,color=GREEN,lean=.35):
    d=Vector((math.cos(a),math.sin(a),lean)); q=Vector((-math.sin(a),math.cos(a),0)); p=Vector(p)
    vs=[tuple(p),tuple(p+d*length*.5+q*width),tuple(p+d*length+Vector((0,0,-length*.15))),tuple(p+d*length*.5-q*width),tuple(p+d*length*.5+Vector((0,0,.025)))]
    cur.mesh(vs,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],color,1)

def sway(builder,axis=1,amp=.012,period=192):
    ob=builder.empty
    for f in range(1,241,12):
        ob.rotation_euler[axis]=amp*math.sin((f-1)*math.tau/period); ob.keyframe_insert(data_path='rotation_euler',frame=f)
    ob.rotation_euler[axis]=0; ob.keyframe_insert(data_path='rotation_euler',frame=241)
    builder.anim.append({'type':'sway','axis':axis,'amplitude_rad':amp,'period_frames':period})

def rotate(builder,axis=1,turns=4):
    ob=builder.empty
    ob.rotation_euler[axis]=0; ob.keyframe_insert(data_path='rotation_euler',frame=1)
    ob.rotation_euler[axis]=turns*math.tau; ob.keyframe_insert(data_path='rotation_euler',frame=241)
    if ob.animation_data and ob.animation_data.action:
        try:
            for fc in ob.animation_data.action.fcurves:
                for k in fc.keyframe_points:k.interpolation='LINEAR'
                fc.modifiers.new('CYCLES')
        except:pass
    builder.anim.append({'type':'rotation','axis':axis,'turns_per_10s':turns})
# OWN load-bearing slab, not a presentation plinth. Entire footprint exactly 15 x 10.
use('courtyard_slab','01_完整旧水泥天台底座',(0,0,0),'architecture')
box((0,0,.16),(15,10,.32),CEMENT);box((0,-4.96,.11),(14.95,.06,.12),INK)
for i in range(220):
    x=random.uniform(-7.3,7.3); y=random.uniform(-4.8,4.8)
    if -5<x<4 and -2.6<y<3.9:continue
    length=random.uniform(.1,.7);box((x,y,.324),(length,.02,.004),GLASS,1,random.random()*3)
for pts in [[(-7,-3,.327),(-6,-2.8,.327),(-5.8,-2,.327),(-5.1,-1.6,.327)],[(3.9,-4.7,.327),(4.4,-3.8,.327),(4.15,-3,.327),(4.7,-2.1,.327)],[(5.5,2.8,.327),(6,1.9,.327),(5.8,1.3,.327),(6.7,.7,.327)]]:
    tube(pts,.008,INK,1,5)
# Two low parapets; cut-away back wall leaves the viewing front open.
use('parapet_back','02_后侧矮水泥护栏',(0,4.7,.32),'architecture')
box((0,4.72,.77),(15,.48,.9),WALL);box((0,4.72,1.25),(15,.58,.09),LIGHT)
for x in [-7.2,-3.8,0,3.8,7.2]:box((x,4.41,.77),(.17,.08,.9),CEMENT)
use('parapet_left','03_左侧矮水泥护栏',(-7.2,0,.32),'architecture')
box((-7.23,0,.77),(.46,9.42,.9),WALL);box((-7.23,0,1.25),(.57,9.45,.09),LIGHT)
use('weathered_wall','04_斑驳侧墙',(-6.9,2,.32),'architecture')
box((-6.87,2.25,1.95),(.28,4.3,3.26),CEMENT)
# Paint flakes in shallow chipped rectangles with uneven joints.
for i in range(105):
    y=random.uniform(.2,4.35);z=random.uniform(.6,3.48)
    box((-6.718,y,z),(.018,random.uniform(.08,.46),random.uniform(.04,.18)),WALL if i%3 else WOOD)
for z in [.55,.85,1.15]:
    for j in range(10):box((-6.708,.28+j*.4,z),(.025,.37,.22),WOODDARK)
# Raised timber floor top = slab top + 0.10m = .42m.
use('timber_deck','05_十厘米风化木平台',(-.9,.5,.32),'floor')
for j in range(27):
    y=-2.65+j*.239
    for i in range(3):
        x=-3.5+i*2.99; c=random.choice([WOOD,WOOD,WOODLIGHT,WOODDARK])
        box((x,y,.37),(2.965,.227,.1),c)
        for end in [-1.43,1.43]:
            for yy in [-.073,.073]:rod((x+end,y+yy,.421),(x+end,y+yy,.425),.013,INK,0,8)
        for k in range(4):
            xx=x+random.uniform(-1.3,1.3); yy=y+random.uniform(-.08,.08)
            tube([(xx-.22,yy,.423),(xx,yy+.008,.423),(xx+.24,yy,.423)],.003,WOODDARK,1,4)
box((-.51,-2.83,.365),(9.02,.13,.09),WOODLIGHT)
# Deck perimeter and fence only on rear/right, no enclosing front obstruction.
use('low_fence','06_矮木围栏',(4.03,1.4,.42))
for y in [-1.8,-.6,.6,1.8,3.45]:box((4.03,y,.98),(.12,.12,1.12),WOODDARK)
for z in [.75,1.19]:box((4.03,.85,z),(.09,5.35,.095),WOOD)
for y in [-1.6+i*.34 for i in range(15)]:box((4.04,y,.93),(.075,.1,.78),WOOD)
box((4.105,.6,1.13),(.025,.68,.34),LIGHT)
# enamel number plate as physical geometric strokes, not interface.
for y in [.43,.61,.79]:box((4.125,y,1.13),(.012,.025,.19),RED)
# Shed precisely covers single sofa, not whole courtyard.
use('shelter_frame','07_风化木梁角钢棚架',(-3.6,2.05,.42),'architecture')
for x in [-5.35,-1.8]:
    for y in [.62,3.8]:
        box((x,y,1.95),(.14,.14,3.06),WOODDARK)
        box((x,y,.58),(.2,.2,.32),STEEL,0)
        for z in [.58,3.25]:
            box((x,y-.08,z),(.22,.035,.22),RUST,0)
            for dz in [-.06,.06]:rod((x,y-.104,z+dz),(x,y-.115,z+dz),.018,INK,0)
for y in [.62,3.8]:box((-3.57,y,3.48),(3.72,.17,.19),WOOD)
for x in [-5.35,-1.8]:box((x,2.2,3.47),(.17,3.35,.2),WOOD)
for x in [-5.35,-1.8]:rod((x,.62,2.85),(x,1.28,3.45),.055,WOODDARK,1,8)
# Wavy tin sheets, actual corrugation geometry.
use('corrugated_roof','08_做旧波纹铁皮',(-3.6,2.2,3.5))
for strip in range(3):
    vs=[];fs=[]
    for j in range(3):
        y=.42+j*1.75
        for i in range(65):
            x=-5.51+strip*1.26+i*1.26/64;z=3.52+.045*math.sin(i*math.pi/4)+.065*(y-.42)
            vs.append((x,y,z))
    for j in range(2):
        for i in range(64):fs.append((j*65+i,j*65+i+1,(j+1)*65+i+1,(j+1)*65+i))
    cur.mesh(vs,fs,STEEL if strip!=1 else GLASS,0)
    for i in range(9):box((-5.45+strip*1.26+i*.13,.41,3.54),(.07,.09,.008),RUST,0)
# Canvas flap with a slight sag and baked shape-key breeze later.
use('roof_canvas','09_半旧灰帆布',(-3.2,2.3,3.58))
vs=[];fs=[]
for j in range(13):
    for i in range(17):
        x=-4.8+i*2.85/16;y=.45+j*3.34/12;z=3.59+.065*(y-.42)+.02*math.sin(i*.8)-.08*math.sin(i*math.pi/16)*math.sin(j*math.pi/12)
        vs.append((x,y,z))
for j in range(12):
    for i in range(16):fs.append((j*17+i,j*17+i+1,(j+1)*17+i+1,(j+1)*17+i))
cur.mesh(vs,fs,WOOD,1)
# Rope web on the rear and short fringe, clear front window.
use('rope_net','10_磨损绳网与碎布',(-5.36,3,2.95))
for j in range(8):
    z=2.28+j*.15;tube([(-5.39,.7,z),(-5.43,2.3,z-.1),(-5.4,3.7,z)],.008,WOODLIGHT,1,5)
for j in range(14):
    y=.7+j*.23;tube([(-5.38,y,3.4),(-5.46,y,2.9),(-5.39,y,2.3)],.008,WOODLIGHT,1,5)
for x in [-5.1+i*.3 for i in range(11)]:box((x,.41,3.38),(.09,.04,random.uniform(.12,.3)),WOOD)
sway(cur,0,.009)
# Sofa focus, sewn rounded cushions are many shallow rounded meshes rather than texture maps.
use('corduroy_sofa','11_灯芯绒单人沙发',(-3.65,2.6,.42))
for x in [-4.4,-2.9]:
    for y in [1.88,3.18]:box((x,y,.56),(.12,.12,.28),WOODDARK)
box((-3.65,2.53,.77),(1.86,1.53,.32),WOODDARK)
sphere((-3.65,2.48,1.02),(.83,.65,.2),WOOD)
sphere((-3.65,3.12,1.52),(.84,.22,.65),WOODDARK)
for x in [-4.55,-2.75]:sphere((x,2.56,1.2),(.23,.8,.32),WOODDARK)
for i in range(73):
    x=-4.44+i*.022
    rod((x,1.96,1.09),(x,2.98,1.12),.006,WOODDARK,1,5)
    rod((x,2.91,1.13),(x,2.92,1.91),.005,WOOD,1,5)
for x in [-4.25,-3.65,-3.05]:sphere((x,2.9,1.56),(.032,.02,.033),INK,1,8,4)
for x in [-4.48,-2.82]:tube([(x,1.9,1.22),(x,2.1,1.41),(x,3.16,1.42)],.012,WOODLIGHT,1)
# Side table + radio, each independently replaceable.
use('side_table','12_旧实木边几',(-1.03,2.55,.42))
box((-1.03,2.55,1.24),(1.21,.9,.09),WOOD)
for x in [-1.51,-.55]:
    for y in [2.21,2.9]:box((x,y,.83),(.095,.095,.82),WOODDARK)
box((-1.03,2.55,.65),(1.07,.8,.045),WOODLIGHT)
box((-1.03,2.1,1.12),(1.05,.07,.18),WOODDARK)
rod((-1.1,2.044,1.12),(-.96,2.044,1.12),.02,STEEL,0)
use('valve_radio','13_木壳灯丝收音机',(-1.04,2.7,1.29))
box((-1.04,2.7,1.62),(.88,.36,.65),WOODLIGHT)
box((-1.04,2.508,1.62),(.78,.025,.53),WOODDARK)
for i in range(20):box((-1.36+i*.02,2.486,1.6),(.007,.012,.38),WOOD)
box((-.83,2.482,1.72),(.34,.025,.12),GOLD,3)
for i in range(15):box((-1+i*.023,2.465,1.73),(.006,.007,.034 if i%3 else .065),INK)
for x in [-.95,-.69]:rod((x,2.49,1.5),(x,2.436,1.5),.049,STEEL,0,20)
ring((-.95,2.431,1.5),.036,.004,LIGHT,0,20,'XZ')
rod((-1.37,2.7,1.9),(-1.16,2.7,2.24),.009,STEEL,0)
use('radio_pointer','14_调频游走指针',(-.85,2.458,1.72))
box((-.85,2.458,1.72),(.007,.006,.085),RED,3)
for f in [1,61,121,181,241]:cur.empty.location.x=-.85+.027*math.sin((f-1)*math.tau/240);cur.empty.keyframe_insert(data_path='location',frame=f)
cur.anim.append({'type':'tuning','amplitude_m':.027})
use('radio_pilot','15_呼吸指示灯',(-.67,2.46,1.81))
sphere((-.67,2.46,1.81),(.018,.012,.018),GOLD,3,12,6)
for f in [1,31,61,91,121,151,181,211,241]:
    s=1+.08*math.sin((f-1)*math.tau/120);cur.empty.scale=(s,s,s);cur.empty.keyframe_insert(data_path='scale',frame=f)
cur.anim.append({'type':'breathing_indicator','amplitude':.08})
use('enamel_mug','16_白瓷红边茶缸',(-1.28,2.26,1.29))
lathe((-1.28,2.26,1.29),[(0,0),(.09,0),(.105,.17),(.105,.19),(.093,.19),(.087,.025),(0,.025)],LIGHT,1)
ring((-1.28,2.26,1.48),.099,.008,RED,1,32)
ring((-1.16,2.26,1.38),.055,.012,LIGHT,1,20,'XZ')
use('table_ephemera','17_烟灰缸与卷报',(-.75,2.25,1.29))
lathe((-.78,2.22,1.29),[(0,0),(.12,0),(.135,.04),(.135,.06),(.11,.06),(.09,.02),(0,.02)],LIGHT,2)
for i in range(3):rod((-.85+i*.055,2.2,1.33),(-.82+i*.055,2.25,1.34),.012,PAPER,1,6)
rod((-.56,2.48,1.35),(-.56,2.06,1.35),.064,PAPER,1,20)
for i in range(9):rod((-.598,2.07+i*.04,1.394),(-.57,2.07+i*.04,1.409),.002,INK,1,4)
# Vintage television foreground, large readable convex CRT.
use('crt_television','18_老式黑白电视',(.8,-.94,.42))
for x in [.2,1.4]:
    for y in [-1.17,-.67]:box((x,y,.55),(.11,.1,.25),WOODDARK)
box((.8,-.9,1.02),(1.55,.74,.97),WOOD)
box((.8,-1.285,1.06),(1.43,.035,.84),INK)
sphere((.63,-1.305,1.06),(.51,.063,.35),GLASS,2,24,12)
for x in [1.32]:
    for z in [.94,1.21]:rod((x,-1.3,z),(x,-1.375,z),.07,STEEL,0,20)
for i in range(7):box((1.33,-1.329,.77+i*.027),(.18,.012,.01),STEEL,0)
for s in [-1,1]:rod((.8,-.8,1.54),(.8+s*.49,-.8,2.08),.012,STEEL,0)
use('tv_static','19_细碎雪花光点',(.63,-1.38,1.06))
for i in range(185):
    x=random.uniform(.17,1.08);z=random.uniform(.79,1.34)
    if ((x-.63)/.49)**2+((z-1.06)/.32)**2>1:continue
    box((x,-1.37,z),(random.uniform(.006,.018),.006,.008),random.choice([LIGHT,GLASS,WALL]),3)
for f in range(1,242,4):cur.empty.location.z=1.06+random.uniform(-.005,.005);cur.empty.keyframe_insert(data_path='location',frame=f)
cur.anim.append({'type':'tv_static','update_hz':6})
# Table fan body and separate rotating blade root.
use('desk_fan','20_铁壳台式电风扇',(2.7,1.85,.42))
sphere((2.7,1.85,.54),(.38,.28,.12),STEEL,0)
rod((2.7,1.85,.55),(2.7,1.85,1.21),.066,STEEL,0)
rod((2.7,1.87,1.51),(2.7,2.07,1.51),.15,INK,0,20)
for r in [.15,.25,.36,.47]:ring((2.7,1.74,1.51),r,.007,STEEL,0,40,'XZ')
for i in range(28):
    a=i*math.tau/28;rod((2.7+.1*math.cos(a),1.68,1.51+.1*math.sin(a)),(2.7+.48*math.cos(a),1.74,1.51+.48*math.sin(a)),.006,STEEL,0,5)
use('desk_fan_blades','21_风扇匀速扇叶',(2.7,1.84,1.51))
for i in range(3):
    a=i*math.tau/3
    vs=[]
    for rr,ang in [(.08,a),(.42,a+.1),(.43,a+.65),(.12,a+.95)]:vs.append((2.7+rr*math.cos(ang),1.82,1.51+rr*math.sin(ang)))
    cur.mesh(vs,[(0,1,2,3),(3,2,1,0)],WOODLIGHT,0)
sphere((2.7,1.82,1.51),(.1,.065,.1),WOOD,0);rotate(cur,1,4)
# Stacked wooden slatted crates / luggage.
for i,(x,y,z,ang) in enumerate([(-4.2,-1.25,.42,-.12),(-4.14,-1.23,1.12,.08),(-2.8,-1.37,.42,.1),(-5.3,-.05,.42,.04)]):
    use('wood_crate_'+str(i+1),'22_'+str(i+1)+'_旧木箱',(x,y,z))
    for xx in [-.55,.55]:
        for yy in [-.35,.35]:box((x+xx,y+yy,z+.32),(.075,.075,.64),WOODDARK,1,ang)
    for j in range(4):
        zz=z+.07+j*.16
        for yy in [-.36,.36]:box((x,y+yy,zz),(1.16,.055,.125),WOOD if j%2 else WOODLIGHT,1,ang)
        for xx in [-.56,.56]:box((x+xx,y,zz),(.055,.75,.125),WOOD,1,ang)
    for j in range(5):box((x-.46+j*.23,y,z+.65),(.21,.78,.05),WOOD,1,ang)
    for xx in [-.52,.52]:
        for yy in [-.39,.39]:rod((x+xx,y+yy,z+.646),(x+xx,y+yy,z+.676),.014,STEEL,0,8)
for i,(x,y,z) in enumerate([(-4.12,-1.2,1.83),(-2.78,-1.32,1.1),(-2.55,-1.3,1.43)]):
    use('leather_case_'+str(i+1),'23_'+str(i+1)+'_牛皮旅行箱',(x,y,z))
    box((x,y,z+.16),(1.12,.64,.32),WOODDARK)
    for xx in [-.4,.4]:box((x+xx,y,z+.328),(.045,.64,.02),WOODLIGHT)
    for xx in [-.45,.45]:box((x+xx,y-.333,z+.18),(.09,.025,.065),STEEL,0)
    tube([(x-.11,y-.36,z+.19),(x-.11,y-.4,z+.25),(x+.11,y-.4,z+.25),(x+.11,y-.36,z+.19)],.025,WOOD,1)
# Foldable canvas chair.
use('folding_chair','24_半旧折叠帆布椅',(.25,.65,.42))
for x in [-.2,.7]:
    rod((x,.28,.43),(x,1.18,1.16),.025,STEEL,0)
    rod((x,1.18,.43),(x,.28,1.16),.025,STEEL,0)
    rod((x,1.11,.88),(x,1.29,1.88),.025,STEEL,0)
box((.25,.75,1.08),(.95,.75,.035),WOOD)
vs=[(-.22,1.14,1.28),(.72,1.14,1.28),(.72,1.29,1.85),(-.22,1.29,1.85)]
cur.mesh(vs,[(0,1,2,3),(3,2,1,0)],WOODLIGHT)
for x in [-.22,.72]:rod((x,.33,1.17),(x,1.2,1.25),.04,WOOD,1)
# Tire table, rotary phone, tin and books.
use('tire_table','25_旧轮胎圆桌',(1.6,-2,.42))
lathe((1.6,-2,.42),[(.35,0),(.52,.08),(.56,.3),(.5,.42),(.3,.43),(.3,.35)],INK,1,40)
for i in range(36):
    a=math.tau*i/36;box((1.6+.545*math.cos(a),-2+.545*math.sin(a),.67),(.05,.05,.19),STEEL,1,a)
lathe((1.6,-2,.85),[(0,0),(.57,0),(.57,.045),(0,.045)],WOOD)
use('rotary_phone','26_拨盘老电话',(1.57,-2,.9))
box((1.57,-2,1.015),(.44,.35,.23),INK)
ring((1.57,-2.03,1.135),.113,.018,WOODLIGHT,0,32)
for i in range(10):
    a=i*math.tau/10;rod((1.57+.089*math.cos(a),-2.03+.089*math.sin(a),1.132),(1.57+.089*math.cos(a),-2.03+.089*math.sin(a),1.146),.015,INK,1,8)
tube([(1.35,-1.92,1.14),(1.35,-1.92,1.25),(1.8,-1.92,1.25),(1.8,-1.92,1.14)],.045,INK,1,12)
tube([(1.78,-1.9,1.22),(1.88,-1.91,1),(1.87,-2.15,.93),(1.65,-2.21,.92)],.009,INK,1,6)
use('books_and_frames','27_旧书相框铁皮饼干盒',(-2.54,-.2,.42))
for i in range(7):
    z=.46+i*.105;ang=random.uniform(-.13,.13)
    box((-2.54,-.2,z),(.67,.45,.085),PAPER,1,ang)
    for dz in [-.05,.05]:box((-2.54,-.2,z+dz),(.7,.48,.012),[WOODDARK,WOOD,RED,GREEN][i%4],1,ang)
    for j in range(3):box((-2.54,-.435,z-.025+j*.022),(.61,.003,.002),GLASS)
box((-2.5,.25,1.08),(.58,.07,.65),WOODDARK)
box((-2.5,.206,1.08),(.46,.015,.53),PAPER)
sphere((-2.5,.19,1.14),(.09,.025,.12),WOOD,1)
box((-2.5,.19,.98),(.25,.01,.15),GLASS)
lathe((-3.12,-.05,1.4),[(0,0),(.22,0),(.22,.16),(.23,.17),(0,.17)],WOODLIGHT,0)
ring((-3.12,-.05,1.57),.22,.012,RED,1)
# Bamboo thermos and delicate steam paths; closed curved line geometry animates gently.
use('bamboo_thermos','28_竹壳暖水瓶',(-.8,.25,.42))
lathe((-.8,.25,.42),[(0,0),(.19,0),(.22,.11),(.22,.59),(.16,.67),(.065,.72),(.065,.77),(.052,.77),(.05,.7)],WOODLIGHT)
for i in range(28):
    a=i*math.tau/28;rod((-.8+.22*math.cos(a),.25+.22*math.sin(a),.52),(-.8+.22*math.cos(a),.25+.22*math.sin(a),1.03),.007,WOODDARK,1,5)
for z in [.54,.75,1.02]:ring((-.8,.25,z),.221,.013,WOODDARK,1)
tube([(-.59,.25,.7),(-.47,.25,.73),(-.47,.25,1),(-.61,.25,1.04)],.023,WOODDARK,1)
use('thermos_steam','29_暖水瓶细白热气',(-.8,.25,1.2))
for k in range(3):
    pts=[(-.8+.022*math.sin(i*.6+k),.25+.022*math.cos(i*.5+k),1.2+i*.034) for i in range(18)]
    tube(pts,.003 if k else .004,LIGHT,3,5)
sway(cur,0,.09,144)
# Potted greenery including parapet pots, fixed plants, independent leaves.
plant_positions=[(-5.9,-1.9,.32,.35),(-6.5,3.8,1.3,.26),(-3,4.65,1.3,.26),(2.9,4.65,1.3,.29),(5.7,4.5,.32,.48),(5.8,-1.1,.32,.38),(3.15,3.2,.42,.28),(-1.8,3.8,.42,.25)]
for i,(x,y,z,r) in enumerate(plant_positions):
    use('pot_'+str(i+1),'30_'+str(i+1)+'_陶土花盆',(x,y,z))
    lathe((x,y,z),[(0,0),(r*.65,0),(r,r*1.5),(r*1.08,r*1.5),(r*1.08,r*1.67),(r*.9,r*1.67),(r*.9,r*1.5),(0,r*1.5)],WOODLIGHT if i%3 else RUST)
    lathe((x,y,z+r*1.5),[(0,0),(r*.89,0)],WOODDARK)
    use('foliage_'+str(i+1),'31_'+str(i+1)+'_微风绿叶',(x,y,z+r*1.5))
    for k in range(7):
        a=k*2.399;h=r*random.uniform(1.2,2.8);end=(x+.22*math.cos(a),y+.22*math.sin(a),z+r*1.5+h)
        rod((x,y,z+r*1.5),end,.009,WOODDARK,1,6)
        for j in range(3):
            q=Vector((x,y,z+r*1.5)).lerp(Vector(end),.4+j*.25)
            leaf(q,a+(-1 if j%2 else 1),r*.75,r*.22,[GREEN,(7,5),(5,5)][j%3])
    sway(cur,1,.018,192)
# Bicycle rim: leaning vertical plane, thin spokes.
use('bicycle_rim','32_旧自行车轮圈',(-5.85,1,.42))
for r in [.59,.62]:ring((-5.85,1,1.05),r,.016,STEEL,0,48,'YZ')
for i in range(24):
    a=i*math.tau/24;rod((-5.85,1,1.05),(-5.85,1+.59*math.cos(a),1.05+.59*math.sin(a)),.004,STEEL,0,4)
rod((-5.9,1,1.05),(-5.8,1,1.05),.055,STEEL,0)
# Basin, galvanized bucket, scrolls, old oiled umbrella.
use('enamel_basin','33_白搪瓷脸盆',(4.8,-2.3,.32))
lathe((4.8,-2.3,.32),[(0,0),(.28,0),(.45,.18),(.46,.22),(.42,.22),(.26,.035),(0,.035)],LIGHT)
ring((4.8,-2.3,.54),.44,.017,RED,1,40)
use('galvanized_bucket','34_镀锌桶卷轴油纸伞',(4.85,2.3,.32))
lathe((4.85,2.3,.32),[(0,0),(.26,0),(.36,.66),(.36,.7),(.335,.7),(.245,.025),(0,.025)],STEEL,0)
ring((4.85,2.3,1.02),.352,.018,LIGHT,0)
ring((4.85,2.3,1.1),.4,.012,STEEL,0,32,'XZ')
for i in range(3):rod((4.7+i*.11,2.3,.62),(4.67+i*.11,2.3,1.58+i*.11),.064,PAPER,1,16)
rod((4.88,2.37,.7),(5.14,2.37,2.13),.018,WOODDARK,1)
rod((4.91,2.37,1.04),(5.09,2.37,1.87),.18,WOOD,1,14,.025)
# Glass oil lantern with cage and amber wick.
use('oil_lantern','35_玻璃煤油灯',(-3.04,-1.33,1.79))
lathe((-3.04,-1.33,1.79),[(0,0),(.14,0),(.14,.07),(.085,.13),(.07,.29),(.08,.37),(.04,.4)],STEEL,0)
sphere((-3.04,-1.33,2.03),(.075,.075,.12),GOLD,2,16,8)
rod((-3.04,-1.33,1.93),(-3.04,-1.33,2.08),.018,GOLD,3,10)
for x in [-3.14,-2.94]:rod((x,-1.33,1.86),(x,-1.33,2.15),.01,STEEL,0)
ring((-3.04,-1.33,2.23),.08,.009,STEEL,0,20,'XZ')
# Air conditioner external unit and independent spinning fan.
use('air_conditioner','36_旧空调外机',(-6.62,2.74,2.2))
box((-6.39,2.74,2.56),(.65,1.42,.78),WALL)
box((-6.048,2.74,2.56),(.027,1.28,.65),CEMENT)
ring((-6.019,2.51,2.56),.285,.018,INK,0,40,'YZ')
for i in range(17):
    y=2.24+i*.034;half=math.sqrt(max(0,.28**2-(y-2.51)**2));rod((-6.0,y,2.56-half),(-6.0,y,2.56+half),.006,STEEL,0,5)
for i in range(10):box((-6.018,3.06,2.34+i*.045),(.015,.25,.017),STEEL,0)
for y in [2.18,3.22]:box((-6.55,y,2.14),(.86,.07,.06),RUST,0)
use('ac_fan_blades','37_空调风扇',(-6.055,2.51,2.56))
for k in range(4):
    a=k*math.tau/4;vs=[(-6.055,2.51,2.56),(-6.055,2.51+.25*math.cos(a),2.56+.25*math.sin(a)),(-6.055,2.51+.25*math.cos(a+.6),2.56+.25*math.sin(a+.6))];cur.mesh(vs,[(0,1,2),(2,1,0)],WOODDARK,0)
rotate(cur,0,3)
# Exposed vents and pipes follow wall, do not cross view.
use('wall_services','38_通风管道花线电缆',(-6.4,1.3,.32),'support')
tube([(-6.45,.4,.62),(-6.45,.4,3.03),(-6.45,1.05,3.4),(-6.45,3.97,3.4)],.11,STEEL,0,16)
for y in [1.2,1.8,2.4,3.1,3.8]:ring((-6.45,y,3.4),.116,.013,INK,0,24,'XZ')
for k in range(4):
    tube([(-6.08,3.16,2.22),(-6.58,3.62,1.88),(-6.61,3.84,.53),(-4.8,3.88,.46),(-2,3.85,.45)],.014,INK,1,6)
tube([(-1.2,2.7,1.29),(-1.5,2.75,.53),(-.6,1.9,.43),(1.2,1.4,.43),(2.7,1.85,.52)],.012,INK,1,6)
box((-.65,1.87,.48),(.38,.11,.07),LIGHT)
for x in [-.78,-.66,-.54]:box((x,1.87,.52),(.06,.042,.005),INK)
# Small utility lamp with metal shade.
use('table_lamp','39_旧台灯',(2.7,.14,.42))
lathe((2.7,.14,.42),[(0,0),(.18,0),(.19,.055),(0,.07)],STEEL,0)
tube([(2.7,.14,.47),(2.7,.14,1.13),(2.43,.14,1.43)],.025,STEEL,0)
lathe((2.43,.14,1.27),[(.22,0),(.15,.15),(.045,.23)],WOOD,0)
sphere((2.43,.14,1.31),(.08,.08,.07),GOLD,3)
# Clothes line catenary and independently moving cloth strips.
use('clothes_line','40_晾衣绳旧电线',(0,4.35,2.5),'support')
for x in [-6.05,5.9]:rod((x,4.37,1.3),(x,4.37,2.78),.025,STEEL,0)
for k in range(2):
    pts=[(-6.05+i*11.95/40,4.37+k*.08,2.74-.47*math.sin(math.pi*i/40)) for i in range(41)];tube(pts,.009,WOODDARK if k else INK,1,5)
sway(cur,0,.004)
for i,(x,w,h) in enumerate([(-.8,.65,.9),(.6,.45,.62),(1.6,.55,.72)]):
    z=2.74-.47*math.sin(math.pi*(x+6.05)/11.95)
    use('linen_'+str(i+1),'41_'+str(i+1)+'_旧布巾亚麻手帕',(x,4.38,z))
    vs=[];fs=[]
    for j in range(9):
        for k in range(7):vs.append((x-w/2+k*w/6,4.38+.045*math.sin(k*1.6)*j/8,z-j*h/8))
    for j in range(8):
        for k in range(6):fs.append((j*7+k,j*7+k+1,(j+1)*7+k+1,(j+1)*7+k))
    cur.mesh(vs,fs,WOOD if i==0 else LIGHT)
    for xx in [x-w*.37,x+w*.37]:box((xx,4.38,z+.018),(.03,.04,.09),WOODLIGHT)
    sway(cur,0,.023,192)
# Original fictitious cinema posters: dimensional paper, geometric period art, no texture exception.
for i,(y,z,w,h) in enumerate([(1.1,1.85,.86,1.13),(3.9,1.83,.68,.95)]):
    use('cinema_poster_'+str(i+1),'42_'+str(i+1)+'_褪色旧电影海报',(-6.69,y,z))
    box((-6.69,y,z),(.012,w,h),PAPER)
    box((-6.676,y,z+.17),(.005,w*.83,h*.48),RED if i==0 else GREEN)
    # Film scene silhouettes and ink bars.
    sphere((-6.664,y-.11,z+.26),(.006,.11,.14),WOODDARK,1,12,6)
    box((-6.663,y-.11,z+.06),(.006,.23,.21),INK)
    for j in range(5):box((-6.665,y,z-h*.32+j*.027),(.005,w*(.75 if j%2 else .55),.009),WOODDARK)
    sway(cur,1,.007,144)
# Broom and dustpan in front-left wall corner.
use('bamboo_broom','43_竹扫帚铁皮簸箕',(-6.25,.26,.32))
rod((-6.3,.35,.58),(-6.53,.35,2.15),.021,WOODLIGHT,1)
for i in range(30):
    x=-6.3+(i-15)*.011;rod((x,.35,.37),(-6.3+(i-15)*.003,.35,.94),.006,WOOD,1,5)
box((-6.02,.26,.35),(.42,.37,.03),STEEL,0)
box((-6.02,.445,.46),(.42,.03,.2),STEEL,0)
rod((-6.02,.43,.48),(-6.02,.43,1.07),.018,STEEL,0)
# Old street sign plaque, dried bouquet and loose weeds.
use('road_sign','44_复古路牌残片',(3.3,3.58,.42))
box((3.3,3.57,.94),(1.13,.035,.33),GLASS)
for z in [.8,1.08]:box((3.3,3.543,z),(1.09,.012,.018),LIGHT)
for x in [2.95,3.08,3.21,3.34,3.47]:box((x,3.532,.94),(.05,.006,.1),PAPER)
use('dried_flowers','45_围栏风干花束',(4.15,1.9,1.06))
for k in range(13):
    a=k*2.4;end=(4.21,1.9+.15*math.sin(a),1.34+.17*math.cos(a))
    rod((4.19,1.9,.76),end,.004,WOODLIGHT,1,5)
    sphere(end,(.034,.039,.025),PAPER,1,8,4)
use('weeds_and_debris','46_细草落叶碎石烟蒂',(0,0,.32),'support')
for x,y in [(-5.7,-.3),(3.86,-1.2),(-4.8,-2.9),(4.4,2.8),(6.3,-3.2)]:
    for i in range(9):
        a=random.random()*math.tau;leaf((x+random.uniform(-.14,.14),y+random.uniform(-.14,.14),.335),a,.12,.023,GREEN,1.5)
for i in range(45):
    x=random.uniform(-6.8,6.9);y=random.uniform(-4.7,4.2)
    if -5.1<x<4.1 and -2.9<y<3.9:continue
    if i%3:leaf((x,y,.332),random.random()*math.tau,.16,.048,WOODLIGHT,0)
    else:sphere((x,y,.342),(.048,.031,.018),LIGHT,1,8,4)
for i in range(6):rod((5+i*.09,-3.5,.343),(5.06+i*.09,-3.46,.343),.011,PAPER,1,6)
# Puddle is shaped reflective surface, never rectangular platform.
use('puddle_drain','47_排水口积水冷暖倒影',(5.7,-3.6,.32),'support')
vs=[(5.7,-3.6,.329)]+[(5.7+(1+.11*math.sin(i*1.8))*math.cos(i*math.tau/48),-3.6+(.6+.06*math.sin(i))*math.sin(i*math.tau/48),.329) for i in range(48)]
cur.mesh(vs,[(0,i+1,(i+1)%48+1) for i in range(48)],GLASS,2)
box((6.65,-3.9,.328),(.47,.42,.018),INK)
for i in range(8):box((6.47+i*.05,-3.9,.339),(.021,.38,.01),STEEL,0)
use('puddle_ripples','48_灯影微波纹',(5.7,-3.6,.337))
for r in [.19,.34,.51]:ring((5.7,-3.6,.337),r,.002,WALL,2,40)
for x in [5.48,5.51,5.55]:tube([(x,-3.8,.337),(x+.03,-3.63,.337),(x-.015,-3.5,.337)],.007,GOLD,3,5)
for f in [1,61,121,181,241]:
    s=1+.025*math.sin((f-1)*math.tau/120);cur.empty.scale=(s,s,1);cur.empty.keyframe_insert(data_path='scale',frame=f)
cur.anim.append({'type':'water_ripple','amplitude':.025})
# Bare pendant bulb separate swinging package.
use('pendant_bulb','49_悬吊裸灯泡',(-2.22,.73,3.4),'support')
tube([(-2.22,.73,3.4),(-2.24,.73,3.08),(-2.23,.73,2.83)],.012,INK,1,6)
rod((-2.23,.73,2.77),(-2.23,.73,2.85),.04,INK,0,12)
sphere((-2.23,.73,2.7),(.083,.083,.105),GOLD,3,20,10)
sway(cur,1,.014,144)
# finalize per-component meshes, preserve independent moving pieces.
for p in packages:p.objects=p.finish()
# Canvas / paper corner shape deformation: saved native Blender animation.
for p in packages:
    if p.slug=='roof_canvas' or p.slug.startswith('linen_'):
        ob=p.objects[0];ob.shape_key_add(name='Basis');key=ob.shape_key_add(name='微风起伏')
        for v in key.data:
            co=v.co;co.y+=.018*math.sin(co.x*4)*(.5+abs(co.z));co.z+=.022*math.sin(co.x*3+co.y*2)
        for f in [1,61,121,181,241]:key.value=.5+.5*math.sin((f-1)*math.tau/240);key.keyframe_insert(data_path='value',frame=f)
        p.anim.append({'type':'cloth_shape','max_displacement_m':.028})
# Source objects are linked-data copies in hidden per-package editable collections.
for p in packages:
    sc=coll(p.name+'_制作源',source)
    for ob in p.objects:
        cp=ob.copy();cp.data=ob.data.copy();cp.animation_data_clear();sc.objects.link(cp);cp.name=ob.name+'_可编辑源';cp.parent=None;cp.matrix_world=ob.matrix_world.copy()
source.hide_render=True;source.hide_viewport=True
# Preview lighting and fixed third-person cameras; never exported.
def link(ob):display.objects.link(ob);return ob
def aim(ob,p):ob.rotation_euler=(Vector(p)-ob.location).to_track_quat('-Z','Y').to_euler()
def area(name,p,energy,color,size):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.color=color;d.shape='DISK';d.size=size;o=link(bpy.data.objects.new(name,d));o.location=p;aim(o,(0,0,0));return o
def point(name,p,energy):
    d=bpy.data.lights.new(name,'POINT');d.energy=energy;d.color=(1,.57,.19);d.shadow_soft_size=.24;o=link(bpy.data.objects.new(name,d));o.location=p;return o
area('冷灰天空主光',(1,-6,13),2400,(.73,.82,1),9)
area('暖灰侧光',(-8,-3,7),1400,(1,.86,.65),7)
area('后缘柔光',(1,8,8),1800,(.73,.83,1),6)
point('棚下灯泡暖光',(-2.23,.65,2.64),75);point('台灯暖光',(2.43,.14,1.21),32);point('收音机灯丝近光',(-.86,2.39,1.7),5)
world=bpy.data.worlds.new('冷灰天空');world.use_nodes=True;bg=next((n for n in world.node_tree.nodes if n.type=='BACKGROUND'),None) or world.node_tree.nodes.new('ShaderNodeBackground');wo=next((n for n in world.node_tree.nodes if n.type=='OUTPUT_WORLD'),None) or world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs[0],wo.inputs[0]);bg.inputs['Color'].default_value=(.16,.19,.24,1);bg.inputs['Strength'].default_value=.45;scene.world=world
camera_specs=[('全景第三视角',(17,-23,18),(0,.25,.85),20),('俯视结构',(0,-.01,25),(0,0,0),17),('沙发收音机近景',(4,-8,6.5),(-2.75,2,1.6),8.2),('背面结构',(-17,21,15),(0,0,1),20)]
for name,pos,target,scale in camera_specs:
    d=bpy.data.cameras.new(name);d.type='ORTHO';d.ortho_scale=scale;o=link(bpy.data.objects.new(name,d));o.location=pos;aim(o,target)
scene.camera=bpy.data.objects['全景第三视角'];scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
scene.render.fps=24;scene.frame_start=1;scene.frame_end=240;scene.frame_set(1)
# Fine contour lines are a render-only pass; not another material or duplicated export mesh.
scene.render.use_freestyle=True
fs=scene.view_layers[0].freestyle_settings
if len(fs.linesets):
    style=fs.linesets[0].linestyle;style.color=(.035,.033,.03);style.thickness=.8
# metadata / package directory mirrored with collection.
manifest={'asset_id':scene['AssetID'],'name_zh':'主塔100F复古天台庭院','block_id':'rooftop','floor_range':'100F','design_scope':scene['design_scope'],'scene_design_docs':scene['scene_design_docs'],'asset_ledger':scene['asset_ledger'],'source_blend':str(SRC),'version':'v001','footprint_m':[15,10],'deck_elevation_m':.1,'palette':str(PAL),'material_roles':roles,'triangle_budget':200000,'budget_source':'user explicit 20W faces, conservatively evaluated triangles','packages':[],'runtime_integrated':False,'existing_rooftop_modified':False}
tri=0
for p in packages:
    bbox=[p.empty.matrix_world@ob.matrix_local@Vector(v) for ob in p.objects for v in ob.bound_box]
    count=0
    for ob in p.objects:ob.data.calc_loop_triangles();count+=len(ob.data.loop_triangles)
    tri+=count
    entry={'package_id':p.slug,'name_zh':p.name,'collection':p.collection.name,'root_object':p.empty.name,'objects':[o.name for o in p.objects],'origin_blender':list(p.origin),'dimensions':[max(v[i] for v in bbox)-min(v[i] for v in bbox) for i in range(3)],'bbox_world':[[min(v[i] for v in bbox) for i in range(3)],[max(v[i] for v in bbox) for i in range(3)]],'triangles':count,'kind':p.kind,'fixed_display_attachment':p.kind=='fixed_display_attachment','animations':p.anim,'source_blend':str(SRC),'version':'v001','front':'Blender -Y -> Godot +Z (preview frontage); explicit negative-Y front','expected_glb':str(BASE/'components'/p.slug/('prp_'+p.slug+'_visual_top3d.glb')),'exported':False}
    folder=source_path(BASE/'source/prp_rooftop_courtyard/component_packages_v001'/p.slug);folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2),encoding='utf-8');manifest['packages'].append(entry)
manifest['triangles_source']=tri;assert tri<200000,tri
SRC.parent.mkdir(parents=True,exist_ok=True)
# exclude maintainable Blender source from Godot import.
(source_path(BASE/'source/.gdignore')).write_text('',encoding='utf-8')
(source_path(BASE/'source/prp_rooftop_courtyard/asset_manifest.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
# Activate third-person camera, no overlays, free orbit remains available.
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.overlay.show_overlays=False;ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.shading.type='MATERIAL'
# Remove orphan materials (including empty initial cube material) only if unreferenced.
for m in list(bpy.data.materials):
    if m.users==0:bpy.data.materials.remove(m)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC))
print(json.dumps({'source':str(SRC),'packages':len(packages),'triangles':tri,'animation_packages':sum(bool(p.anim) for p in packages),'materials_in_new_scene':len(mats)},ensure_ascii=False))
