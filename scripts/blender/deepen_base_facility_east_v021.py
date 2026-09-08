import bpy,bmesh,math,json,ast,hashlib,importlib.util,random
from pathlib import Path
from mathutils import Vector,Matrix
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_east_v021';OUT=P/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend'
names=['78_维修工作台与工具墙_资产包','80_低矮储物收纳区_资产包','83_东面植物点缀组_资产包']
C=[bpy.data.collections[n] for n in names];A=C[0];allowed=set(o for c in C for o in c.all_objects)
spec=importlib.util.spec_from_file_location('old',P/'scripts/blender/reorganize_base_facility_component_packages_v017.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
source=(P/'scripts/blender/deepen_base_facility_loft_v019.py').read_text();tree=ast.parse(source)
for name in ['sig','uv','mesh','move','bevel','box','tube','cyl','paint','text','leaf','potplant']:
 node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name);exec(ast.get_source_segment(source,node))
# Two segments only where silhouette benefits; micro-bevels use one segment.
_bevel=bevel
def bevel(o,width=.03,segments=2):return _bevel(o,width,1 if width<.03 else 2)
locked=json.loads(json.dumps({o.name:sig(o) for o in bpy.data.objects if o not in allowed}));(R/'locked_before.json').write_text(json.dumps(locked,ensure_ascii=False))
M=[bpy.data.materials[n] for n in ['01_精工金属_v018公共色盘','02_细腻哑光_v018公共色盘','03_清漆反光_v018公共色盘','04_柔和自发光_v018公共色盘']]
DARK=(.95,.95);STEEL=(.95,.65);TEAL=(.55,.45);GREEN=(.35,.45);LIGHT=(.95,.05);WALNUT=(.55,.75);TAN=(.85,.75);GOLD=(.85,.65);ORANGE=(.65,.75);RED=(.45,.85)
def triangles(obs):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs if o.type=='MESH')
before={c.name:{'triangles':triangles(c.all_objects),'bbox':old.bbox(list(c.all_objects))} for c in C}
S=[]
for c in C:
 for o in list(c.all_objects):bpy.data.objects.remove(o,do_unlink=True)
 for child in list(c.children):bpy.data.collections.remove(child)
 sc=bpy.data.collections.new(c.name[:2]+'_01_制作组件_统一材质_v021');c.children.link(sc);S.append(sc)
def shellcase(c,n,p,dim,cell,front=True):
 x,y,z=p;w,d,h=dim
 box(c,n+'_防冲击箱体',(x,y,z+h*.43),(w,d,h*.86),cell,b=min(.055,h*.10))
 box(c,n+'_箱盖密封缝',(x,y,z+h*.83),(w*1.012,d*1.012,.024),DARK,b=.014)
 box(c,n+'_独立箱盖',(x,y,z+h*.94),(w*1.01,d*1.01,h*.16),cell,b=min(.045,h*.07))
 # Fold-flat top handle and black inset.
 box(c,n+'_提手凹槽',(x,y,z+h*1.025),(w*.42,d*.17,.012),DARK,b=.015)
 tube(c,n+'_折叠提手',[(x-w*.17,y,z+h*1.035),(x-w*.14,y,z+h*1.095),(x+w*.14,y,z+h*1.095),(x+w*.17,y,z+h*1.035)],.022,STEEL,0,sides=6)
 for xx in [x-w*.31,x+w*.31]:
  box(c,n+'_锁扣'+str(xx),(xx,y+d*.51,z+h*.79),(.095,.04,h*.24),STEEL,0,b=.012)
 for xx in [x-w*.43,x+w*.43]:
  for yy in [y-d*.43,y+d*.43]:box(c,n+'_包角%.2f_%.2f'%(xx,yy),(xx,yy,z+.09),(.10,.10,.16),DARK,0,b=.018)
 return z+h*1.1
# flat graphic labels, no extruded high-resolution typography.
def frontlabel(c,n,body,p,size,cell=LIGHT):return text(c,n,body,p,size,cell,(math.pi/2,0,math.pi))
def topmark(c,n,p,size=.18):
 x,y,z=p
 # friendly rabbit outline and two ears, built from short polygonal strokes.
 pts=[(x+size*math.cos(a),y+size*.72*math.sin(a),z) for a in [j*math.tau/16 for j in range(17)]];tube(c,n+'_兔脸',pts,.009,LIGHT,sides=4)
 for xx in [x-size*.45,x+size*.45]:tube(c,n+'_耳'+str(xx),[(xx-size*.13,y+size*.55,z),(xx-size*.13,y+size*1.3,z),(xx+size*.13,y+size*1.3,z),(xx+size*.13,y+size*.55,z)],.009,LIGHT,sides=4)
 for xx in [x-size*.36,x+size*.36]:cyl(c,n+'_眼'+str(xx),(xx,y,z+.002),.016,.003,LIGHT,verts=6)
def mug(c,p):
 x,y,z=p;vs=[];profiles=[(0,.10),(.04,.14),(.33,.16),(.36,.16),(.36,.13),(.08,.11)]
 for zz,r in profiles:
  for j in range(16):a=j*math.tau/16;vs.append((x+r*math.cos(a),y+r*math.sin(a),z+zz))
 fs=[(k*16+j,k*16+(j+1)%16,(k+1)*16+(j+1)%16,(k+1)*16+j) for k in range(5) for j in range(16)];o=mesh(c,'台面_陶瓷杯',vs,fs,LIGHT)
 for f in o.data.polygons:f.use_smooth=True
 tube(c,'杯子_圆环柄',[(x+.15+.09*math.sin(j*math.pi/8),y,z+.18+.12*math.cos(j*math.pi/8)) for j in range(9)],.022,LIGHT,sides=6)
 cyl(c,'杯内咖啡',(x,y,z+.29),.125,.006,(.15,.75),verts=16)
# Keep established room placement; front is +Y. Board and countertop now form one continuous station.
c=S[0]
box(c,'维修台_耐磨钢台面',(6.2,-13.15,1.72),(5,2.05,.18),DARK,0,b=.045)
for x in [3.85,8.55]:
 box(c,'维修台_承重侧腿'+str(x),(x,-13.15,.84),(.20,1.88,1.62),DARK,0,b=.025)
 box(c,'维修台_脚垫'+str(x),(x,-13.15,.10),(.30,1.94,.15),STEEL,0,b=.016)
box(c,'维修台_下柜框',(6.2,-13.50,.62),(4.55,1.15,.72),DARK,0,b=.025)
for j,x in enumerate([4.68,6.2,7.72]):
 box(c,'维修台_独立抽屉%d'%j,(x,-12.88,.64),(1.42,.08,.57),(.95,.55),b=.02)
 box(c,'维修台_竖凹拉手%d'%j,(x-.51,-12.824,.73),(.07,.022,.20),DARK,b=.012)
box(c,'工具墙_背板',(6.2,-14.35,3.05),(5,.12,2.10),DARK,0,b=.035)
for x in [3.76,8.64]:box(c,'工具墙_侧框'+str(x),(x,-14.265,3.05),(.045,.025,2.0),STEEL,0)
# Two triangles per recess, no boolean holes or stacks of cylinders.
for row in range(6):
 for col in range(18):
  x=3.93+col*.267;z=2.22+row*.32
  mesh(c,'工具墙_冲孔_%d_%d'%(row,col),[(x-.012,-14.282,z-.012),(x+.012,-14.282,z-.012),(x+.012,-14.282,z+.012),(x-.012,-14.282,z+.012)],[(0,1,2,3)],(.95,.75),0)
box(c,'工具墙_灯具外壳',(6.2,-14.22,4.19),(4.62,.18,.15),DARK,0,b=.025)
box(c,'工具墙_青色任务灯_柔和自发光',(6.2,-14.111,4.18),(4.38,.015,.066),TEAL,3)
# Distinct hanging tool silhouettes, open-jaw spanners instead of solid round heads.
for j,x in enumerate([6.15,6.60,7.05,7.50,7.95]):
 h=.54+j*.06;z=2.64
 tube(c,'固定扳手%d_柄'%j,[(x,-14.16,z-h*.45),(x,-14.16,z+h*.42)],.027,STEEL,0,sides=6)
 tube(c,'固定扳手%d_开口头'%j,[(x-.09,-14.16,z+h*.65),(x-.10,-14.16,z+h*.46),(x,-14.16,z+h*.32),(x+.10,-14.16,z+h*.46),(x+.09,-14.16,z+h*.65)],.025,STEEL,0,sides=5)
for j,x in enumerate([4.25,4.72]):
 tube(c,'固定锤%d_柄'%j,[(x,-14.15,2.55),(x,-14.15,3.48)],.035,ORANGE,sides=6)
 box(c,'固定锤%d_头'%j,(x,-14.15,3.5),(.44,.17,.22),TEAL if j else (.75,.25),0,b=.025)
for j,x in enumerate([5.20,5.57]):
 cyl(c,'固定螺丝刀%d_握把'%j,(x,-14.15,3.00),.065,.25,ORANGE if j else TEAL,verts=8)
 tube(c,'固定螺丝刀%d_杆'%j,[(x,-14.15,2.50),(x,-14.15,2.89)],.018,STEEL,0,sides=5)
o=cyl(c,'挂墙_黄色卷尺',(5.42,-14.13,3.53),.17,.09,GOLD,verts=16);o.rotation_euler.x=math.pi/2
box(c,'挂墙_套筒盒',(6.13,-14.12,3.52),(.49,.16,.23),(.95,.55),0,b=.025)
for x in [4.25,4.72,5.2,5.57,6.15,6.6,7.05,7.5,7.95]:tube(c,'工具挂钩'+str(x),[(x,-14.28,3.23),(x,-14.10,3.23),(x,-14.1,3.30)],.014,STEEL,0,sides=4)
shellcase(c,'橙色维修工具箱',(6.50,-12.98,1.82),(1.30,.64,.48),ORANGE)
shellcase(c,'青绿零件盒',(7.92,-12.90,1.82),(.64,.46,.25),TEAL)
mug(c,(4.38,-13.08,1.82));cyl(c,'台面_润滑油罐',(4.96,-12.92,1.97),.066,.30,TEAL,verts=12);cyl(c,'油罐_喷头',(4.96,-12.92,2.14),.03,.05,STEEL,0,verts=8)
# Low storage is a hard-top bank of three inset bins, following the reference.
c=S[1]
box(c,'收纳柜_底座',(10.85,-14.0,.16),(2.88,1.10,.20),DARK,0,b=.025)
box(c,'收纳柜_框架',(10.85,-14.0,.72),(2.9,1.08,1.06),DARK,0,b=.025)
box(c,'收纳柜_硬质台面',(10.85,-13.98,1.30),(3.04,1.21,.16),DARK,0,b=.03)
for j,x in enumerate([9.91,10.85,11.79]):
 box(c,'收纳柜_抽箱%d'%j,(x,-13.428,.75),(.86,.07,.90),(.75,.25) if j==1 else (.95,.65),b=.025)
 box(c,'收纳柜_嵌入提手%d'%j,(x,-13.382,1.00),(.32,.02,.085),DARK,b=.012)
 box(c,'收纳柜_底部护角%d'%j,(x,-13.375,.35),(.76,.025,.05),STEEL,0)
shellcase(c,'收纳柜_青绿手提箱',(10.46,-13.99,1.40),(.90,.65,.39),TEAL)
# Three existing plant instances remain separate within 83; one sits on the storage countertop.
c=S[2]
for j,(x,y,z) in enumerate([(12.65,3.2,.13),(12,-7.95,.11),(11.73,-13.96,1.40)]):
 cyl(c,'植物%d_陶瓷盆'%j,(x,y,z+.19),.235,.38,LIGHT,verts=8)
 cyl(c,'植物%d_盆沿'%j,(x,y,z+.38),.248,.055,LIGHT,verts=8)
 cyl(c,'植物%d_土壤'%j,(x,y,z+.407),.208,.014,(.15,.75),verts=12)
 tube(c,'植物%d_主茎'%j,[(x,y,z+.40),(x,y,z+.89)],.028,GREEN,sides=6)
 for k in range(9):
  a=k*math.tau/8;r=.22 if k<8 else 0;loc=(x+r*math.cos(a),y+r*math.sin(a),z+.69+(.14 if k%2 else 0)+(.19 if k==8 else 0))
  bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=.155,location=loc);o=bpy.context.object;o.name='植物%d_圆润叶簇%d'%(j,k);move(o,c);o.scale=(1, .82,1.12);paint(o,GREEN if k%3 else (.35,.55))
  for f in o.data.polygons:f.use_smooth=True
placements=[((6.2,-13.15,0),0),((10.85,-14,0),0),((0,0,0),0)]
bpy.context.view_layer.update()
# Preserve semantic accessories as output objects; merge construction pieces by facility/material role.
catalog=[]
for c,sc in zip(C,S):
 out=bpy.data.collections.new(c.name[:2]+'_02_游戏输出_整合模型_v021');c.children.link(out);groups={}
 for o in list(sc.objects):
  if o.type!='MESH':sc.objects.unlink(o);out.objects.link(o);continue
  uv(o)
  if any(m==M[3] for m in o.data.materials):key='柔和自发光'
  elif c==C[2]:key=o.name.split('_')[0]
  elif any(k in o.name for k in ['工具箱','零件盒','手提箱','杯','咖啡','润滑油','油罐']):key='固定展示附件'
  else:key='主体'
  groups.setdefault(key,[]).append(o)
 for key,obs in groups.items():
  vs=[];fs=[];mi=[];us=[];sm=[];ns=[];mats=[]
  for o in obs:
   o.data.update();off=len(vs);vs.extend(tuple(o.matrix_world@v.co) for v in o.data.vertices);u=o.data.uv_layers[0];nt=o.matrix_world.to_3x3().inverted().transposed()
   for p in o.data.polygons:
    fs.append(tuple(off+i for i in p.vertices));m=o.data.materials[p.material_index]
    if m not in mats:mats.append(m)
    mi.append(mats.index(m));us.append([tuple(u.data[i].uv) for i in p.loop_indices]);sm.append(p.use_smooth);ns.extend(tuple((nt@o.data.corner_normals[i].vector).normalized()) for i in p.loop_indices)
  me=bpy.data.meshes.new(key+'_v021');me.from_pydata(vs,[],fs)
  for m in mats:me.materials.append(m)
  u=me.uv_layers.new(name='PaletteUV');me.uv_layers.active_index=0;u.active_render=True
  for p,idx,uu,smooth in zip(me.polygons,mi,us,sm):
   p.material_index=idx;p.use_smooth=smooth
   for li,t in zip(p.loop_indices,uu):u.data[li].uv=t
  me.normals_split_custom_set(ns);o=bpy.data.objects.new(c.name[:2]+'_'+key+'_v021',me);out.objects.link(o);o['fixed_display_attachment']=key not in ['主体','柔和自发光']
 sc.hide_viewport=True;sc.hide_render=True;c['资产类别']='east_facilities';c['组织版本']='v021';c['当前状态']='东面设施参考深化_待验收';slug=c['资产包键'];folder=P/'source/art/blender/base_facility_layout/component_packages/v021/east_facilities'/slug;folder.mkdir(parents=True,exist_ok=True);c['未来导出目录']=str(folder.relative_to(P));center,dims=old.bbox([o for o in out.objects if o.type=='MESH'])
 rec={'package_id':slug,'collection':c.name,'parent_collection':next(p.name for p in bpy.data.collections if c.name in p.children),'source_collection':sc.name,'output_collection':out.name,'source_blend':str(OUT.relative_to(P)),'version':'v021','objects':[o.name for o in out.objects],'triangles_before':before[c.name]['triangles'],'triangles_after':triangles(out.objects),'center':center,'dimensions':dims,'local_origin':[center[0],center[1],center[2]-dims[2]/2],'world_placement':placements[C.index(c)],'material_roles':[m.name for m in M],'exported':False,'runtime_integrated':False,'collision':'not_modified','fixed_display_attachments':True}
 (folder/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2));catalog.append(rec)
bpy.context.view_layer.update();after=json.loads(json.dumps({n:sig(bpy.data.objects[n]) for n in locked}));diff=[n for n in locked if locked[n]!=after[n]];assert not diff,diff[:20];assert [c.name for c in C]==names
(R/'locked_after.json').write_text(json.dumps(after,ensure_ascii=False));(R/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2));report={'locked_match':True,'locked_count':len(locked),'package_count':len(C),'names_unchanged':True,'triangles_before':sum(x['triangles_before'] for x in catalog),'triangles_after':sum(x['triangles_after'] for x in catalog),'material_count':len(bpy.data.materials),'status':'scope_pass_visual_pending'};(R/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT));print('RESULT',report)
