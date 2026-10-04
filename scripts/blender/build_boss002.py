"""Boss002 source-only authoring. Run with Blender 4.5 --background --factory-startup."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
from math import sin,cos,pi
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/enemies/bosses/enm_boss_monitor002'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name!='Collection':bpy.data.collections.remove(c)
master=bpy.data.collections.get('Collection'); master.name='BOSS002_MONITOR'
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
groups={}
for name in ['01_MONITOR','02_FACE','03_ARMS','04_GLOVES','05_KEYBOARD','06_CABLE','07_STAND']:
    c=bpy.data.collections.new(name);master.children.link(c)
    sub=bpy.data.collections.new(name+'_default');c.children.link(sub);groups[name]=sub
current='01_MONITOR'
def put(o,name,mat=None):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    groups[current].objects.link(o)
    if mat:o.data.materials.append(mat)
    o['slot_id']=current;o['variant_id']='default'
    return o
def material(name,col,metal=0,rough=.4,emission=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if emission:p.inputs['Emission Color'].default_value=(*col,1);p.inputs['Emission Strength'].default_value=emission
    return m
def flat(name,col):
    m=material(name,col);n=m.node_tree.nodes;n.clear();a=n.new('ShaderNodeEmission');a.inputs[0].default_value=(*col,1);a.inputs[1].default_value=.85;o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(a.outputs[0],o.inputs[0]);return m
silver=material('Brushed titanium',(.39,.43,.52),.72,.3)
edge=material('Edge bright alloy',(.66,.7,.79),.7,.27)
dark=material('Graphite housing',(.035,.042,.058),.35,.38)
black=material('Rubber cables',(.009,.014,.018),.12,.29)
screen=material('Deep green glass',(.002,.012,.001),.1,.24)
green=material('Phosphor code',(.17,.8,.004),0,.4,1.35)
dim=material('Dim phosphor',(.028,.14,.004),0,.5,.6)
scanmat=material('Subtle raster',(.004,.025,.002),0,.6,.2)
white=material('Warm ivory gloves',(.89,.87,.81),0,.52)
cuffmat=material('Glove cuff shadow',(.36,.35,.41),0,.55)
ink=flat('Face ink',(.004,.005,.006));paper=flat('Face ivory',(.96,.94,.88));pink=flat('Face pale lilac',(.69,.51,.7));red=flat('Vermilion lips',(.95,.032,.055));redlight=flat('Lip highlight', (1,.16,.17))
def cube(n,loc,scale,m,bev=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=put(bpy.context.object,n,m);o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bev:
        b=o.modifiers.new('Soft manufactured edges','BEVEL');b.width=bev;b.segments=3
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o
def sphere(n,loc,scale,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=loc);o=put(bpy.context.object,n,m);o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for p in o.data.polygons:p.use_smooth=True
    return o
def tube(n,points,r,m,cyclic=False):
    cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';cu.resolution_u=2;cu.bevel_depth=r;cu.bevel_resolution=3
    s=cu.splines.new('POLY');s.points.add(len(points)-1)
    for a,p in zip(s.points,points):a.co=(*p,1)
    s.use_cyclic_u=cyclic;o=bpy.data.objects.new(n,cu);groups[current].objects.link(o);o.data.materials.append(m);return o
def bezier(n,points,r,m):
    cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';cu.resolution_u=18;cu.bevel_depth=r;cu.bevel_resolution=4
    s=cu.splines.new('BEZIER');s.bezier_points.add(len(points)-1)
    for a,p in zip(s.bezier_points,points):a.co=p;a.handle_left_type='AUTO';a.handle_right_type='AUTO'
    o=bpy.data.objects.new(n,cu);groups[current].objects.link(o);o.data.materials.append(m);return o
def cyl(n,loc,r,depth,m,axis='Z',vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc);o=put(bpy.context.object,n,m)
    if axis=='X':o.rotation_euler[1]=pi/2
    if axis=='Y':o.rotation_euler[0]=pi/2
    b=o.modifiers.new('Rim bevel','BEVEL');b.width=.014;b.segments=3;o.modifiers.new('Normals','WEIGHTED_NORMAL');return o
def txt(n,text,loc,size,m):
    cu=bpy.data.curves.new(n,'FONT');cu.body=text;cu.size=size;cu.extrude=0;cu.space_character=1.05
    o=bpy.data.objects.new(n,cu);groups[current].objects.link(o);o.location=loc;o.rotation_euler=(pi/2,0,0);cu.materials.append(m);return o
# Portrait chassis: no image of a model pasted onto a plane.
cube('Rear shell',(0,.10,2.02),(1.63,.27,2.66),dark,.075)
cube('Metal chassis',(0,-.025,2.02),(1.68,.16,2.72),silver,.055)
cube('Black screen gasket',(0,-.12,2.04),(1.47,.045,2.48),black,.035)
cube('Portrait display',(0,-.148,2.045),(1.37,.02,2.36),screen,.012)
for x in [-.797,.797]:cube('Vertical silver bezel',(x,-.165,2.02),(.075,.09,2.61),edge,.018)
for z in [.707,3.337]:cube('Horizontal silver bezel',(0,-.161,z),(1.64,.085,.09),edge,.018)
cube('Power switch',(0,-.217,.718),(.23,.016,.036),dark,.009)
sphere('Status LED',(.17,-.227,.72),(.013,.006,.009),green)
for x in [-.76,.76]:
    for z in [.76,3.28]:
        cyl('Bezel screw',(x,-.22,z),.018,.012,dark,'Y',16)
        cube('Screw slot',(x,-.229,z),(.023,.004,.003),silver,0)
lines=['// MONITOR.EXE','boot.sys(002);','load(kernel);','void awaken() {','  scan(player);','  eat(data);','  spawn(face);','  corrupt();','  for (;;) {','    trace(input);','    steal(keys);','    pulse(0x02);','    rewrite(ai);','    break_wall();','  }','  access(ROOT);','  return chaos;','}','> compiling...','> boss_online','> _']
for i,line in enumerate(lines):
    z=3.14-i*.104
    txt('CODE_%02d'%i,line,(-.624,-.17,z),.077,green if i%4 else dim)
for i in range(48):
    z=.89+i*.046;cube('CRT scanline',(0,-.163,z),(1.32,.001,.001),scanmat,0)
cube('Typing cursor',(.28,-.177,1.04),(.055,.003,.093),green,0)
# Rear housing, inset access doors, vents, VESA fasteners and I/O bank.
cube('Rear inset cover',(0,.263,2.22),(1.24,.085,1.83),dark,.085)
cube('Service hatch',(0,.324,2.18),(.88,.04,.85),silver,.045)
cube('Service hatch insert',(0,.35,2.18),(.81,.015,.78),dark,.025)
for x in [-.35,.35]:
    for z in [1.87,2.49]:cyl('VESA screw',(x,.373,z),.027,.022,silver,'Y')
for x in [-.52,.52]:
    for j in range(15):cube('Rear cooling slot',(x,.317,2.72-j*.073),(.085,.016,.026),black,.006)
for i in range(5):cube('Top cooling vent',(-.40+i*.2,.25,3.20),(.12,.032,.048),black,.007)
for i in range(3):
    cube('IO socket bezel',(-.825,.09,1.24+i*.19),(.025,.15,.10),edge,.007)
    cube('IO socket hollow',(-.841,.08,1.24+i*.19),(.008,.115,.068),black,.003)
    cube('IO contact',(-.848,.06,1.24+i*.19),(.01,.05,.02),green,.002)
current='07_STAND'
cyl('Portrait rotation hinge',(0,.34,.88),.19,.24,dark,'Y')
cyl('Hinge cap',(0,.48,.88),.137,.025,silver,'Y')
cyl('Stand column',(0,.08,.48),.095,.62,silver)
cyl('Stand boot',(0,.08,.22),.155,.18,black)
cyl('Stand boot trim',(0,.08,.18),.186,.045,edge)
# Extruded crescent pedestal.
outline=[(-.9,-.36),(-.85,.15),(-.63,.39),(-.27,.5),(.27,.5),(.63,.39),(.85,.15),(.9,-.36),(.60,-.30),(.38,-.19),(-.38,-.19),(-.60,-.30)]
verts=[(x,y,z) for z in [.035,.16] for x,y in outline];N=len(outline);faces=[tuple(range(N-1,-1,-1)),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
me=bpy.data.meshes.new('Pedestal mesh');me.from_pydata(verts,[],faces);me.update();ob=bpy.data.objects.new('Crescent pedestal',me);groups[current].objects.link(ob);me.materials.append(silver)
b=ob.modifiers.new('Rounded pedestal edges','BEVEL');b.width=.045;b.segments=3;ob.modifiers.new('Normals','WEIGHTED_NORMAL')
for x in [-.68,.68]:cube('Rubber foot',(x,-.06,.03),(.29,.35,.05),black,.02)
current='03_ARMS'
for sign in [-1,1]:
    side='L' if sign<0 else 'R'
    cyl('Rear arm grommet '+side,(sign*.62,.28,2.01),.20,.18,black,'Y')
    bezier('Behind monitor cable '+side,[(sign*.62,.32,2.01),(sign*.84,.38,2.01),(sign*.91,.08,2.01)],.074,black)
    pts=[]
    for j in range(521):
        t=j/520;ang=t*2*pi*7.5
        rad=.18*min(1,t/.065,(1-t)/.065)
        pts.append((sign*(.91+t*1.21),.08+rad*sin(ang),2.01+rad*cos(ang)))
    tube('Continuous spring cable '+side,pts,.062,black)
    cyl('Metal wrist ferrule '+side,(sign*2.16,.08,2.01),.155,.12,silver,'X')
    cyl('Wrist sleeve '+side,(sign*2.23,.08,2.01),.17,.14,cuffmat,'X')
    current='04_GLOVES'
    cyl('White cuff '+side,(sign*2.28,.08,2.01),.19,.16,white,'X')
    # Connected, remeshed sculpted mitten with four separate knuckle lobes.
    parts=[]
    parts.append(sphere('Palm '+side,(sign*2.53,.035,1.99),(.28,.18,.22),white))
    for j in range(4):
        x=sign*(2.37+j*.115)
        parts.append(sphere('Knuckle '+side,(x,-.09,1.84),(.073,.15,.13+(j==1)*.014),white))
        parts.append(sphere('Curl '+side,(x,.045,1.78),(.072,.115,.068),white))
    parts.append(sphere('Thumb base '+side,(sign*2.34,-.085,1.99),(.12,.16,.13),white))
    parts.append(sphere('Thumb tip '+side,(sign*2.38,-.205,1.9),(.10,.08,.13),white))
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();hand=bpy.context.object;hand.name='Sculpted glove '+side
    rem=hand.modifiers.new('Weld glove sculpt','REMESH');rem.mode='VOXEL';rem.voxel_size=.018;rem.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=rem.name)
    sm=hand.modifiers.new('Soften cloth','SMOOTH');sm.factor=.8;sm.iterations=4;bpy.ops.object.modifier_apply(modifier=sm.name)
    sub=hand.modifiers.new('Glove surface','SUBSURF');sub.levels=1
    for j in range(3):
        x=sign*(2.43+j*.115)
        bezier('Glove stitch '+side,[(x,-.145,2.13),(x+sign*.017,-.154,2.07),(x+sign*.015,-.158,2.02)],.006,cuffmat)
    current='03_ARMS'
current='05_KEYBOARD'
cube('Keyboard outer shell',(-2.56,.045,1.23),(.77,.14,1.22),silver,.065)
cube('Keyboard deck',(-2.56,-.035,1.23),(.70,.035,1.15),black,.032)
for row in range(12):
    for col in range(5):
        x=-2.83+col*.132;z=.75+row*.084
        cube('KEY_%02d_%02d'%(row,col),(x,-.069,z),(.111,.047,.066),green if col==4 and row in [1,4,8] else dark,.01)
        if col<4:txt('Key legend',str((row*5+col)%10),(x-.019,-.098,z-.016),.034,edge)
cube('Space bar',(-2.57,-.07,.682),(.4,.045,.05),dark,.008)
for i in range(3):sphere('Keyboard LED',(-2.73+i*.105,-.074,1.772),(.012,.006,.007),green)
current='06_CABLE'
bezier('Long data cable whip',[(2.52,.02,1.96),(2.59,-.015,1.46),(2.2,-.01,.76),(2.15,-.1,.22),(2.61,-.27,.10),(3.1,-.17,.19),(3.18,.035,.34),(2.86,.17,.39),(2.60,.06,.19),(2.93,-.11,.10),(3.40,.015,.39),(3.5,.08,.96)],.048,black)
cube('Cable strain relief',(3.5,.08,1.015),(.10,.11,.24),black,.023)
for z in [.96,1.005,1.05]:cube('Relief rib',(3.5,.08,z),(.13,.13,.018),dark,.006)
cube('Data connector body',(3.5,.08,1.22),(.22,.17,.27),dark,.025)
cube('Connector alloy collar',(3.5,.08,1.36),(.205,.15,.055),edge,.008)
cube('Luminous data plug',(3.5,.08,1.43),(.147,.11,.13),green,.013)
cube('Connector front inset',(3.5,-.011,1.24),(.13,.012,.14),black,.004)
for i in range(3):cube('Plug contact',(3.451+i*.048,-.003,1.455),(.014,.01,.066),edge,.002)
# Face pieces: every surface is mathematically planar; outlines are planar ribbons.
current='02_FACE'
def poly(n,points,y,m):
    me=bpy.data.meshes.new(n);me.from_pydata([(x,y,z) for x,z in points],[],[tuple(range(len(points)))]);me.update();o=bpy.data.objects.new(n,me);groups[current].objects.link(o);me.materials.append(m);o['face_flat']=True;return o
def catmull(points,steps=8):
    out=[];N=len(points)
    for i in range(N):
        a,b,c,d=[Vector(points[k%N]) for k in [i-1,i,i+1,i+2]]
        for j in range(steps):
            t=j/steps;v=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t);out.append(tuple(v))
    return out
def stroke(n,pts,y,width,m,closed=False):
    vs=[];N=len(pts)
    for i,p in enumerate(pts):
        a=Vector(pts[(i-1)%N if closed else max(0,i-1)]);b=Vector(pts[(i+1)%N if closed else min(N-1,i+1)]);d=(b-a).normalized();off=Vector((-d.y,d.x))*width/2
        for q in [Vector(p)+off,Vector(p)-off]:vs.append((q.x,y,q.y))
    fs=[(2*i,2*i+1,2*((i+1)%N)+1,2*((i+1)%N)) for i in range(N if closed else N-1)]
    me=bpy.data.meshes.new(n);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(n,me);groups[current].objects.link(o);me.materials.append(m);o['face_flat']=True;return o
def shape(n,points,y,m,w=.022):
    p=catmull(points);poly(n,p,y,m);stroke(n+' ink outline',p,y-.001,w,ink,True);return p
shape('Large asymmetric eye',[(-1.01,2.77),(-.91,3.12),(-.67,3.38),(-.46,3.4),(-.23,3.20),(-.15,2.89),(-.57,2.75)],-.45,paper,.026)
shape('Cubist pupil',[(-.63,2.77),(-.72,2.99),(-.63,3.24),(-.50,3.37),(-.45,3.12),(-.49,2.87)],-.453,ink,.01)
for i in range(14):
    z=2.82+i*.036
    stroke('Pupil hand ink hatch',[(-.66+.09*((z-3.06)/.3)**2,z),(-.475,z+.05)],-.456,.01,paper)
cx=.69;cz=2.85
shape('Round floating eye',[(cx+.295*cos(t*2*pi/48),cz+.31*sin(t*2*pi/48)) for t in range(48)],-.46,paper,.025)
stroke('Lilac eye underside',[(cx+.258*cos(t),cz+.27*sin(t)) for t in [pi+v*pi/45 for v in range(46)]],-.463,.028,pink)
shape('Round pupil',[(cx+.09+.111*cos(t*2*pi/32),cz+.04+.123*sin(t*2*pi/32)) for t in range(32)],-.468,ink,.008)
poly('Pupil catch light',[(cx+.052+.023*cos(t*2*pi/20),cz+.097+.027*sin(t*2*pi/20)) for t in range(20)],-.47,paper)
for j in range(3):
    a=.15+j*.34;start=(cx+.29*cos(a),cz+.30*sin(a));end=(cx+.43*cos(a),cz+.44*sin(a));stroke('Flat eyelash',[start,end],-.464,.025,ink)
lip=[(-.55,2.22),(-.23,2.30),(.02,2.34),(.20,2.18),(.47,2.21),(.69,2.01),(.84,1.91),(.46,1.76),(.20,1.75),(-.11,1.87)]
shape('Floating vermilion lips',lip,-.50,red,.03)
# Open smooth mouth seam avoiding closed Catmull wrap.
stroke('Mouth seam',[(-.54,2.21),(-.23,2.13),(.03,2.06),(.18,1.99),(.34,2.025),(.58,1.97),(.83,1.91)],-.507,.023,ink)
stroke('Upper lip flat shine',[(-.20,2.285),(.0,2.311),(.16,2.165)],-.506,.016,redlight)
# Rotate authored front -Y to the project +Y convention; apply to data.
from mathutils import Matrix
rot=Matrix.Rotation(pi,4,'Z')
for o in list(master.all_objects):o.matrix_world=rot@o.matrix_world
bpy.ops.object.select_all(action='DESELECT')
for o in master.all_objects:o.select_set(o.type!='FONT')
bpy.context.view_layer.objects.active=next(o for o in master.all_objects if o.type=='MESH')
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
scene['asset_id']='ENM-BOSS-MONITOR002-3D';scene['boss_number']='002';scene['stage']='authored_unrigged';scene['forward']='+Y';scene['user_scope']='T Pose, no armature, no animation, source only'
scene['runtime_consumer']='Future BossContentCatalog -> Enemy3D; not integrated'
scene.render.engine='CYCLES';scene.cycles.samples=32
scene.world.color=(.18,.18,.18)
# A separate scene holds studio objects; the authoring scene only holds the asset.
scene.name='BOSS002_SOURCE_TPOSE'
source_scene=scene
preview=bpy.data.scenes.new('BOSS002_STUDIO');preview.collection.children.link(master)
bpy.context.window.scene=preview;scene=preview
studio=bpy.data.collections.new('STUDIO_NOT_ASSET');scene.collection.children.link(studio)
groups['STUDIO']=studio;current='STUDIO'
floor=material('Studio matte',(.035,.055,.072),0,.65)
cube('Studio floor',(0,0,-.08),(200,200,.12),floor,.01)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
def area(n,loc,power,col,size):
    d=bpy.data.lights.new(n,'AREA');d.energy=power;d.color=col;d.shape='DISK';d.size=size;o=bpy.data.objects.new(n,d);studio.objects.link(o);o.location=loc;aim(o,(0,0,1.5))
area('Large warm key',(-3,5,7),1000,(1,.86,.70),5)
area('Cool soft fill',(4,3,4),750,(.62,.78,1),4)
area('Lime rim',(1,-4,5),1250,(.69,1,.45),3)
scene.world=bpy.data.worlds.new('Studio world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.075,.11,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
d=bpy.data.cameras.new('Presentation camera');cam=bpy.data.objects.new('Presentation camera',d);studio.objects.link(cam);scene.camera=cam;d.type='ORTHO';d.lens=55
scene.render.engine='CYCLES';scene.cycles.samples=32
scene.render.resolution_x=1500;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
def camera(loc,scale,target=(-.3,0,1.72)):
    cam.location=loc;aim(cam,target);d.ortho_scale=scale
camera((4,10,5),7.6)
# Save opening on clean model view, with a separate render scene available.
bpy.context.window.scene=source_scene
for screen_ui in bpy.data.screens:
    for ar in screen_ui.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.region_3d.view_distance=7.5;ar.spaces.active.region_3d.view_location=(0,0,1.7);ar.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();ar.spaces.active.shading.type='MATERIAL'
bpy.ops.object.select_all(action='DESELECT')
source=BASE/'source/enm_boss_monitor002_source_v001.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.context.window.scene=preview
for name,loc,scale in [('overview',(3.5,11,4.8),7.4),('front',(-.3,12,1.72),7.4),('back',(3,-11,4.5),7.4),('side',(12,0,2.8),5.0)]:
    bpy.data.objects['Studio floor'].hide_render=name=='front'
    camera(loc,scale);scene.render.filepath=str(BASE/'previews'/f'{name}.png');bpy.ops.render.render(write_still=True)
print('BOSS002_SOURCE_SAVED',source)
