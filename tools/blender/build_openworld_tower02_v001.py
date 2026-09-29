"""Tower 02: editable architectural source, palette-only materials, package manifests."""
import bpy, math, json, random
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
OUT=R/'assets/art/environments/open_world/source/tower_02/v001'
OUT.mkdir(parents=True,exist_ok=True)
for d in ('previews','qa','component_packages'): (OUT/d).mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
palette=bpy.data.images.load(str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'))
names=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
mats=[]
for i,name in enumerate(names):
 m=bpy.data.materials.new(name); m.use_nodes=True
 n=m.node_tree.nodes; p=n.get('Principled BSDF')
 p.inputs['Metallic'].default_value=[.82,.02,.16,0][i]
 p.inputs['Roughness'].default_value=[.3,.7,.16,.38][i]
 p.inputs['Coat Weight'].default_value=[.15,0,.65,0][i]
 uv=n.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
 tex=n.new('ShaderNodeTexImage'); tex.image=palette; tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']); m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
 if i==3:
  m.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=1.2
 mats.append(m)
def col(name,parent):
 c=bpy.data.collections.new(name); parent.children.link(c); return c
root=col('塔2_开放世界施工高楼_中文资产管理',scene.collection)
src=col('01_制作组件_按设施拆分',root); src.hide_render=True; src.hide_viewport=True
game=col('02_游戏输出_独立资产包_v001',root)
display=col('90_展示与验收_灯光相机',root)
categories={k:col(v,game) for k,v in [('architecture','01_建筑结构'),('scaffold','02_脚手架及围网'),('facilities','03_施工设施'),('roof','04_屋顶施工构件')]}
# Palette coordinates are column, row counted from top (zero based).
WHITE=(9,9); CONCRETE=(9,8); STEEL=(9,4); DARK=(9,1); GOLD=(6,3); GREEN=(5,4); TEAL=(5,5); BLUE=(6,6); RED=(4,1); WOOD=(6,2)
class Part:
 def __init__(self,slug,name,category):
  self.slug=slug; self.name=name; self.category=category; self.v=[]; self.f=[]; self.colors=[]; self.mi=[]
 def poly(self,verts,faces,color,mat=1):
  off=len(self.v); self.v.extend(verts)
  for face in faces: self.f.append(tuple(off+i for i in face)); self.colors.append(color); self.mi.append(mat)
 def box(self,p,s,c=CONCRETE,m=1):
  x,y,z=p; a,b,d=[t/2 for t in s]
  self.poly([(x+i*a,y+j*b,z+k*d) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],c,m)
 def rod(self,a,b,r=.06,c=STEEL,m=0,n=6):
  a,b=Vector(a),Vector(b); w=(b-a).normalized(); u=w.cross(Vector((0,0,1)))
  if u.length<.01: u=w.cross(Vector((0,1,0)))
  u.normalize(); v=w.cross(u)
  verts=[tuple(p+r*(math.cos(i*2*math.pi/n)*u+math.sin(i*2*math.pi/n)*v)) for p in (a,b) for i in range(n)]
  self.poly(verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],c,m)
 def slab(self,z):
  # Concave front recess, split into three true solid rectangles.
  self.box((0,3,z),(70,44,.5),WHITE)
  self.box((-22.5,-22,z),(25,6,.5),WHITE)
  self.box((17.5,-22,z),(35,6,.5),WHITE)
 def finish(self):
  c=col(self.name+'_资产包',categories[self.category]); mesh=bpy.data.meshes.new(self.name+'_可编辑网格')
  mesh.from_pydata(self.v,[],self.f); mesh.update()
  for mat in mats[:3]: mesh.materials.append(mat)
  uv=mesh.uv_layers.new(name='PaletteUV'); uv.active_render=True
  for p,color,mi in zip(mesh.polygons,self.colors,self.mi):
   p.material_index=mi; cx=(color[0]+.5)/10; cy=1-(color[1]+.5)/10
   for j,li in enumerate(p.loop_indices):
    t=2*math.pi*j/len(p.loop_indices); uv.data[li].uv=(cx+.026*math.cos(t),cy+.026*math.sin(t))
  o=bpy.data.objects.new(self.name,mesh); c.objects.link(o); o['package_id']='tower_02/'+self.slug
  o['version']='v001'; o['unit']='meter'; o['game_building_id']='塔2'
  source=o.copy(); source.data=mesh.copy(); source.name=self.name+'_制作源'; src.objects.link(source)
  mn=[min(v[j] for v in self.v) for j in range(3)]; mx=[max(v[j] for v in self.v) for j in range(3)]
  info=dict(package_id='tower_02/'+self.slug,display_name=self.name,slug=self.slug,category=self.category,version='v001',source_blend='塔2_施工高楼_70x50m_v001.blend',collection=c.name,objects=[o.name],root_object=o.name,world_position=[0,0,0],local_origin=[0,0,0],front_direction='-Y',bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)],material_roles=names[:3],animation=False,emissive=False,dependencies=[],collision_status='not_authored',exported=False,expected_export=self.slug+'.glb',fixed_display_attachment=True)
  path=OUT/'component_packages'/self.category/self.slug; path.mkdir(parents=True,exist_ok=True); (path/'asset_manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8'); catalog.append(info)
catalog=[]
outline=[(-35,-25),(-10,-25),(-10,-19),(0,-19),(0,-25),(35,-25),(35,25),(-35,25)]
segments=list(zip(outline,outline[1:]+outline[:1]))
def rail(p,a,b,z,color=GOLD):
 a,b=Vector(a),Vector(b); length=(b-a).length
 for h in (.55,1.1): p.rod((*a,z+h),(*b,z+h),.055,color)
 for i in range(math.ceil(length/2.5)+1):
  q=a+(b-a)*i/math.ceil(length/2.5); p.rod((*q,z),(*q,z+1.15),.065,color)
def edgepoint(a,b,t): return (a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t)
# Twenty individually editable floors, full structural grid and slab edge details.
for floor in range(21):
 z=.25+floor*4.2
 p=Part('floor_%02d'%floor,'楼层_%02d_楼板柱梁'%floor,'architecture'); p.slab(z)
 if floor<20:
  for x in [-33.8,-23,-12,0,11,22,33.8]:
   for y in [-23.8,-12,0,12,23.8]:
    if -10<x<0 and y<-19: continue
    p.box((x,y,z+2.3),(1.15,1.15,4.1),CONCRETE)
  for y in [-23.8,-12,0,12,23.8]:
   if y<-19:
    p.box((-22.5,y,z+3.8),(25,.8,.7)); p.box((17.5,y,z+3.8),(35,.8,.7))
   else: p.box((0,y,z+3.8),(68.7,.8,.7))
  for a,b in segments: rail(p,a,b,z+.3)
 p.finish()
print('STRUCTURE_DONE',flush=True)
# Central service cores and stairs, each floor accessible in source.
for k,(x,y) in enumerate([(-13,5),(14,6)]):
 p=Part('core_%d'%k,'核心筒_%d_楼梯及开口'%k,'architecture')
 for f in range(20):
  z=f*4.2+.5
  p.box((x-3.8,y,z+2),( .4,9,4),CONCRETE); p.box((x+3.8,y,z+2),(.4,9,4),CONCRETE)
  p.box((x,y+4.3,z+2),(7.6,.4,4),CONCRETE)
  p.box((x-2.5,y-4.3,z+2),(2.2,.4,4),CONCRETE); p.box((x+2.5,y-4.3,z+2),(2.2,.4,4),CONCRETE)
  p.box((x,y-4.3,z+3.6),(3,.4,.8),CONCRETE)
  for j in range(12):
   for side in [-1,1]: p.box((x+side*1.5,y+side*(-2.6+j*.43),z+(j+1)*.175+(2.1 if side==1 else 0)),(2.6,.45,.18),WHITE)
  p.box((x,y+3,z+2.1),(6,1.8,.22),WHITE)
 p.finish()
# Per-face scaffolding, diagonal bracing, anchorage, green safety fabric panels.
for si,(a,b) in enumerate(segments):
 p=Part('scaffold_%02d'%si,'立面_%02d_脚手架围网'%si,'scaffold')
 av,bv=Vector(a),Vector(b); vec=bv-av; outward=Vector((vec.y,-vec.x)).normalized(); av+=outward*.85; bv+=outward*.85
 count=math.ceil(vec.length/3)
 for j in range(count+1):
  q=av+(bv-av)*j/count; p.rod((*q,1),(*q,86),.075,STEEL)
  for z in [20,40,60,80]: p.rod((*q,z),(*(q-outward*1.7),z),.07,STEEL)
 for f in range(21):
  z=f*4.2+.6
  p.rod((*av,z),(*bv,z),.06,GOLD)
  if f in [0,4,10,16,20]:
   for j in range(count):
    q=av+(bv-av)*(j+.5)/count
    size=(vec.length/count,1.5,.13) if abs(vec.x)>0 else (1.5,vec.length/count,.13)
    p.box((*q,z),size,WOOD)
   rail(p,tuple(av),tuple(bv),z+.1)
  for j in range(count):
   q=av+(bv-av)*j/count; t=av+(bv-av)*(j+1)/count
   if j%3==0: p.rod((*q,z),(*t,z+4.2),.047,STEEL)
   covered=(16<=f<20) or (f in [10,11] and j<count*.6) or (12<=f<15 and si==4 and j>count*.5)
   if covered:
    # Fabric has a lightly bowed center and segmented seams, remains opaque palette-only.
    center=(q+t)*.5+outward*.035
    verts=[(*q,z+.12),(*t,z+.12),(*t,z+4),(*q,z+4),(*center,z+2.1)]
    p.poly(verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],GREEN if (j+f)%3 else TEAL)
    p.rod((*q,z+.14),(*t,z+.14),.035,TEAL)
 p.finish()
# Blue lower climbing protection screens with battens, strongbacks, brackets and bolt heads.
for si,(a,b) in enumerate(segments):
 p=Part('climbing_screen_%02d'%si,'立面_%02d_蓝色爬架屏'%si,'scaffold'); av,bv=Vector(a),Vector(b); d=bv-av; normal=Vector((d.y,-d.x)).normalized(); av+=normal*1.05; bv+=normal*1.05
 count=max(1,round(d.length/5))
 for j in range(count):
  if j%5==4: continue
  q=av+d*(j+.5)/count; w=d.length/count-.2; z=21+(j%3)*.35
  p.box((*q,z),(w,.12,13) if abs(d.x) else (.12,w,13),BLUE)
  for side in [-1,0,1]:
   t=q+d.normalized()*w*.48*side+normal*.15; p.rod((*t,z-6.5),(*t,z+6.5),.075,CONCRETE)
   for h in [-6,-3,0,3,6]:
    u=t+normal*.08; p.rod((*u,z+h),(*(u+normal*.13),z+h),.1,WHITE)
  for h in [-6.5,-3.25,0,3.25,6.5]:
   t=q-d.normalized()*w*.5+normal*.18; u=q+d.normalized()*w*.5+normal*.18; p.rod((*t,z+h),(*u,z+h),.065,WHITE)
 p.finish()
# Exterior construction elevator: twin braced rails, four red cabins and floor gates.
p=Part('construction_elevator','双笼施工电梯_导轨附墙架','facilities')
for x in [17,20]:
 for xx in [x-.48,x+.48]:
  for y in [-27.4,-28.4]: p.rod((xx,y,.5),(xx,y,88),.09,STEEL)
 for z in range(1,88,2):
  for y in [-27.4,-28.4]:
   p.rod((x-.48,y,z),(x+.48,y,z+2),.06,GOLD); p.rod((x-.48,y,z),(x+.48,y,z),.06,STEEL)
 for f in range(21): p.rod((x,-28,f*4.2+1),(x,-24,f*4.2+1),.12,STEEL)
for i,z in enumerate([8,27,49,70]):
 x=15.1 if i%2 else 22.3; y=-28
 p.box((x,y,z),(3.4,3,3.6),RED)
 for side in [-1,1]:
  p.box((x+side*.85,y-1.52,z+.45),(1.4,.1,1.65),DARK,2)
  for dx in [-.65,0,.65]: p.rod((x+side*.85+dx,y-1.62,z-.38),(x+side*.85+dx,y-1.62,z+1.3),.04,WHITE)
 p.box((x,y,z+1.9),(3.7,3.3,.18),STEEL,0)
p.finish()
# Roof columns: dense rebar cages, formwork ribs and clamps.
for k,(x,y) in enumerate([(x,y) for x in [-29,-16,-3,10,26] for y in [-16,0,18]]):
 p=Part('roof_column_%02d'%k,'屋顶柱_%02d_钢筋模板'%k,'roof'); base=84.5; height=[5,7,6,8][k%4]
 p.box((x,y,base+height/2),(2,2,height),CONCRETE)
 for dx in [-.88,0,.88]:
  for dy in [-.88,0,.88]:
   p.rod((x+dx,y+dy,base),(x+dx,y+dy,base+height+2.4),.055,STEEL)
 for j in range(int(height*3)):
  z=base+j*.33
  for a,b in [((-1,-1),(1,-1)),((1,-1),(1,1)),((1,1),(-1,1)),((-1,1),(-1,-1))]: p.rod((x+a[0],y+a[1],z),(x+b[0],y+b[1],z),.037,STEEL)
 if k%3:
  h=height*.65
  for side in [-1,1]:
   p.box((x+side*1.12,y,base+h/2),(.15,2.4,h),WOOD)
   p.box((x,y+side*1.12,base+h/2),(2.4,.15,h),WOOD)
   for off in [-1,-.5,0,.5,1]:
    p.box((x+side*1.24,y+off,base+h/2),(.14,.11,h),GOLD,0)
    p.box((x+off,y+side*1.24,base+h/2),(.11,.14,h),GOLD,0)
  for z in [base+.6,base+h-.5]:
   p.box((x,y,z),(2.8,2.8,.13),GOLD,0)
 p.finish()
random.seed(22)
p=Part('roof_material_stacks','屋顶_固定材料堆及机具','roof')
for k in range(28):
 x=random.uniform(-29,29); y=random.choice([-10,9,21]); z=84.65
 if k%3==0:
  for j in range(8): p.box((x,y,z+j*.17),(4,.9,.13),WOOD)
 elif k%3==1:
  for j in range(7): p.rod((x-2,y+j*.2,z+.18),(x+2,y+j*.2,z+.18),.09,STEEL)
 else:
  p.box((x,y,z+.65),(1.8,1.2,1.3),RED if k%2 else BLUE)
  p.box((x,y-.62,z+.8),(1.2,.06,.55),DARK,2)
  for dx in [-.65,.65]: p.box((x+dx,y,z+.15),(.12,1.5,.15),STEEL,0)
p.finish()
for k,(x,y,w,d,h) in enumerate([(-19,7,7,6,6),(3,-6,8,6,4),(22,10,6,7,5)]):
 p=Part('roof_formwork_%d'%k,'屋顶核心模板_%d_支撑平台'%k,'roof'); z=84.5
 p.box((x,y,z+h/2),(w,d,h),WOOD)
 for side in [-1,1]:
  for j in range(int(w)+1): p.box((x-w/2+j,y+side*(d/2+.12),z+h/2),(.14,.18,h),GOLD,0)
  for j in range(int(d)+1): p.box((x+side*(w/2+.12),y-d/2+j,z+h/2),(.18,.14,h),GOLD,0)
  for zz in [z+.7,z+2.6,z+h-.2]:
   p.box((x,y+side*(d/2+.26),zz),(w+.8,.17,.2),GOLD,0)
   p.box((x+side*(w/2+.26),y,zz),(.17,d+.8,.2),GOLD,0)
  for xx in [-w/2,w/2]: p.rod((x+xx,y+side*(d/2+3),z),(x+xx,y+side*d/2,z+h-.4),.085,STEEL)
 p.box((x,y,z+h+.1),(w+.8,d+.8,.2),CONCRETE)
 for a,b in [((x-w/2-.6,y-d/2-.6),(x+w/2+.6,y-d/2-.6)),((x-w/2-.6,y+d/2+.6),(x+w/2+.6,y+d/2+.6))]: rail(p,a,b,z+h+.2)
 p.finish()
# Three complete tower cranes with lattice masts/jibs, counterweights, cab glazing, ropes/hooks.
for idx,(cx,cy,base,top,angle) in enumerate([(-40,-18,0,112,10),(11,12,84.5,125,165),(39,18,0,108,-35)]):
 p=Part('crane_%02d'%idx,'塔吊_%02d_桁架驾驶室吊钩'%idx,'facilities')
 theta=math.radians(angle)
 def pt(x,y,z): return (cx+x*math.cos(theta)-y*math.sin(theta),cy+x*math.sin(theta)+y*math.cos(theta),z)
 def beam(a,b,r=.12,c=GOLD): p.rod(pt(*a),pt(*b),r,c)
 p.box((cx,cy,base+.5),(5.4,5.4,1),CONCRETE)
 for x in [-1.2,1.2]:
  for y in [-1.2,1.2]: beam((x,y,base+1),(x,y,top),.18)
 levels=math.ceil((top-base-1)/3)
 for j in range(levels):
  z=base+1+j*(top-base-1)/levels; zz=min(top,z+(top-base-1)/levels)
  for a,b in [((-1.2,-1.2),(1.2,-1.2)),((1.2,-1.2),(1.2,1.2)),((1.2,1.2),(-1.2,1.2)),((-1.2,1.2),(-1.2,-1.2))]:
   beam((*a,z),(*b,z),.12); beam((*a,z),(*b,zz),.09); beam((*b,z),(*a,zz),.065)
  beam((-.5,0,z),(-.5,0,zz),.04,STEEL); beam((.5,0,z),(.5,0,zz),.04,STEEL)
  for h in [0,.4,.8,1.2,1.6,2,2.4]: beam((-.5,0,z+h),(.5,0,z+h),.035,STEEL)
 for z in [base+3,top-3]:
  p.box((cx,cy,z),(4.8,4.8,.2),GOLD,0)
  for a,b in [((-2.3,-2.3),(2.3,-2.3)),((2.3,-2.3),(2.3,2.3)),((2.3,2.3),(-2.3,2.3)),((-2.3,2.3),(-2.3,-2.3))]: rail(p,pt(*a,z)[:2],pt(*b,z)[:2],z+.1)
 # Jib bottom rails and triangular upper chord.
 for start,end in [(-13,0),(0,32)]:
  beam((start,-1,top+1),(end,-1,top+1),.15); beam((start,1,top+1),(end,1,top+1),.15); beam((start,0,top+2.5),(end,0,top+2.5),.13)
  for x in range(start,end,2):
   xx=min(x+2,end)
   for y in [-1,1]: beam((x,y,top+1),(xx,0,top+2.5),.075); beam((x,0,top+2.5),(xx,y,top+1),.075)
   beam((x,-1,top+1),(x,1,top+1),.07)
 beam((-1,-.8,top+1),(0,0,top+10),.18); beam((1,.8,top+1),(0,0,top+10),.18)
 for x in [-12,27]: beam((0,0,top+10),(x,0,top+2.4),.055,STEEL)
 for x in [-12,-10]: p.box(pt(x,0,top+.2),(2.2,3,2.8),WHITE)
 p.box(pt(1,-2,top-.7),(2.7,2.6,2.8),WHITE)
 p.box(pt(1,-3.32,top-.5),(2.1,.08,1.65),DARK,2)
 p.box(pt(2.4,-2,top-.5),(.08,2,1.65),DARK,2)
 for y in [-.3,.3]: beam((23,y,top+1),(23,y,top-17),.035,DARK)
 p.box(pt(23,0,top-17),(1,.9,1.2),GOLD,0)
 for a,b in [((23,0,top-17.5),(23,0,top-18.4)),((23,0,top-18.4),(23.5,0,top-18.8)),((23.5,0,top-18.8),(24,0,top-18.3))]: beam(a,b,.12,STEEL)
 # Building attachment collars for external masts.
 if base==0:
  for z in [25,48,71]:
   target=(max(-34,min(34,cx)),cy,z)
   for dy in [-1.3,1.3]: p.rod((cx,cy+dy,z),target,.16,GOLD)
 p.finish()
print('DETAIL_DONE',flush=True)
# A separately hidden emission marker makes all four shared roles intentional.
mesh=bpy.data.meshes.new('屋顶警示灯'); mesh.from_pydata([(-.2,-.2,0),(.2,-.2,0),(.2,.2,0),(-.2,.2,0)],[],[(0,1,2,3)]); mesh.materials.append(mats[3]); uv=mesh.uv_layers.new(name='PaletteUV'); uv.active_render=True
for i,xy in enumerate([(.42,.12),(.48,.12),(.48,.18),(.42,.18)]): uv.data[i].uv=xy
lamp=bpy.data.objects.new('屋顶警示灯_柔和自发光',mesh); categories['roof'].children[0].objects.link(lamp); lamp.location=(-29,-16,92)
# Keep manifest exact after adding attached emission geometry.
catalog_item=next(x for x in catalog if x['slug']=='roof_column_00'); catalog_item['objects'].append(lamp.name); catalog_item['emissive']=True; catalog_item['material_roles']=names
(OUT/'component_packages/roof/roof_column_00/asset_manifest.json').write_text(json.dumps(catalog_item,ensure_ascii=False,indent=2),encoding='utf8')
def camera(name,location,target,scale):
 data=bpy.data.cameras.new(name); obj=bpy.data.objects.new(name,data); display.objects.link(obj); obj.location=location; obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler(); data.type='ORTHO'; data.ortho_scale=scale; data.lens=48; data.clip_end=1000; return obj
cameras=[camera('参考镜头_全景',(170,-230,180),(0,0,59),177),camera('俯视结构',(0,0,260),(0,0,0),150),camera('屋顶细节',(112,-142,159),(0,0,87),95),camera('立面施工细节',(100,-155,71),(12,-20,39),67),camera('背面完整性',(-175,220,165),(0,0,57),177)]
world=bpy.data.worlds.new('蓝色展示环境'); scene.world=world; world.use_nodes=True; world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.29,.46,1); world.node_tree.nodes['Background'].inputs[1].default_value=.65
for name,loc,power,size in [('主柔光',(30,-100,180),1900000,100),('补光',(-100,-20,100),1100000,90),('轮廓',(40,100,150),2100000,80)]:
 data=bpy.data.lights.new(name,'AREA'); data.energy=power*.08; data.shape='DISK'; data.size=size; o=bpy.data.objects.new(name,data); display.objects.link(o); o.location=loc; o.rotation_euler=(Vector((0,0,50))-o.location).to_track_quat('-Z','Y').to_euler()
sun=bpy.data.lights.new('日光','SUN'); sun.energy=2; sun.angle=.15; o=bpy.data.objects.new('日光',sun); display.objects.link(o); o.rotation_euler=(.4,-.6,-.4)
scene.render.engine='CYCLES'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.resolution_x=1600; scene.render.resolution_y=1600; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=0
scene.camera=cameras[0]
scene['building_id']='塔2'; scene['building_relationship']='peer_of_main_tower'; scene['footprint_m']=[70,50]; scene['floor_count']=20; scene['floor_height_m']=4.2; scene['height_source']='reference-derived authoring assumption; not gameplay floor contract'; scene['runtime_status']='Blender source only; not exported or integrated'
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D': area.spaces.active.region_3d.view_distance=190; area.spaces.active.region_3d.view_location=(0,0,55)
blend=OUT/'塔2_施工高楼_70x50m_v001.blend'
palette.filepath=bpy.path.relpath(palette.filepath,start=str(OUT))
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
(OUT/'catalog.json').write_text(json.dumps(dict(building_id='塔2',relationship='peer_of_main_tower',footprint_m=[70,50],floor_count=20,floor_height_m=4.2,source_status='authored_not_runtime',ledger_status='not_registered',packages=catalog),ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'package_tree.txt').write_text('\n'.join(x['category']+'/'+x['slug']+' — '+x['display_name'] for x in catalog),encoding='utf8')
print('SAVED',str(blend),'PACKAGES',len(catalog),flush=True)
for i,cam in enumerate(cameras):
 scene.camera=cam; scene.render.filepath=str(OUT/'previews'/('%02d_'%i+cam.name+'.png')); bpy.ops.render.render(write_still=True); print('RENDER_DONE',i,flush=True)
scene.camera=cameras[0]; bpy.ops.wm.save_as_mainfile(filepath=str(blend))
