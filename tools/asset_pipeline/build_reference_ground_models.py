"""Derive 100–200 triangle ground variants from the approved preview meshes."""
import bpy,bmesh,json,sys,hashlib,math,os,shutil,time
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tools/asset_pipeline')]
from workspace_paths import work_path
import build_reference_items_20261014 as author
OUT=work_path('items_reference_20261014/ground/report.json').parent
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reports=[]
for s in author.SPECS:
 slug,name,logical,aid,domain,*_=s
 folder=ROOT/'art_source/items_weapons'/domain/slug
 c=json.loads((folder/'asset_contract.json').read_text('utf8'));high=ROOT/c['source_blend'];before=digest(high)
 bpy.ops.wm.open_mainfile(filepath=str(high))
 output=bpy.data.collections['02_游戏输出_整合模型'];obj=next(o for o in output.objects if o.type=='MESH')
 high_points=[v.co.copy() for v in obj.data.vertices];obj.data.calc_loop_triangles();high_triangles=len(obj.data.loop_triangles)
 # Semantic budgets: reduce existing lathe rings rather than collapse caps into fragments.
 for old in list(output.objects):bpy.data.objects.remove(old,do_unlink=True)
 source_col=bpy.data.collections['01_制作组件_已统一材质'];source_col.hide_viewport=False
 bpy.ops.object.select_all(action='DESELECT')
 keep=[]
 plans={
 'battery_large':{'主蓝色圆筒':(8,2),'银色护圈':(6,2),'收肩金属罩':(6,2),'金色腰圈':(6,2),'顶部蓝色盖':(6,2),'侧黄色电芯':(4,2),'顶部黄提手':(0,16)},
 'battery_small':{'紫色电池壳':(10,2),'金色底环':(8,2),'银色顶盖':(8,2),'正极凸钮':(8,2)},
 'health_potion':{'粉色药液瓶身':(8,5),'浅色玻璃肩':(8,3),'金属旋盖':(6,2),'白色医疗十字':(0,0)},
 'bullet_standard':{'银色底口':(6,4),'银色弹底环':(6,2),'蓝色弹壳':(8,2),'银色弹颈圈':(6,2),'金色圆锥弹头':(8,4)},
 'big_mag':{'黑色后壳':(0,0),'浅蓝色主壳':(0,0),'提环侧壁':(0,0),'提环上梁':(0,0),'粉色前护板':(0,0),'上部黑色插舌':(0,0),'黑色底护块':(0,0),'银色侧供弹管':(4,2),'侧滑轨黑锁扣':(0,0),'锁扣金色按钮':(0,0)},
 'triple_muzzle':{'后部深色护框':(0,0),'粉色三叉主体':(0,0),'粉色枪管座':(5,2),'银色枪口':(5,4),'枪膛暗面':(5,2)},
 'rubber_stock':{'蓝色渐缩枪托':(0,0),'下方黑色支撑':(0,0),'前端深色连接座':(0,0),'粉色橡皮后托框':(0,110)},
 'scope':{'白色瞄具筒':(8,2),'后部黑色伸缩段':(6,2),'粉色端环':(6,2),'前镜筒蓝色外沿':(6,4),'青色凸透镜':(8,3),'黑色导轨夹具':(0,0),'顶部黑色调节钮':(6,2)}}
 seen={}
 for src in list(source_col.objects):
  label=src.name.split('_制作组件_')[-1].split('.')[0]
  if label not in plans[slug]:continue
  seen[label]=seen.get(label,0)+1
  if slug=='battery_large' and label=='银色护圈' and seen[label]>2:continue
  seg,levels=plans[slug][label]
  ob=src.copy();ob.data=src.data.copy();output.objects.link(ob);ob.parent=bpy.data.objects['ItemRoot']
  for mod in list(ob.modifiers):ob.modifiers.remove(mod)
  if seg:
   mesh=ob.data;vcount=len(mesh.vertices);oldseg=64 if label in ['粉色药液瓶身','浅色玻璃肩','金色圆锥弹头'] else 48
   rings=vcount//oldseg;assert vcount%oldseg==0,(label,vcount)
   is_tube=label in ['银色底口','银色枪口','前镜筒蓝色外沿']
   if is_tube:indices=[0,2,3,5] # inner back, outer back, outer front, inner front
   elif levels==2:indices=[0,rings-1]
   else:indices=sorted(set(round(i*(rings-1)/(levels-1)) for i in range(levels)))
   verts=[tuple(mesh.vertices[r*oldseg+round(i*oldseg/seg)%oldseg].co) for r in indices for i in range(seg)]
   faces=[(r*seg+i,r*seg+(i+1)%seg,(r+1)*seg+(i+1)%seg,(r+1)*seg+i) for r in range(len(indices)-1) for i in range(seg)]
   if is_tube:faces.extend(((len(indices)-1)*seg+i,(len(indices)-1)*seg+(i+1)%seg,(i+1)%seg,i) for i in range(seg))
   else:faces.extend([tuple(reversed(range(seg))),tuple(range((len(indices)-1)*seg,len(indices)*seg))])
   new=bpy.data.meshes.new(label+'_ground');new.from_pydata(verts,[],faces);new.update();new.materials.append(mesh.materials[0]);ob.data=new
   u=mesh.uv_layers.active.data[0].uv;layer=new.uv_layers.new(name='PaletteUV');layer.active_render=True
   for loop in layer.data:loop.uv=u
  elif levels:
   bpy.context.view_layer.objects.active=ob;ob.data.calc_loop_triangles();mod=ob.modifiers.new('轮廓减面','DECIMATE');mod.ratio=levels/len(ob.data.loop_triangles);mod.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  ob.select_set(True);keep.append(ob)
 bpy.context.view_layer.objects.active=keep[0];bpy.ops.object.join();obj=bpy.context.object
 source_col.hide_viewport=True
 original=obj.data.copy();original.calc_loop_triangles();count=len(original.loop_triangles)
 bm=bmesh.new();bm.from_mesh(original);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(original);bm.free()
 best=None
 for budget in [min(count,198),196,180,160,140,120,100,80,60,40,20,10,1]:
  obj.data=original.copy();bpy.context.view_layer.objects.active=obj
  mod=obj.modifiers.new('地面模型减面','DECIMATE');mod.decimate_type='COLLAPSE';mod.ratio=budget/count;mod.use_collapse_triangulate=True
  bpy.ops.object.modifier_apply(modifier=mod.name)
  obj.data.calc_loop_triangles();n=len(obj.data.loop_triangles)
  if 100<=n<=200:best=obj.data;break
 assert best is not None,(slug,n)
 # Restore exact envelope with baked vertex coordinates (root and object scales remain one).
 verts=obj.data.vertices;lo=Vector([min(v.co[i] for v in verts) for i in range(3)]);hi=Vector([max(v.co[i] for v in verts) for i in range(3)])
 srcpts=high_points
 slo=Vector([min(v[i] for v in srcpts) for i in range(3)]);shi=Vector([max(v[i] for v in srcpts) for i in range(3)])
 for v in verts:
  for i in range(3):v.co[i]=slo[i]+(v.co[i]-lo[i])/(hi[i]-lo[i])*(shi[i]-slo[i])
 uv=obj.data.uv_layers.active
 for p in obj.data.polygons:
  coords=[uv.data[i].uv.copy() for i in p.loop_indices]
  votes={}
  for u in coords:
   key=(min(9,max(0,int(u.x*10))),min(9,max(0,int(u.y*10))));votes[key]=votes.get(key,0)+1
  x,y=max(votes,key=votes.get)
  for k,li in enumerate(p.loop_indices):
   a=2*math.pi*k/len(p.loop_indices);uv.data[li].uv=((x+.5)/10+.023*math.cos(a),(y+.5)/10+.023*math.sin(a))
 obj.name=('itm' if domain=='props' else 'wpn')+'_'+slug+'_ground_主体'
 for o in list(bpy.data.collections['01_制作组件_已统一材质'].objects):bpy.data.objects.remove(o,do_unlink=True)
 # Keep an editable low mesh copy, never embed the high variant into the ground file.
 edit=obj.copy();edit.data=obj.data.copy();bpy.data.collections['01_制作组件_已统一材质'].objects.link(edit)
 ground=folder/'source'/high.name.replace('_source_','_ground_source_')
 scene=bpy.context.scene;scene['model_role']='ground';scene['derived_from']=c['source_blend'];scene['derived_sha256']=before;scene['face_budget']='100-200 triangles, evaluated output only'
 for image in bpy.data.images:
  if image.source=='FILE':image.filepath='//'+os.path.relpath(author.PAL,ground.parent).replace('\\','/')
 tmp=OUT/(slug+str(time.time_ns())+'.blend');bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(tmp),relative_remap=False);shutil.copyfile(tmp,ground)
 for image in bpy.data.images:
  if image.source=='FILE':image.filepath=str(author.PAL);image.reload()
 scene.render.filepath=str(OUT/(slug+'.png'));bpy.ops.render.render(write_still=True)
 assert digest(high)==before
 r={'asset_id':aid,'slug':slug,'preview_source':c['source_blend'],'preview_sha256':before,'ground_source':ground.relative_to(ROOT).as_posix(),'ground_sha256':digest(ground),'preview_triangles':high_triangles,'ground_polygons':len(obj.data.polygons),'ground_triangles':n,'root_scale':[1,1,1],'derived_by':'Existing source components: semantic detail removal, ring/profile subsampling and limited Decimate; palette islands repaired; high envelope restored','source_only':True}
 reports.append(r)
 (folder/'ground_manifest.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
 print('GROUND_MODEL_OK',slug,n,flush=True)
(OUT/'report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf8')




