import bpy, bmesh, math, json, os, random, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
PREV=ROOT.parent/'stairwell_art_v019'
LEAVES=['通用墙组件_资产包','通用地板组件_资产包','通用楼梯组件_资产包','墙面装甲与结构框_装饰组件','地面导光与警示_装饰组件','工业管线_装饰组件','灯带与发光几何_装饰组件','楼层标识与海报_装饰组件','控制盒_装饰组件','固定绿植_装饰组件']
C={i:bpy.data.collections[n] for i,n in enumerate(LEAVES)}
M=list(sorted(bpy.data.materials,key=lambda m:m.name))
GRAY=(9,6); WALL=(9,5); DARK=(9,9); EDGE=(9,7); SILVER=(9,2); WHITE=(9,0); ORANGE=(5,7); RED=(3,8); CYAN=(3,9)
def bounds(o):
    p=[o.matrix_world@v.co for v in o.data.vertices]
    return [[min(v[i] for v in p) for i in range(3)],[max(v[i] for v in p) for i in range(3)]]
def sig(o,appearance=True):
    d={'matrix':[list(r) for r in o.matrix_basis], 'parent':o.parent.name if o.parent else None,'verts':[list(v.co) for v in o.data.vertices], 'faces':[list(p.vertices) for p in o.data.polygons]}
    if appearance:
        d.update(materials=[m.name for m in o.data.materials],indices=[p.material_index for p in o.data.polygons],uv=[[list(x.uv) for x in l.data] for l in o.data.uv_layers])
    return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
locked={o.name:sig(o) for i in [2,9] for o in C[i].objects if o.type=='MESH'}
locked.update({o.name:sig(o) for o in C[1].objects if o.get('SS2_platform_railing')})
structural={o.name:sig(o,False) for i in [0,1] for o in C[i].objects if o.type=='MESH'}
(ROOT/'qa'/'locked_before.json').write_text(json.dumps({'full':locked,'geometry':structural},ensure_ascii=False,indent=2))
def uvpaint(o,cell,mat=None):
    if o.data.users>1:o.data=o.data.copy()
    if mat is not None:
        o.data.materials.clear();o.data.materials.append(M[mat])
        for p in o.data.polygons:p.material_index=0
    uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.new(name='PaletteUV')
    for p in o.data.polygons:
        for j,k in enumerate(p.loop_indices):
            a=2*math.pi*j/len(p.loop_indices)
            uv.data[k].uv=((cell[0]+.5)/10+.026*math.cos(a),(cell[1]+.5)/10+.026*math.sin(a))
    o.data.uv_layers.active=uv;uv.active_render=True
    for layer in list(o.data.uv_layers):
        if layer.name!='PaletteUV':o.data.uv_layers.remove(layer)
class Mesh:
    def __init__(self,name,coll,mat=0):self.name=name;self.coll=coll;self.mat=mat;self.v=[];self.f=[];self.cells=[]
    def face(self,vs,cell):
        n=len(self.v);self.v.extend(vs);self.f.append(tuple(range(n,n+len(vs))));self.cells.append(cell)
    def box(self,p,size,cell=EDGE):
        x,y,z=p;a,b,c=[v/2 for v in size]
        vs=[(x+i*a,y+j*b,z+k*c) for i,j,k in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
        for f in [(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]:self.face([vs[i] for i in f],cell)
    def rod(self,a,b,r,cell=EDGE,n=8):
        a,b=Vector(a),Vector(b);d=(b-a).normalized();u=d.cross(Vector((0,0,1)) if abs(d.z)<.9 else Vector((0,1,0))).normalized();v=d.cross(u)
        rings=[[p+r*(math.cos(i*2*math.pi/n)*u+math.sin(i*2*math.pi/n)*v) for i in range(n)] for p in [a,b]]
        self.face(list(reversed(rings[0])),cell);self.face(rings[1],cell)
        for i in range(n):j=(i+1)%n;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],cell)
    def finish(self,bevel=0):
        me=bpy.data.meshes.new(self.name);me.from_pydata(self.v,[],self.f);me.update();o=bpy.data.objects.new(self.name,me);C[self.coll].objects.link(o);me.materials.append(M[self.mat]);uv=me.uv_layers.new(name='PaletteUV')
        for p,cell in zip(me.polygons,self.cells):
            for j,k in enumerate(p.loop_indices):
                a=2*math.pi*j/len(p.loop_indices);uv.data[k].uv=((cell[0]+.5)/10+.026*math.cos(a),(cell[1]+.5)/10+.026*math.sin(a))
        uv.active_render=True
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(me);bm.free();me.update()
        if bevel:
            m=o.modifiers.new('工艺倒角','BEVEL');m.width=bevel;m.segments=2
            m=o.modifiers.new('加权法线','WEIGHTED_NORMAL')
        o['asset_detail_version']='v020';return o
def point(side,u,z,d=0):
    return {'front':(80-u,-2.39+d,z),'back':(u,27.19-d,z),'left':(32.81+d,u,z),'right':(47.19-d,u,z)}[side]
def wallbox(mesh,side,u,z,w,h,depth,cell=GRAY,d=0):
    mesh.box(point(side,u,z,d), (w,depth,h) if side in ['front','back'] else (depth,w,h),cell)
def label(name,body,center,size,side='floor',cell=WHITE,coll=7):
    curve=bpy.data.curves.new(name,'FONT');curve.body=body;curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER';curve.space_character=1.1;curve.extrude=.0005;curve.resolution_u=2
    o=bpy.data.objects.new(name,curve);C[coll].objects.link(o);o.location=center
    bases={'front':((-1,0,0),(0,0,1),(0,1,0)),'back':((1,0,0),(0,0,1),(0,-1,0)),'left':((0,1,0),(0,0,1),(1,0,0)),'right':((0,-1,0),(0,0,1),(-1,0,0)),'floor':((-1,0,0),(0,-1,0),(0,0,1))}
    o.rotation_euler=Matrix(bases[side]).transposed().to_euler();bpy.context.view_layer.update()
    ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=bpy.data.meshes.new_from_object(ev);matrix=o.matrix_world.copy()
    bpy.data.objects.remove(o,do_unlink=True);bpy.data.curves.remove(curve)
    o=bpy.data.objects.new(name,me);C[coll].objects.link(o);o.matrix_world=matrix;uvpaint(o,cell,1);o['asset_detail_version']='v020';return o
# Current file is the inspected v019, all editable archival collections stay untouched.
assert 'v019' in bpy.data.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'env_tower_stairwell_art_source_v020.blend'),compress=True)
for c in bpy.data.collections:
    if c.name in ['楼梯区_组件化美术管理_v019','02_游戏输出_组件包_v019']:c.name=c.name.replace('v019','v020')
# Archive the original accessory design in the prior source file, rebuild in the same leaves.
removed=[]
for i in [3,4,5,6,7,8]:
    for o in list(C[i].objects):removed.append(o.name);bpy.data.objects.remove(o,do_unlink=True)
for o in C[0].objects:uvpaint(o,DARK,1)
for o in C[1].objects:
    if o.name.startswith('地板.'):uvpaint(o,EDGE,1)
# Panel system: original shell interfaces are retained, new skins have thin framed joints.
surfaces=[]
for side in ['left','right']:
    for k in range(6):
        if side=='left' and k==0:continue
        for lo,hi in ([(-20.9,-9.3)] if side=='left' else [(-20.9,-9.3),(-9,2.3)]):surfaces.append((side,-.2+5*k,4.76,lo,hi))
for side in ['front','back']:
    for k in range(3):
        for lo,hi in ([(-20.9,-9.3)] if side=='back' else [(-20.9,-9.3),(-9,2.3)]):surfaces.append((side,35+5*k,4.86,lo,hi))
for idx,(side,u,w,lo,hi) in enumerate(surfaces):
    panel=Mesh(f'墙面_{side}_{idx:02d}_折边装甲板',3,1)
    wallbox(panel,side,u,(lo+hi)/2,w,hi-lo-.10,.07,(9,5 if idx%4 else 6),0)
    panel.finish(.035)
    trim=Mesh(f'墙面_{side}_{idx:02d}_拼缝压边与紧固',3)
    for off in [-w/2,w/2]:wallbox(trim,side,u+off,(lo+hi)/2,.045,hi-lo-.10,.055,EDGE,.055)
    for z in [lo+.14,hi-.14,lo+1.3]:wallbox(trim,side,u,z,w,.065,.06,EDGE,.06)
    for off in [-w/2+.15,w/2-.15]:
        for z in [lo+.24,lo+1.42,hi-.24]:trim.rod(point(side,u+off,z,.07),point(side,u+off,z,.115),.045,SILVER,6)
    # lower kick panel and small bracket registration marks
    wallbox(trim,side,u,lo+.65,w-.2,1.0,.045,DARK,.065)
    trim.finish(.008)
# Floor panels, seams, captive fasteners and subtle wear: all directly hosted by floor component.
rng=random.Random(20)
floor_hosts=[o for o in C[1].objects if o.name.startswith('地板.')]
for idx,host in enumerate(floor_hosts):
    mn,mx=bounds(host);x0,y0,z=mn[0],mn[1],mx[2];x1,y1=mx[:2]
    nx=3 if x1-x0>10 else 1;ny=2 if y1-y0>5.5 else 1
    mesh=Mesh(f'地板_{idx:02d}_钢板分缝与检修紧固',1,1)
    metal=Mesh(f'地板_{idx:02d}_压边与螺钉',1)
    wear=Mesh(f'地板_{idx:02d}_局部磨损印记',1,1)
    for ix in range(nx):
        for iy in range(ny):
            a=x0+(x1-x0)*ix/nx+.11;b=x0+(x1-x0)*(ix+1)/nx-.11;c=y0+(y1-y0)*iy/ny+.11;d=y0+(y1-y0)*(iy+1)/ny-.11
            mesh.box(((a+b)/2,(c+d)/2,z+.006),(b-a,d-c,.012),(9,6 if (ix+iy+idx)%3 else 7))
            for xx in [a+.04,b-.04]:metal.box((xx,(c+d)/2,z+.017),(.037,d-c,.015),EDGE)
            for yy in [c+.04,d-.04]:metal.box(((a+b)/2,yy,z+.017),(b-a,.037,.015),EDGE)
            for xx in [a+.17,b-.17]:
                for yy in [c+.17,d-.17]:
                    metal.rod((xx,yy,z+.01),(xx,yy,z+.026),.065,SILVER,8)
                    wear.box((xx,yy,z+.028),(.065,.012,.002),DARK)
            for j in range(9):
                xx=rng.uniform(a+.2,b-.2);yy=rng.uniform(c+.18,d-.18)
                wear.box((xx,yy,z+.013),(rng.uniform(.035,.15),.008,.0015),(9,5))
    for ob in [mesh.finish(.018),metal.finish(.004),wear.finish()]:ob['host_object']=host.name
# Floor service hatches on real surfaces only.
for idx,(x,y,z) in enumerate([(35.4,1.45,-9),(44.9,21,-15),(44.4,1,-20.9)]):
    m=Mesh(f'地板检修盖_{idx}_框与提手',1)
    m.box((x,y,z+.018),(1.45,1.05,.035),DARK)
    m.box((x,y,z+.04),(1.27,.87,.014),GRAY)
    for dx in [-.47,.47]:m.box((x+dx,y,z+.054),(.24,.075,.02),DARK)
    m.finish(.022)
# Trim the old floating guides by constructing new in-surface edge lights.
for idx,(x0,x1,y0,y1,z) in enumerate([(32.9,47.1,-2.3,3.13,-9),(33.05,46.86,18.2,23.8,-15),(32.9,47.1,-2.2,27.05,-20.9)]):
    m=Mesh(f'地面_{idx}_导光槽',4);e=Mesh(f'地面_{idx}_蓝色引导_UI灯光',4,3)
    for x in [x0,x1]:
        m.box((x,(y0+y1)/2,z+.016),(.14,y1-y0,.03),DARK)
        e.box((x,(y0+y1)/2,z+.034),(.034,y1-y0-.1,.005),(8,9))
    m.finish(.008);e.finish()
for idx,(x,y,z,body) in enumerate([(40,0,-9,'02-03'),(41.7,21.5,-15,'01-02'),(41,0,-20.9,'01 / ACCESS')]):
    label(f'地面喷印_{idx}',body,(x,y,z+.022),.65,'floor',(9,2),4)
    mark=Mesh(f'地面_{idx}_边界警示与箭头',4,1)
    for j in range(14):
        a=33.6+j*.87; yy=2.55 if idx!=1 else 18.48
        mark.face([(a,yy,z+.025),(a+.25,yy,z+.025),(a+.39,yy+.22,z+.025),(a+.14,yy+.22,z+.025)],(9,3))
    for a in [33.35,46.7]:
        mark.face([(a,yy-.5,z+.028),(a+.3,yy-.5,z+.028),(a+.3,yy-.2,z+.028)],ORANGE)
    mark.finish()
# Wall service routes, authentic bent tubes with elbows and saddles.
def route(name,side,coords,r=.045,cell=EDGE):
    m=Mesh(name,5)
    for a,b in zip(coords,coords[1:]):m.rod(point(side,*a),point(side,*b),r,cell,10)
    return m.finish(.009)
for side in ['front','left','right','back']:
    a,b=(33.4,46.55) if side in ['front','back'] else ((2.7,26.55) if side=='left' else (-2.0,26.55))
    for j,z in enumerate(([-20.4,-20.05] if side in ['left','back'] else [-8.6,-8.24,-7.88,1.35,1.65,-20.4,-20.05])):
        route(f'管线_{side}_并行_{j}',side,[(a,z-.3,.18),(a+.2,z,.18),(b-.2,z,.18),(b,z-.24,.18)],.043 if j%2 else .06)
    clamps=Mesh(f'管线_{side}_固定管卡',5)
    for u in [a+.35+(b-a-.7)*k/5 for k in range(6)]:
        for z in ([-20.22] if side in ['left','back'] else [-8.24,1.5,-20.22]):wallbox(clamps,side,u,z,.075,.83 if z==-8.24 else .48,.10,EDGE,.24)
    clamps.finish(.012)
for u in [33.45,33.73,34.02]:route(f'主墙_左侧电箱竖管_{u}','front',[(u,-8.6,.23),(u,.8,.23),(u+.3,1.35,.23)],.048)
route('主墙_右侧红色电缆','front',[(46.1,-7.6,.22),(46.1,1.48,.22)],.09,RED)
# Recessed ventilation grille on focus wall at skirting.
def grille(name,side,u,z,w,h):
    m=Mesh(name,3);wallbox(m,side,u,z,w,h,.19,DARK,.21)
    for du in [-w/2,w/2]:wallbox(m,side,u+du,z,.09,h,.12,SILVER,.32)
    for k in range(9):wallbox(m,side,u,z-h*.42+k*h*.105,w-.16,.052,.16,EDGE,.34)
    return m.finish(.014)
grille('主墙_底部散热百叶','front',41.95,-7.95,2.45,.95)
grille('下层_墙面检修百叶','right',12.5,-18.7,2.3,1.15)
# Reference electrical boxes: backplate, orange red painted door, latch, small labels.
def control(name,side,u,z,w,h,color):
    m=Mesh(name+'_箱体与门板',8,1);wallbox(m,side,u,z,w,h,.42,EDGE,.26);wallbox(m,side,u,z,w-.12,h-.12,.06,color,.51);m.finish(.055)
    m=Mesh(name+'_锁扣与接头',8)
    wallbox(m,side,u+w*.30,z-.18,.075,.30,.075,SILVER,.57)
    for du in [-w*.33,w*.33]:
        for zz in [z-h*.37,z+h*.37]:m.rod(point(side,u+du,zz,.55),point(side,u+du,zz,.59),.035,SILVER,6)
    m.finish(.006)
    if h>1:label(name+'_铭牌','DANGER\nHIGH VOLTAGE',point(side,u,z+.12,.558),w*.095,side,WHITE,8)
control('主墙左侧配电箱','front',33.82,-1.2,1.35,1.55,RED)
control('主墙右侧警示箱','front',46.08,-4.95,.92,1.27,(7,4))
control('下层红色接线盒','right',10.3,-18.8,.92,1.20,RED)
for u in [40.9,46.15]:
    control(f'主墙上沿线路盒_{u}','front',u,1.24,1.0,.72,DARK)
    label(f'线路盒_{u}_编号','~ ~',point('front',u,1.24,.57),.22,'front',ORANGE,8)
# Frame and true mountain graphics replacing zigzag beams.
def poster(name,side,u,z,w,h,title):
    m=Mesh(name+'_金属细框',7);wallbox(m,side,u,z,w,h,.11,EDGE,.10)
    wallbox(m,side,u,z,w-.16,h-.16,.025,(9,8),.17)
    for du in [-w/2+.065,w/2-.065]:wallbox(m,side,u+du,z,.035,h-.1,.025,SILVER,.195)
    for zz in [z-h/2+.065,z+h/2-.065]:wallbox(m,side,u,zz,w-.1,.035,.025,SILVER,.195)
    m.finish(.013)
    g=Mesh(name+'_山形印刷',7,1)
    for du,ht in [(-.26,.28),(0,.43),(.27,.24)]:
        mid=u+du*w;base=z-.05*h;peak=z+ht*h
        pts=[point(side,mid-w*.24,base,.201),point(side,mid,peak,.201),point(side,mid+w*.23,base,.201)]
        g.face(pts,RED)
        g.face([point(side,mid-w*.18,base,.204),point(side,mid,peak-.19*h,.204),point(side,mid+w*.17,base,.204)],(7,3))
    for du,col in [(-.26,CYAN),(.27,(7,1))]:
        g.face([point(side,u+du*w+math.cos(a*math.pi/16)*w*.058,z+h*.36+math.sin(a*math.pi/16)*w*.058,.205) for a in range(32)],col)
    g.finish()
    label(name+'_标题',title,point(side,u,z-h*.29,.207),w*.106,side,WHITE)
    label(name+'_副标题','TOGETHER' if title=='WORK' else 'BEYOND',point(side,u,z-h*.40,.207),w*.084,side,ORANGE)
poster('主墙山形海报','front',38.15,-3.05,3.05,5.1,'WORK')
poster('侧墙探索海报','right',13.4,-3.0,2.7,4.5,'EXPLORE')
sign=Mesh('主墙_导向牌细框',7);wallbox(sign,'front',42.5,-4.1,2.12,1.45,.1,DARK,.12);sign.finish(.045)
label('主墙导向牌标题','HUGE CAMP',point('front',42.5,-3.9,.19),.23,'front')
label('主墙导向箭头','<<',point('front',42.5,-4.48,.19),.45,'front',ORANGE)
for side,u,z,level in [('right',6.2,-3.8,'02'),('front',42.5,-16.0,'01')]:
    label(f'墙面_{side}_楼层标题','LEVEL',point(side,u,z+1.15,.075),.51,side,(9,3))
    label(f'墙面_{side}_楼层编号',level,point(side,u,z-.05,.076),1.95,side,(9,7))
    label(f'墙面_{side}_楼层箭头','>>>',point(side,u,z-1.3,.077),.65,side,(9,3))
# Surface mounted fixtures and actual light sources share locations.
def lightbar(name,side,u,z,length,warm=False):
    m=Mesh(name+'_灯座与护罩',6);wallbox(m,side,u,z,length,.35,.20,DARK,.22)
    for du in [-length/2+.1,length/2-.1]:wallbox(m,side,u+du,z,.14,.43,.26,EDGE,.27)
    m.finish(.026)
    e=Mesh(name+'_灯芯_UI灯光',6,3);wallbox(e,side,u,z,length-.35,.15,.07,ORANGE if warm else WHITE,.355);e.finish(.025)
    data=bpy.data.lights.new(name+'_实光','AREA');data.energy=160 if warm else 250;data.color=(1,.30,.07) if warm else (.28,.56,1);data.shape='RECTANGLE';data.size=length;data.size_y=.5
    ob=bpy.data.objects.new(name+'_实光',data);bpy.context.scene.collection.objects.link(ob);ob.location=point(side,u,z,.48)
    target=Vector(point(side,u,z-1.4,2.5));ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
lightbar('主墙蓝白荧光灯','front',38.15,.65,3.05)
lightbar('右墙长条壁灯','right',13.4,.40,4.1)
lightbar('下层门楣暖光','front',42.5,-13.75,1.7,True)
# Step accent accessories only: visible treads and rails remain exactly locked.
for j in range(2):
    e=Mesh(f'楼梯_{j}_侧边暖色定位_UI灯光',4,3)
    m=Mesh(f'楼梯_{j}_止滑条与角标',4,1)
    for k in range(20):
        x=44.0 if j==0 else 36.0;y=3.29+.75*k if j==0 else 17.29-.75*k;z=-9.05-.3*k if j==0 else -15.05-.3*k
        for xx in [x-1.88,x+1.88]:
            m.face([(xx,y,z+.023),(xx+.13,y,z+.023),(xx+.13,y+.13,z+.023)],ORANGE)
            if k%4==0:e.box((xx,y,z+.01),(.10,.2,.05),ORANGE)
        m.box((x,y+.12,z+.005),(3.45,.036,.007),(9,3))
    e.finish();m.finish()
# Soft neutral overhead illumination; keep blue/orange emphasis local to fixtures.
for o in bpy.context.scene.objects:
    if o.type=='LIGHT' and not o.name.endswith('_实光'):
        if o.data.type=='POINT':o.data.energy=180;o.data.shadow_soft_size=1.4
        elif o.name=='主冷光_顶部':o.data.color=(.70,.80,1);o.data.energy=6000;o.data.size=16
        else:o.data.energy=1400;o.data.color=(.45,.63,1);o.data.size=10
s=bpy.context.scene;s.view_settings.look='AgX - Medium High Contrast';s.world.color=(.12,.12,.12)
bpy.context.view_layer.update()
after={n:sig(bpy.data.objects[n]) for n in locked}
aftergeo={n:sig(bpy.data.objects[n],False) for n in structural}
assert after==locked,'Locked object changed'
assert aftergeo==structural,'Structural geometry changed'
(ROOT/'qa'/'build_result.json').write_text(json.dumps({'locked_count':len(locked),'structural_count':len(structural),'locked_match':after==locked,'structural_match':aftergeo==structural,'replaced_accessories':removed,'counts':{c.name:len(c.objects) for c in C.values()}},ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'env_tower_stairwell_art_source_v020.blend'),compress=True)
print('V020_BUILD_OK',len(locked),{i:len(c.objects) for i,c in C.items()})
