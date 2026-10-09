import bpy,json,math,random,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from math import pi,sin,cos
R=Path(__file__).resolve().parents[2];O=R/'assets/art/environments/master_office_3d/source/env_block00_story_rooms/v001';P=json.loads((O/'component_plan.json').read_text(encoding='utf8'))
assert P['component_plan_frozen'];random.seed(981234)
bpy.ops.wm.read_factory_settings(use_empty=True);S=bpy.context.scene;S.name='98F_四房美术总览';S.unit_settings.system='METRIC'
def coll(n,parent=None):
 c=bpy.data.collections.new(n);(parent or S.collection).children.link(c);return c
root=coll('98F剧情房间_中文资产管理');src=coll('01_制作组件',root);out=coll('02_游戏输出_实例布局',root);stage=coll('90_展示与验收',root)
office_path=R/P['source_office'];oc=json.loads((office_path.parent/'component_catalog.json').read_text(encoding='utf8'))
with bpy.data.libraries.load(str(office_path),link=True) as (a,b):b.collections=[d['collection'] for d in oc]
masters={d['slug']:bpy.data.collections[d['collection']] for d in oc}
assert all(tuple(c.instance_offset)==(0,0,0) for c in masters.values())
names=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'];mats=[bpy.data.materials[n] for n in names]
palette=next(n.image for n in mats[0].node_tree.nodes if n.type=='TEX_IMAGE');pixels=list(palette.pixels)
def nearest(rgb):
 candidates=[]
 for row in range(10):
  for col in range(9):
   k=(int((9-row+.5)*51.2)*512+int((col+.5)*51.2))*4;candidates.append((sum((pixels[k+i]-rgb[i])**2 for i in range(3)),(col,row)))
 return min(candidates)[1]
colors={'steel':(9,3),'dark':(9,1),'slate':(9,4),'concrete':(9,5),'silver':(9,7),'fabric':(9,8),'paper':(9,9),'blue':(9,2),'cyan':nearest((.48,.78,.95)),'gold':nearest((.46,.33,.14)),'leaf':nearest((.25,.35,.11)),'rust':nearest((.40,.18,.12))}
# Reuse only the tested geometry/UV helpers, not the prior room's construction or layout.
helper=(R/'scripts/blender/build_father_office_source.py').read_text(encoding='utf8');exec(helper[helper.index('parts={};'):helper.index('# 5 m modules')])
def hardbox(n,p,sz,mat=0,color='steel',rot=None):return box(n,p,sz,mat,color,0,rot)
def beam(n,a,b,width,depth,color='steel'):
 a=Vector(a);b=Vector(b);o=hardbox(n,(a+b)*.5,(width,depth,(b-a).length),0,color);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def prism(n,poly,depth,y=0,mat=0,color='steel'):
 count=len(poly);vs=[(x,y+dy,z) for dy in [-depth/2,depth/2] for x,z in poly]
 fs=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
 return objmesh(n,vs,fs,mat=mat,color=color)
def pedestal():
 hardbox('宽阶基座',(0,0,.16),(3.8,2.6,.32),1,'slate');hardbox('收分台座',(0,0,.47),(3.35,2.25,.30),0,'dark');hardbox('纪念碑座',(0,0,.85),(2.9,1.95,.46),1,'concrete')
 hardbox('铭牌',(0,-1.0,.86),(1.20,.035,.25),0,'gold')
 for x in [-1.4,1.4]:
  for y in [-.9,.9]:cyl('锚定铆栓',(x,y,.66),.09,.12,0,'silver',6)
def gear(radius=1.4,center=(0,0,3.4)):
 cx,cy,cz=center;n=48;vs=[]
 for yy in [-.16,.16]:
  for inside in [False,True]:
   for i in range(n):
    a=2*pi*i/n;rr=radius*.57 if inside else radius*(1 if i%4 in [0,1] else .88);vs.append((cx+rr*cos(a),cy+yy,cz+rr*sin(a)))
 fs=[]
 for i in range(n):
  j=(i+1)%n;fs.extend([(i,j,j+n,i+n),(i+2*n,i+3*n,j+3*n,j+2*n),(i,i+2*n,j+2*n,j),(i+n,j+n,j+3*n,i+3*n)])
 objmesh('十二齿工业环',vs,fs,mat=0,color='rust')
use('sculpture_foundry');pedestal()
# Monumental faceted worker and hammer: fixed sculpture, no character rig or animation.
prism('跨步支腿',[(-1.1,1.05),(-.3,1.05),(.14,3.0),(-.55,3.08)],.64,color='steel')
prism('支撑腿',[(.4,1.05),(1.12,1.05),(.62,3.1),(-.04,3.0)],.64,color='silver')
prism('棱角躯干',[(-.67,2.9),(.52,2.85),(1.05,4.38),(.26,4.85),(-.87,4.25)],.82,color='concrete')
prism('面部斜切',[(-.22,4.58),(.39,4.5),(.58,5.15),(.18,5.52),(-.29,5.25)],.57,color='silver')
beam('举起的臂',(.6,0,4.3),(1.15,0,5.17),.50,.62,'steel');beam('伸展的臂',(-.65,0,4.2),(-1.50,-.12,3.54),.50,.58,'steel')
beam('铸锤长柄',(.7,0,4.6),(1.15,0,6.1),.16,.20,'gold');hardbox('铸锤头',(1.1,0,6.05),(1.48,.76,.54),0,'rust',rot=(0,-.14,0))
prism('背后钢翼',[(-1.45,1.1),(-1.56,4.7),(-.87,3.6),(-.75,1.1)],.19,y=.75,color='rust')
use('sculpture_turbine');pedestal();gear(1.48,(0,0,3.75))
beam('对角动力梁',(-1.14,.34,1.05),(1.0,.34,5.60),.42,.52,'silver')
beam('反向动力梁',(1.2,.4,1.05),(-.95,.4,4.60),.33,.44,'steel')
prism('飞升左翼',[(-1.5,1.1),(-1.78,5.95),(-1.12,5.18),(-.67,1.1)],.35,y=.45,color='concrete')
prism('飞升右翼',[(.9,1.1),(1.65,1.1),(1.72,5.44),(1.15,4.78)],.35,y=.55,color='steel')
cyl('工业环轴心',(0,-.06,3.75),.24,.40,0,'gold',8).rotation_euler.x=pi/2
for a in [0,pi/2,pi,3*pi/2]:beam('轮辐',(0,0,3.75),(cos(a)*.85,0,3.75+sin(a)*.85),.15,.22,'steel')
use('sculpture_pylon');pedestal()
prism('倾斜纪念主峰',[(-1.35,1.05),(-.66,1.05),(.6,6.2),(-.25,5.52)],.7,color='concrete')
prism('对冲钢峰',[(.55,1.05),(1.4,1.05),(.53,5.25),(-.20,4.6)],.60,y=.14,color='steel')
prism('尖翼', [(-1.50,2.10),(-.30,2.60),(.10,5.05),(-1.68,4.0)],.20,y=-.44,color='rust')
beam('横向桁架',(-1.35,-.30,2.6),(1.3,-.30,4.2),.24,.26,'silver')
for z in [2.2,2.8,3.4,4.0]:hardbox('构造横肋',(.05,.36,z),(1.5,.30,.15),0,'dark')
use('debris_slab')
prism('尖角楼板',[(-1.3,.1),(-1.0,.35),(-.2,.48),(.45,.24),(1.23,.32),(.85,.05)],1.15,mat=1,color='concrete')
for x in [-.65,-.2,.28,.73]:tube('外露短钢筋',[(x,-.60,.22),(x+.09,-.85,.24),(x+.16,-1.03,.15)],.024,0,'rust',4)
use('debris_cluster')
for k in range(12):rock('斜碎混凝土',(random.uniform(-1.1,1.1),random.uniform(-.35,.35),random.uniform(.12,.25)),(random.uniform(.15,.62),random.uniform(.12,.40),random.uniform(.16,.45)),random.choice(['concrete','slate']))
use('cable_floor')
for j in range(4):
 pts=[(-.13+j*.065+.09*sin(t*.6+j),-1.65+t*.15,.045+.013*j) for t in range(22)]
 tube('断线绝缘层',pts,.031,1,'dark',5)
 e=Vector(pts[-1]);tube('裸露铜芯',[e,e+Vector((.04,.12,.04)),e+Vector((-.06,.23,.02))],.010,0,'gold',4)
for y in [-1,.2,.9]:hardbox('残留束线扣',(0,y,.09),(.36,.06,.055),0,'steel')
use('cable_hanging')
hardbox('破裂接线盒',(0,0,2.9),(.75,.38,.48),0,'steel')
for j in range(5):
 pts=[(-.25+j*.12,0,2.68),(-.15+j*.10,-.06,1.65),(-.33+j*.17,.10,.9),(-.22+j*.16,-.06,.10+j*.08)]
 tube('下垂绝缘线',pts,.030,1,'dark',5);e=Vector(pts[-1]);tube('断口铜丝',[e,e+Vector((.05,-.06,-.08))],.009,0,'gold',4)
use('portal_damage')
prism('破门侧边残骸',[(-.22,0),(.25,0),(.23,2.4),(.06,2.8),(-.20,2.52)],.37,mat=1,color='slate')
beam('倾斜断金属',(-.1,.18,.2),(.18,.18,2.30),.095,.14,'steel')
for z in [.4,1.2,2.1]:cyl('残留锚栓',(0,-.20,z),.056,.10,0,'gold',6).rotation_euler.x=pi/2
use('constructivist_mural')
hardbox('大型壁画底板',(0,0,3),(10,.18,6),1,'paper')
for x in [-5.08,5.08]:hardbox('壁画竖框',(x,.08,3),(.14,.25,6.28),0,'steel')
for z in [-.07,6.07]:hardbox('壁画横框',(0,.08,z),(10.30,.25,.14),0,'steel')
# Flat geometric relief: sun, factory skyline and sweeping red diagonals.
n=20;poly=[(2.3+1.5*cos(2*pi*i/n),3.8+1.5*sin(2*pi*i/n)) for i in range(n)];prism('工业红日',poly,.035,y=.119,mat=1,color='rust')
prism('红色上升斜楔',[(-4.7,.4),(-3.3,.4),(3.8,5.7),(2.2,5.7)],.04,y=.15,mat=1,color='rust')
for k in range(5):
 x=-4.6+k*1.8;h=1.05+(k%3)*.55
 prism('工厂锯齿轮廓',[(x,.35),(x+1.5,.35),(x+1.5,h+.8),(x+.85,h+.38),(x+.85,h+.85),(x,h+.4)],.05,y=.19,mat=1,color='dark')
 hardbox('厂房窗带',(x+.73,.225,.77),(1.18,.012,.09),1,'silver')
for x,h in [(-3.9,4.5),(-1.4,3.9),(.8,3.2)]:hardbox('纪念烟囱',(x,.25,h/2),(.26,.06,h),1,'steel')
for k in range(6):prism('放射线',[(-4.7,.55),(-4.7+k*1.5,5.8),(-4.55+k*1.5,5.8)],.016,y=.11,mat=1,color='silver')

# Bake nine independent masters; keep linked office masters and materials untouched.
catalog=[];triangles={}
for d in P['components']:
 slug=d['slug']
 if slug.startswith('sculpture'):
  for ob in parts[slug]:
   for mod in ob.modifiers:
    if mod.type=='BEVEL':mod.segments=1
 if slug=='debris_cluster':
  for ob in parts[slug]:
   for mod in list(ob.modifiers):
    if mod.type in ['BEVEL','WEIGHTED_NORMAL']:ob.modifiers.remove(mod)
 bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();arr=[];points=[]
 for ob in parts[slug]:
  me=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),depsgraph=deps);me.transform(ob.matrix_world);uvpaint(me,ob['color_key']);arr.append((me,int(ob['role'])));points.extend(v.co.copy() for v in me.vertices)
 lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)));anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 mc=bpy.data.collections.new('组件_'+d['name_zh']);mc.use_fake_user=True;masters[slug]=mc
 vs=[];fs=[];puvs=[];roles=[]
 for me,role in arr:
  start=len(vs);vs.extend(tuple(v.co-anchor) for v in me.vertices)
  for face in me.polygons:fs.append(tuple(start+i for i in face.vertices));puvs.append([tuple(me.uv_layers.active.data[i].uv) for i in face.loop_indices]);roles.append(role)
  bpy.data.meshes.remove(me)
 me=bpy.data.meshes.new(d['name_zh']+'_网格');me.from_pydata(vs,[],fs);me.update();uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 for m in mats[:3]:me.materials.append(m)
 for face,pu,role in zip(me.polygons,puvs,roles):
  face.material_index=role
  for li,co in zip(face.loop_indices,pu):uv.data[li].uv=co
 ob=bpy.data.objects.new(d['name_zh']+'_主体输出',me);mc.objects.link(ob);me.calc_loop_triangles();triangles[slug]=len(me.loop_triangles)
 if slug.startswith('sculpture'):assert triangles[slug]<=P['sculpture_triangle_budget_each'],(slug,triangles[slug])
 manifest={**d,'collection':mc.name,'version':'v001','source_blend':'env_block00_story_rooms_source_v001.blend','bounds_size_m':list(hi-lo),'local_origin':[0,0,0],'objects':[ob.name],'triangles':triangles[slug],'exported':False,'collision_owner':'future_godot_wrapper','block_id':'master_office','floor_range':[98,98],'asset_ledger':P['asset_ledger']}
 folder=O/'component_packages'/d['category']/slug;folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8');catalog.append(manifest)
source_layer=bpy.context.view_layer.layer_collection.children[root.name].children[src.name];source_layer.exclude=True
roomcols={r['room_id']:coll(r['name_zh']+'_'+r['room_id'],out) for r in P['rooms']}
cutcols={rid:coll('剖视隐藏墙_'+rid,c) for rid,c in roomcols.items()}
instances=[]
def place(slug,pos,room,rot=0,cut=False,euler=None):
 c=masters[slug];ob=bpy.data.objects.new(slug+'_实例',None);ob.instance_type='COLLECTION';ob.instance_collection=c;(cutcols[room] if cut else roomcols[room]).objects.link(ob);ob.location=pos;ob.rotation_euler=euler or (0,0,math.radians(rot));ob['room_id']=room;ob['slug']=slug
 instances.append(dict(instance_id=ob.name,slug=slug,component_collection=c.name,room_id=room,position_m=list(pos),rotation_euler_rad=list(ob.rotation_euler),scale=[1,1,1],cutaway_hidden=cut,source='linked_office' if slug in [d['slug'] for d in oc] else 'new_component'));return ob
oi=json.loads((office_path.parent/'component_instances.json').read_text(encoding='utf8'))['instances']
for i in oi:place(i['slug'],i['world_position_m'],'master_office',cut=i['cutaway_hidden'],euler=i['rotation_euler_rad'])
wallkeys=set()
for y in [-7.5,-2.5,2.5,7.5]:
 for x in [-40,-25]:wallkeys.add(('x',x,y))
for x in [-37.5,-32.5,-27.5]:
 for y in [-10,10]:wallkeys.add(('y',y,x))
for room in P['rooms']:
 rid=room['room_id']
 if rid=='master_office':continue
 xmin,xmax=room['bounds_x_m'];ymin,ymax=room['bounds_y_m']
 for ix in range(round((xmax-xmin)/5)):
  for iy in range(round((ymax-ymin)/5)):place('floor_fractured' if (ix+iy)%3 else 'floor_panel',(xmin+2.5+ix*5,ymin+2.5+iy*5,0),rid)
 for axis,line,centers,angle,side in [('x',xmin,[ymin+2.5+i*5 for i in range(round((ymax-ymin)/5))],-90,'west'),('x',xmax,[ymin+2.5+i*5 for i in range(round((ymax-ymin)/5))],90,'east'),('y',ymin,[xmin+2.5+i*5 for i in range(round((xmax-xmin)/5))],0,'south'),('y',ymax,[xmin+2.5+i*5 for i in range(round((xmax-xmin)/5))],180,'north')]:
  for center in centers:
   key=(axis,line,center)
   if key in wallkeys:continue
   wallkeys.add(key)
   if key==('x',20,2.5):continue
   door=axis=='x' and center==2.5 and line in [-25,15,35]
   pos=(line,center,0) if axis=='x' else (center,line,0)
   place('wall_door' if door else 'wall_panel',pos,rid,angle,cut=side in ['south','east'])
# Six monumental works on each side. The complete 6 m center lane remains empty.
for row,y,rot in [(0,-2.95,180),(1,7.95,0)]:
 for k,x in enumerate([-21.5,-15,-8.5,-2,4.5,11]):
  slug=['sculpture_foundry','sculpture_turbine','sculpture_pylon'][(k+row)%3];place(slug,(x,y,.12),'meeting_room',rot)
# Debris and wiring stay along edges, outside every passage.
for x in [-23,-16,-9,-2,5,12]:
 for y in [-4.15,9.10]:place('debris_cluster',(x,y,.12),'meeting_room',0)
for x in [-19,-6,7]:place('cable_floor',(x,9.45,.12),'meeting_room',90)
for rid,points in [('corridor',[(16.0,-8.3),(18.8,-5.8),(16.0,7.9),(19.1,8.3)]),('lobby',[(22,-3.75),(27,-3.75),(32,-3.75),(22,8.8),(27,8.8),(32,8.8)])]:
 for k,(x,y) in enumerate(points):
  place('debris_cluster',(x,y,.12),rid,90 if rid=='corridor' else 0)
  if k%2==0:place('debris_slab',(x,y,.14),rid,90 if rid=='corridor' else -10)
for xyz in [(15.7,-6.8,.12),(19.35,7.4,.12)]:place('cable_floor',xyz,'corridor')
for xyz in [(23,-4.40,.12),(29,9.3,.12),(32,-4.3,.12)]:place('cable_floor',xyz,'lobby',90)
place('cable_hanging',(15.48,-5.9,2.4),'corridor',-90)
place('cable_hanging',(34.47,7.1,2.0),'lobby',90)
# The old 5 m door wall and its leaf are absent; remnants lie beyond clear opening [0,5].
for y in [-.5,5.5]:place('portal_damage',(20,y,.12),'corridor',90)
place('cable_hanging',(20,5.75,3.1),'lobby',90)
place('debris_cluster',(20,-.92,.12),'corridor',0)
place('constructivist_mural',(27.5,9.61,3.55),'lobby',180)
for d in catalog:d['instance_count']=sum(i['slug']==d['slug'] for i in instances)
(O/'component_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf8')
(O/'linked_component_catalog.json').write_text(json.dumps(oc,ensure_ascii=False,indent=2),encoding='utf8')
(O/'component_instances.json').write_text(json.dumps({'coordinate_space':'blender_block_world','instances':instances,'door_removal':P['door_removal']},ensure_ascii=False,indent=2),encoding='utf8')
(O/'component_tree.txt').write_text('\n'.join(d['category']+'/'+d['slug']+' '+d['name_zh'] for d in catalog),encoding='utf8')
for rid in roomcols:bpy.context.view_layer.layer_collection.children[root.name].children[out.name].children[roomcols[rid].name].children[cutcols[rid].name].exclude=True
full=S.view_layers.new('完整围护_接口核对');full.use=False;full.layer_collection.children[root.name].children[src.name].exclude=True
def camera(n,loc,target,scale):
 data=bpy.data.cameras.new(n);ob=bpy.data.objects.new(n,data);stage.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale;return ob
cams={
 'overview':camera('四房全景', (34,-60,65),(-2.5,1,2.9),98),
 'meeting':camera('会议室全景', (19,-31,27),(-5,2.5,3.2),51),
 'meeting_top':camera('会议室通道俯视',(-5,2.5,50),(-5,2.5,0),44),
 'passage':camera('走廊门厅贯通', (48,-23,24),(23,2,2),32),
 'sculpture':camera('工业雕塑近景',(-10,3,9),(-15,-2.95,3),12),
 'lobby':camera('门厅壁画',(40,-14,15),(27.5,5,4),24)}
def light(n,loc,target,power,size,color):
 data=bpy.data.lights.new(n,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color;ob=bpy.data.objects.new(n,data);stage.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
for x in [-33,-18,-3,12,27]:
 light('顶柔光',(x,-4,21),(x,2,0),4300,13,(.78,.87,1));light('暖色侧光',(x,6,13),(x,0,2),1800,8,(1,.80,.62))
light('办公室破墙冷光',(-30,12,7),(-32,0,1),3000,8,(.32,.64,1))
S.world=bpy.data.worlds.new('统一冷灰环境');S.world.use_nodes=True;S.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.20,.26,1);S.world.node_tree.nodes['Background'].inputs[1].default_value=.45
S.render.engine='CYCLES';S.cycles.samples=48;S.cycles.use_denoising=True
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for device in prefs.devices:device.use=device.type!='CPU'
 if any(d.use for d in prefs.devices):S.cycles.device='GPU'
except Exception:pass
S.view_settings.view_transform='AgX';S.render.image_settings.file_format='PNG';S.camera=cams['overview'];S.render.resolution_x=1800;S.render.resolution_y=850;S.render.resolution_percentage=100
S['asset_id']=P['asset_id'];S['block_id']='master_office';S['floor_number']=98;S['source_only']=True;S['removed_door_wall']='x=20 y=[0,5]';S['meeting_clear_width_m']=6
note=bpy.data.texts.new('使用说明');note.write('四房总源，办公室24种组件外链既有v002。会议室南北各6尊低面工业雕塑，中间6m无障碍。第三第四间门墙和门扇已在本美术源拆除，开放5m。正式Godot场景尚未改变。切换完整围护视图层检查所有墙体。')
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(O/'env_block00_story_rooms_source_v001.blend'))
print('STORY_BUILD_OK',len(instances),'SCULPTURE_TRIANGLES',triangles,flush=True)
layer=bpy.context.view_layer
for key,cam in cams.items():
 S.camera=cam
 for rid,col in roomcols.items():
  hidden=(key in ['meeting','meeting_top','sculpture'] and rid!='meeting_room') or (key=='passage' and rid not in ['corridor','lobby']) or (key=='lobby' and rid!='lobby')
  layer.layer_collection.children[root.name].children[out.name].children[col.name].exclude=hidden
  layer.layer_collection.children[root.name].children[out.name].children[col.name].children[cutcols[rid].name].exclude=True
 S.render.resolution_x=1800 if key=='overview' else 1500;S.render.resolution_y=850 if key in ['overview','meeting','meeting_top'] else 1100
 S.render.filepath=str(O/('preview_'+key+'.png'));bpy.ops.render.render(write_still=True)
print('STORY_RENDERS_OK',flush=True)
