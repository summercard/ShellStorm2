"""Eight reference props: editable source, shared scene materials, no runtime export."""
import bpy, math, json, sys, hashlib, os, shutil, time
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
OUT=work_path('items_reference_20261014/build.json').parent
PAL=ROOT/'assets/art/shared/palette/item_high_visibility_palette_10x10_512.png'
TEMPLATE=ROOT/'art_source/items_weapons/_templates/prp/prp_template_source_v001.blend'
ROLES=['01_精工金属_道具骨架','02_细腻哑光_道具大面','03_清漆反光_道具点缀','04_柔和自发光_道具UI']
COLS=['01_制作组件_已统一材质','02_游戏输出_整合模型','10_骨骼与动画','80_挂点_交互接口','90_展示环境_灯光相机']
# Zero based palette column,row. Exactly the existing palette; no new texture.
C={'blue':(4,6),'purple':(5,7),'pink':(6,8),'pink_light':(8,8),'gold':(7,3),'silver':(9,9),'steel':(9,7),'dark':(9,0),'black':(9,0),'cyan':(7,5),'white':(9,9)}
SPECS=[
 ('battery_large','大型电池','item_battery_l','ITM-CONSUMABLE-ITEM-BATTERY-L','props','consumable',2,.66),
 ('battery_small','小型电池','item_battery_s','ITM-CONSUMABLE-ITEM-BATTERY-S','props','consumable',2,.66),
 ('health_potion','治疗药水','item_health_potion','ITM-CONSUMABLE-ITEM-HEALTH-POTION','props','consumable',2,.82),
 ('bullet_standard','标准子弹模块','mod_bullet_standard','WPN-BUL-MOD-BULLET-STANDARD','weapons','bullet_module',2,.94),
 ('big_mag','肉质弹匣','attach_big_mag','WPN-ATT-ATTACH-BIG-MAG','weapons','attachment',2,.24),
 ('triple_muzzle','三叉枪口','attach_triple_muzzle','WPN-ATT-ATTACH-TRIPLE-MUZZLE','weapons','attachment',1,.16),
 ('rubber_stock','橡皮枪托','attach_rubber_stock','WPN-ATT-ATTACH-RUBBER-STOCK','weapons','attachment',1,.32),
 ('scope','放大镜瞄具','attach_scope','WPN-ATT-ATTACH-SCOPE','weapons','attachment',1,.28),
]
def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def uv_assign(obj,role,color):
 m=obj.data;m.materials.clear();m.materials.append(bpy.data.materials[ROLES[role]])
 for u in list(m.uv_layers):m.uv_layers.remove(u)
 u=m.uv_layers.new(name='PaletteUV');u.active_render=True
 col,row=C[color];cx=(col+.5)/10;cy=1-(row+.5)/10
 for p in m.polygons:
  for k,li in enumerate(p.loop_indices):
   a=2*math.pi*k/len(p.loop_indices);u.data[li].uv=(cx+.023*math.cos(a),cy+.023*math.sin(a))
 return obj
def finish(obj,name,role,color,bevel=0):
 obj.name=NAME+'_制作组件_'+name
 for c in list(obj.users_collection):c.objects.unlink(obj)
 COMPONENTS.objects.link(obj)
 bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=obj.modifiers.new('可编辑倒角','BEVEL');b.width=bevel;b.segments=3
  b.limit_method='ANGLE'
  obj.modifiers.new('面加权法线','WEIGHTED_NORMAL')
 for p in obj.data.polygons:p.use_smooth=True
 uv_assign(obj,role,color);obj.select_set(False)
 return obj
def box(name,p,size,role,color,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=size
 return finish(o,name,role,color,bevel)
def lathe(name,profile,role,color,axis='z',p=(0,0,0),n=48,caps=True):
 vs=[];fs=[]
 for z,r in profile:
  for i in range(n):
   a=2*math.pi*i/n;v=(r*math.cos(a),r*math.sin(a),z)
   if axis=='y':v=(v[0],v[2],-v[1])
   elif axis=='x':v=(v[2],v[0],v[1])
   vs.append(tuple(v[j]+p[j] for j in range(3)))
 for k in range(len(profile)-1):
  for i in range(n):fs.append((k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i))
 if caps:fs+=[tuple(reversed(range(n))),tuple(range((len(profile)-1)*n,len(profile)*n))]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(vs,[],fs);mesh.update()
 o=bpy.data.objects.new(name,mesh);COMPONENTS.objects.link(o)
 return finish(o,name,role,color)
def cyl(name,p,r,h,role,color,axis='z',bevel=.009):
 return lathe(name,[(-h/2,r-bevel),(-h/2+bevel,r),(h/2-bevel,r),(h/2,r-bevel)],role,color,axis,p,caps=True)
def tube(name,p,r,inner,h,role,color,axis='y'):
 e=min(.012,h*.12,(r-inner)*.3)
 return lathe(name,[(-h/2,inner),(-h/2,r-e),(-h/2+e,r),(h/2-e,r),(h/2,r-e),(h/2,inner),(-h/2,inner)],role,color,axis,p,caps=False)
def path(name,pts,r,role,color):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=16;c.bevel_depth=r;c.bevel_resolution=3
 sp=c.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for b,p in zip(sp.bezier_points,pts):b.co=p;b.handle_left_type='AUTO';b.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,c);COMPONENTS.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,name,role,color)
def bolt(name,p,axis='y',r=.014):
 cyl(name,p,r,.009,0,'steel',axis,bevel=.002)
def plate(name,points,thickness,role,color,axis='x'):
 vs=[]
 for side in [-1,1]:
  for a,b in points:vs.append((side*thickness/2,a,b) if axis=='x' else (a,side*thickness/2,b))
 n=len(points);fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]
 fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 m=bpy.data.meshes.new(name);m.from_pydata(vs,[],fs);m.update();o=bpy.data.objects.new(name,m);COMPONENTS.objects.link(o)
 return finish(o,name,role,color,.015)
def battery_large():
 lathe('主蓝色圆筒',[(.07,.23),(.11,.28),(.70,.28),(.76,.255)],1,'blue')
 for z,r,h in [(.065,.265,.07),(.12,.28,.07),(.73,.28,.07),(.86,.235,.09)]:cyl('银色护圈',(0,0,z),r,h,0,'silver')
 lathe('收肩金属罩',[(.75,.27),(.81,.25),(.87,.205)],0,'silver')
 cyl('底部橡胶脚',(0,0,.018),.235,.036,1,'dark')
 cyl('金色腰圈',(0,0,.67),.286,.055,0,'gold')
 cyl('顶部蓝色盖',(0,0,.915),.25,.065,1,'blue')
 cyl('盖中心触点',(0,0,.953),.09,.012,0,'gold')
 path('顶部黄提手',[(-.13,0,.95),(-.12,0,1.065),(.12,0,1.065),(.13,0,.95)],.024,0,'gold')
 for s in [-1,1]:
  x=s*.328
  cyl('侧黄色电芯',(x,0,.44),.049,.52,0,'gold')
  for z in [.235,.64]:cyl('电芯黑箍',(x,0,z),.061,.071,1,'dark')
  path('上部U管',[(s*.25,0,.81),(s*.32,0,.84),(x,0,.74)],.025,0,'gold')
  path('下部U管',[(s*.24,0,.12),(s*.31,0,.12),(x,0,.22)],.025,0,'gold')
  plate('蓝色吊耳',[(.0,.71),(.0,.92),(.08,.94),(.13,.79)],.04,1,'blue').location.x=s*.25
  for z in [.22,.57,.88]:bolt('外壳铆钉',(s*.18,-.215,z),r=.012)
  box('侧面金色细线',(s*.24,-.14,.41),(.012,.013,.28),0,'gold',.004)
def battery_small():
 cyl('紫色电池壳',(0,0,.43),.20,.70,2,'purple',bevel=.025)
 cyl('银色负极底',(0,0,.058),.194,.058,0,'silver')
 cyl('金色底环',(0,0,.105),.208,.095,0,'gold')
 cyl('银色顶盖',(0,0,.80),.21,.09,0,'silver')
 tube('顶盖压槽',(0,0,.851),.174,.164,.009,1,'dark','z')
 cyl('正极凸钮',(0,0,.885),.071,.07,0,'silver')
 for z in [.29,.47,.65]:bolt('接缝铆钉',(.09,-.176,z),r=.011)
def health_potion():
 # Shared clearcoat role stays opaque; milky upper glass is a stylized palette treatment.
 lathe('粉色药液瓶身',[(.04,.08),(.055,.17),(.10,.245),(.19,.30),(.31,.323),(.42,.32),(.50,.29)],2,'pink',n=64)
 lathe('浅色玻璃肩',[(.50,.29),(.57,.245),(.61,.18),(.635,.11),(.69,.105)],2,'pink_light',n=64)
 tube('药液水平分界',(0,0,.499),.293,.286,.008,2,'pink_light','z')
 lathe('底部玻璃包边',[(.032,.09),(.04,.17),(.068,.215),(.088,.236)],2,'pink_light',n=64)
 cyl('瓶颈金属束口',(0,0,.685),.115,.09,0,'steel')
 cyl('金属旋盖',(0,0,.765),.178,.09,0,'silver')
 tube('瓶盖同心压线',(0,0,.813),.136,.128,.007,0,'steel','z')
 cyl('瓶盖中心面',(0,0,.814),.125,.01,0,'silver')
 for s in [-1,1]:bolt('瓶盖锁点',(s*.165,0,.765),'x',.013)
 # One continuous rounded cross, floating minimally above the convex front surface.
 a=.052;b=.145
 cross=[(-a,b),(a,b),(a,a),(b,a),(b,-a),(a,-a),(a,-b),(-a,-b),(-a,-a),(-b,-a),(-b,a),(-a,a)]
 o=plate('白色医疗十字',cross,.028,1,'white','y');o.location=(0,-.319,.31)
def bullet_standard():
 tube('银色底口',(0,0,.07),.205,.135,.09,0,'silver','z')
 cyl('底口深色内壁',(0,0,.115),.137,.028,1,'black')
 cyl('银色弹底环',(0,0,.17),.204,.07,0,'silver')
 cyl('黑色细密封圈',(0,0,.213),.193,.023,1,'dark')
 cyl('蓝色弹壳',(0,0,.435),.194,.43,1,'blue',bevel=.024)
 cyl('银色弹颈圈',(0,0,.66),.195,.055,0,'silver')
 lathe('金色圆锥弹头',[(.681,.191),(.75,.184),(.84,.158),(.93,.115),(1.01,.061),(1.045,.018),(1.05,.001)],0,'gold',n=64)
def big_mag():
 box('黑色后壳',(0,.015,.45),(.40,.17,.88),1,'dark',.06)
 box('浅蓝色主壳',(0,.0,.52),(.38,.20,.85),1,'blue',.06)
 # Open rectangular carrying / mounting loop.
 for x in [-.137,.137]:box('提环侧壁',(x,0,.97),(.065,.18,.13),0,'steel',.025)
 box('提环上梁',(0,0,1.04),(.31,.18,.055),0,'steel',.02)
 box('黑色前内衬',(0,-.126,.47),(.33,.045,.76),1,'dark',.025)
 box('粉色前护板',(0,-.162,.40),(.33,.037,.59),1,'pink',.024)
 for x in [-.092,.092]:box('上部黑色插舌',(x,-.138,.80),(.088,.076,.20),1,'dark',.018)
 box('黑色底护块',(0,-.173,.076),(.365,.075,.10),1,'dark',.018)
 cyl('银色侧供弹管',(.203,.008,.44),.038,.65,0,'silver')
 box('侧粉色滑轨',(.237,-.01,.49),(.047,.062,.62),2,'pink',.01)
 for z in [.21,.46,.74]:
  box('侧滑轨黑锁扣',(.246,-.045,z),(.078,.12,.081),1,'dark',.014)
  box('锁扣金色按钮',(.25,-.111,z),(.041,.016,.040),0,'gold',.008)
 for x in [-.14,.14]:
  for z in [.15,.63]:bolt('粉面固定钉',(x,-.186,z),r=.012)
 for z in [.13,.92]:bolt('壳体侧钉',(.13,-.104,z),r=.012)
def triple_muzzle():
 box('后部深色护框',(0,-.14,0),(.49,.13,.51),1,'dark',.075)
 box('粉色三叉主体',(0,-.015,0),(.46,.24,.46),1,'pink',.068)
 for x,z in [(0,.118),(-.13,-.115),(.13,-.115)]:
  cyl('粉色枪管座',(x,.16,z),.12,.17,2,'pink','y')
  tube('银色枪口',(x,.285,z),.112,.081,.16,0,'silver','y')
  tube('枪管黑内壁',(x,.21,z),.080,.069,.21,1,'black','y')
  cyl('枪膛暗面',(x,.102,z),.070,.012,1,'black','y')
 for x in [-.194,.194]:
  for z in [-.15,.15]:bolt('机匣铆钉',(x,.112,z),r=.011)
 box('顶部粉色定位块',(0,-.005,.25),(.105,.087,.03),2,'pink_light',.008)
def rubber_stock():
 # Longitudinal axis +Y towards receiver; wide rear recoil pad at -Y.
 pts=[(-.40,-.19),(-.40,.20),(.39,.095),(.40,-.035),(-.02,-.15)]
 plate('蓝色渐缩枪托',pts,.25,1,'blue')
 plate('下方黑色支撑',[(-.31,-.17),(.25,-.065),(-.30,-.34)],.18,1,'dark')
 box('前端深色连接座',(0,.41,.035),(.28,.085,.23),1,'dark',.022)
 # Rear open rounded oblong rubber buttplate with dark inner channel.
 pts2=[]
 for x,z,start in [(.073,.20,0),(-.073,.20,90),(-.073,-.20,180),(.073,-.20,270)]:
  for i in range(7):
   a=math.radians(start+i*15);pts2.append((x+.065*math.cos(a),-.43,z+.065*math.sin(a)))
 path('粉色橡皮后托框',pts2+[pts2[0]],.043,1,'pink')
 path('后托内侧黑边',[(x*.76,y+.015,z*.92) for x,y,z in pts2]+[(pts2[0][0]*.76,pts2[0][1]+.015,pts2[0][2]*.92)],.018,1,'dark')
 for s in [-1,1]:
  for y,z in [(-.32,.12),(-.29,-.10),(.31,.054)]:bolt('侧板固定钉',(s*.129,y,z),'x',.012)
def scope():
 cyl('白色瞄具筒',(0,0,.08),.185,.46,1,'white','y',.018)
 cyl('后部黑色伸缩段',(0,-.31,.08),.147,.22,1,'dark','y')
 for y in [.30,-.435]:
  cyl('粉色端环',(0,y,.08),.204,.085,2,'pink','y')
  tube('蓝色镜头护圈',(0,y+.048,.08),.193,.15,.045,1,'blue','y')
 tube('前镜筒蓝色外沿',(0,.344,.08),.204,.162,.055,1,'blue','y')
 tube('前镜头深色密封圈',(0,.349,.08),.164,.151,.013,1,'dark','y')
 # Clearcoat lens plus inset low-energy cyan center, fourth standard role only.
 lathe('青色凸透镜',[(-.006,.001),(0,.145),(.013,.136),(.026,.09),(.030,.001)],2,'cyan','y',(0,.341,.08))
 box('镜座白色连接块',(0,-.02,-.128),(.18,.20,.12),1,'white',.019)
 box('黑色导轨夹具',(0,-.02,-.21),(.235,.28,.065),1,'dark',.015)
 for x in [-.124,.124]:
  cyl('安装旋钮',(x,-.065,-.198),.042,.027,1,'dark','x')
  cyl('旋钮金属中心',(x*1.10,-.065,-.198),.021,.009,0,'gold','x')
 cyl('顶部黑色调节钮',(0,.04,.276),.054,.035,1,'dark')
 for x in [-.036,.036]:bolt('调节钮钉',(x,.038,.296),'z',.005)
 box('后镜环准星块',(0,-.43,.291),(.06,.065,.028),1,'blue',.008)
 for y in [-.44,.29]:
  for s in [-1,1]:bolt('镜环固定钉',(s*.19,y,.08),'x',.010)

BUILDERS={s[0]:globals()[s[0]] for s in SPECS}
def setup_materials():
 images=[n.image for m in bpy.data.materials for n in (m.node_tree.nodes if m.use_nodes else []) if n.type=='TEX_IMAGE' and n.image]
 img=images[0] if images else bpy.data.images.load(str(PAL))
 img.filepath=str(PAL);img.reload()
 for i,name in enumerate(ROLES):
  m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;m.use_fake_user=True
  nt=m.node_tree;nt.nodes.clear();o=nt.nodes.new('ShaderNodeOutputMaterial');p=nt.nodes.new('ShaderNodeBsdfPrincipled')
  p.inputs['Metallic'].default_value=[.86,.02,.18,0][i];p.inputs['Roughness'].default_value=[.28,.72,.16,.4][i];p.inputs['Coat Weight'].default_value=[.15,0,.65,0][i]
  uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';t=nt.nodes.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest'
  nt.links.new(uv.outputs['UV'],t.inputs['Vector']);nt.links.new(t.outputs['Color'],p.inputs['Base Color']);nt.links.new(p.outputs['BSDF'],o.inputs['Surface'])
  if i==3:nt.links.new(t.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=1.3
 for m in list(bpy.data.materials):
  if m.name not in ROLES:bpy.data.materials.remove(m)
 return img

def camera_light(collection,center,scale):
 scene=bpy.context.scene
 def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
 cam=bpy.data.objects.new('PreviewCamera',bpy.data.cameras.new('PreviewCamera'));collection.objects.link(cam);scene.camera=cam
 cam.data.type='ORTHO';cam.data.ortho_scale=scale*1.65;cam.location=Vector(center)+Vector((1.5,2.4,1.45))*scale;aim(cam,center)
 for name,loc,energy,size in [('Key',(-2,3,4),650,3),('Fill',(3,1,2),400,2.5),('Rim',(0,-3,3),800,2)]:
  d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size*scale
  o=bpy.data.objects.new(name,d);collection.objects.link(o);o.location=Vector(center)+Vector(loc)*scale;d.energy=energy*scale*scale*.35;aim(o,center)
 scene.world=bpy.data.worlds.new('StudioWorld');scene.world.use_nodes=True;next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.24,.27,.33,1);next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.6
 scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
 scene.render.resolution_x=720;scene.render.resolution_y=720;scene.render.resolution_percentage=100;scene.render.film_transparent=True
 scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.2
 return cam,aim

def build(spec):
 global NAME,COMPONENTS
 slug,NAME,logical,aid,domain,subclass,axis,target=spec
 prefix='itm' if domain=='props' else 'wpn'
 folder=ROOT/'art_source/items_weapons'/domain/slug;source=folder/'source'/f'{prefix}_{slug}_source_v001.blend';source.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.wm.open_mainfile(filepath=str(TEMPLATE))
 for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
 for c in list(bpy.data.collections):bpy.data.collections.remove(c)
 for m in list(bpy.data.meshes):bpy.data.meshes.remove(m)
 root=bpy.data.collections.new(prefix.upper()+'_'+NAME+'_中文资产管理');bpy.context.scene.collection.children.link(root)
 cols={}
 for n in COLS:cols[n]=bpy.data.collections.new(n);root.children.link(cols[n])
 COMPONENTS=cols[COLS[0]];output=cols[COLS[1]];img=setup_materials()
 BUILDERS[slug]()
 # Uniform physical unit conversion from modeled reference proportions to measured principal axis.
 bpy.context.view_layer.update();pts=[o.matrix_world@Vector(v) for o in COMPONENTS.objects for v in o.bound_box]
 lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)])
 factor=target/(hi[axis]-lo[axis]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 # Attachment origin at measured socket center; pickup sources have a grounded origin.
 if subclass=='attachment':shift.z=(lo.z+hi.z)/2
 for o in COMPONENTS.objects:
  world=o.matrix_world.copy();o.data.transform(Matrix.Scale(factor,4)@Matrix.Translation(-shift)@world);o.matrix_world=Matrix.Identity(4)
  for mod in o.modifiers:
   if mod.type=='BEVEL':mod.width*=factor
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 root_obj=bpy.data.objects.new('ItemRoot',None);cols[COLS[3]].objects.link(root_obj);root_obj['asset_id']=aid
 for o in list(COMPONENTS.objects):
  ev=o.evaluated_get(dg);mesh=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=dg)
  c=bpy.data.objects.new(prefix+'_'+slug+'_'+o.name.split('_制作组件_')[-1],mesh);output.objects.link(c);c.parent=root_obj
  # Bevel-generated UVs are remapped to the source color's safe cell per face.
  mat=o.data.materials[0];role=ROLES.index(mat.name);u=o.data.uv_layers.active.data[0].uv
  cell=(int(u.x*10),9-int(u.y*10));color=next(k for k,v in C.items() if v==cell);uv_assign(c,role,color)
 bpy.ops.object.select_all(action='DESELECT')
 for o in output.objects:o.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(output.objects))
 bpy.ops.object.join()
 bpy.context.object.name=prefix+'_'+slug+'_主体_金属哑光反光'
 COMPONENTS.hide_render=True;COMPONENTS.hide_viewport=True
 pts=[o.matrix_world@Vector(v) for o in output.objects for v in o.bound_box];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);size=hi-lo
 dims={'width':round(size.x,6),'depth':round(size.y,6),'height':round(size.z,6)}
 measured=json.loads((OUT/'runtime_dimensions.json').read_text('utf8'))[logical]
 contract={'schema_version':1,'asset_id':aid,'display_name_zh':NAME,'logical_id':logical,'category':'道具' if domain=='props' else '武器','subclass':subclass,'domain_ledger':f'assets/registry/ledgers/ShellStorm2_{"道具" if domain=="props" else "武器"}账本_v001.xlsx','dimensions_m':dims,'dimension_basis':{'runtime_probe':measured,'locked_axis_blender':axis,'locked_length_m':target,'method':'按实测主轴定总长；其余轴保持用户参考图形体比例；非将旧占位盒非等比挤成新形体。','snapshot_date':'2026-10-14'},'origin_and_facing':'挂点中心原点；Blender +Y 对应 Godot -Z 枪口，+Z向上' if subclass=='attachment' else '底面中心原点；Blender +Z向上，正面-Y；Godot +Y向上、正面+Z','collision_intent':{'enabled':False,'owner':'外部拾取/武器系统','method':'无Blender碰撞'},'animation_tier':'tier_0_static','animation_reason':'独立闭合消耗品/固定配件；无本体运行时开合动画契约，换弹由整件挂点运动驱动。','source_collection':root.name,'anchor_contract':['ItemRoot'],'material_roles':ROLES,'material_rule_override':'用户明确要求使用场景材质球规范，武器配件沿用同一四角色模板。','source_dir':source.parent.relative_to(ROOT).as_posix(),'source_blend':source.relative_to(ROOT).as_posix(),'stable_glb':f'assets/art/items_weapons/{domain}/{slug}/components/{prefix}_{slug}_visual_top3d.glb','stable_prefab':f'assets/art/items_weapons/{domain}/{slug}/runtime/{prefix}_{slug}_root_top3d.tscn','function_note':'仅Blender原始源制作；后续导入保持现有物品使用/装配规则；当前运行时仍用原表现','status':'Blender源已完成','glass_note':'严格四材质公共色盘，药瓶采用不透明清漆与浅色肩部表现玻璃感；未新增透明材质。' if slug=='health_potion' else ''}
 write(folder/'asset_contract.json',contract)
 scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
 scene['source_contract']=json.dumps(contract,ensure_ascii=False);scene['authoring_stage']='SOURCE_ONLY_NOT_IMPORTED'
 center=(lo+hi)/2;extent=max(size)
 cam,aim=camera_light(cols[COLS[4]],center,extent)
 # Face forward (+Y) for barrels; consumables face -Y.
 direction=1 if slug in ['scope','triple_muzzle'] else -1
 cam.location=center+Vector((1.5,direction*2.4,1.45))*extent;aim(cam,center)
 bpy.context.view_layer.update();img.filepath='//'+os.path.relpath(PAL,source.parent).replace('\\','/')
 for area in bpy.context.screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_distance=extent*2.7;area.spaces.active.region_3d.view_location=center
 bpy.ops.object.select_all(action='DESELECT')
 bpy.context.preferences.filepaths.save_version=0; temp=OUT/(slug+str(time.time_ns())+".blend"); bpy.ops.wm.save_as_mainfile(filepath=str(temp),relative_remap=False); shutil.copyfile(temp,source); img.filepath=str(PAL); img.reload()
 render_dir=OUT/'previews'/slug;render_dir.mkdir(parents=True,exist_ok=True)
 views={'hero':tuple(cam.location),'front':tuple(center+Vector((0,direction*3,0))*extent),'side':tuple(center+Vector((3,0,0))*extent),'top':tuple(center+Vector((0,0,3))*extent),'game':tuple(center+Vector((1.6,direction*2,3.1))*extent)}
 for name,pos in views.items():
  cam.location=pos;aim(cam,center);scene.render.filepath=str(render_dir/(name+'.png'));bpy.ops.render.render(write_still=True)
 manifest={'asset_id':aid,'source_blend':contract['source_blend'],'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'dimensions_m':dims,'components':len(COMPONENTS.objects),'output_meshes':len(output.objects),'triangles':sum(len(o.data.loop_triangles) for o in output.objects),'source_only':True,'previews':str(render_dir),'contract':str(folder/'asset_contract.json')}
 for o in output.objects:o.data.calc_loop_triangles()
 manifest['triangles']=sum(len(o.data.loop_triangles) for o in output.objects)
 write(folder/'source_manifest.json',manifest);return manifest

if __name__=='__main__':
 args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 specs=[s for s in SPECS if not args or s[0] in args]
 for s in specs:
  m=build(s);write(OUT/(s[0]+'_build.json'),m);print('REFERENCE_ITEM_BUILT',json.dumps(m,ensure_ascii=False),flush=True)






