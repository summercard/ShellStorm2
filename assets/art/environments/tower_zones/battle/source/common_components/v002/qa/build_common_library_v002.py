import bpy,json,hashlib,math,shutil
from pathlib import Path
from mathutils import Vector,Matrix

ROOT=Path('/Users/summercards/ShellStorm2')
SRC=ROOT/'assets/art/environments/tower_zones/battle/source/room_instances/main_room_02/v003'
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v002'
PKG=OUT/'component_packages_v002'
for p in [OUT,OUT/'renders',OUT/'qa',PKG]:p.mkdir(parents=True,exist_ok=True)
source_catalog=json.loads((SRC/'component_packages_v003/catalog.json').read_text())
catalog=[p for p in source_catalog if p['slug']!='floor_base']

def group_name(p):
 s=p['slug'];c=p['category']
 if c=='architecture':return '08_墙壁组件'
 if c=='floor':return '09_地板组件'
 if c=='support':return '07_环境支持'
 if s.startswith(('north_','east_')) and s.split('_')[-1].isdigit():return '01_服务器机柜'
 if s in {'west_desk','west_control','north_control','technician_chair'}:return '02_工作终端'
 if s.startswith('island_'):return '03_中央设备岛'
 if s.startswith(('fault_tray_','wall_service_','equipment_case_')):return '04_维修与机箱'
 if s in {'east_portal','west_portal','data_banner'}:return '05_门框与标识'
 if s.startswith('planter_'):return '06_环境陈设'
 raise RuntimeError('Unclassified '+s)

def normalizing_yaw(slug,category):
 if category=='floor':return None
 if slug.startswith('north_') or slug in {'north_control','north_utilities','data_banner','wall_north_01'}:return math.pi
 if slug.startswith('east_') or slug in {'east_utilities'} or slug.startswith('wall_east_'):return -math.pi/2
 if slug.startswith('west_') or slug in {'west_utilities'} or slug.startswith('wall_west_'):return math.pi/2
 return 0.0

def localized_mesh(obj,anchor,yaw):
 m=obj.data.copy();m.transform(Matrix.Rotation(yaw,4,'Z')@Matrix.Translation(-anchor)@obj.matrix_world)
 return m

def mesh_digest(mesh):
 uv=mesh.uv_layers.get('PaletteUV')
 payload={'v':[[round(x,5) for x in v.co] for v in mesh.vertices],
          'p':[(list(p.vertices),p.material_index) for p in mesh.polygons],
          'm':[m.name if m else None for m in mesh.materials],
          'uv':[[round(x,5) for x in d.uv] for d in uv.data] if uv else []}
 return hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def package_snap(p,yaw):
 obs=[bpy.data.objects[n] for n in p['objects']];pts=[]
 for o in obs:pts += [o.matrix_world@Vector(c) for c in o.bound_box]
 lo=Vector((min(v.x for v in pts),min(v.y for v in pts),min(v.z for v in pts)))
 hi=Vector((max(v.x for v in pts),max(v.y for v in pts),max(v.z for v in pts)))
 anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 meshes=[localized_mesh(o,anchor,yaw) for o in obs]
 pts2=[v.co for m in meshes for v in m.vertices]
 lo2=Vector((min(v.x for v in pts2),min(v.y for v in pts2),min(v.z for v in pts2)))
 hi2=Vector((max(v.x for v in pts2),max(v.y for v in pts2),max(v.z for v in pts2)))
 shift=Vector((-(lo2.x+hi2.x)/2,-(lo2.y+hi2.y)/2,-lo2.z))
 for m in meshes:m.transform(Matrix.Translation(shift))
 sig=hashlib.sha256('|'.join(sorted(mesh_digest(m) for m in meshes)).encode()).hexdigest()
 return {'meta':p,'meshes':meshes,'size':hi2-lo2,'yaw_deg':round(math.degrees(yaw))%360,'signature':sig}

# Normalize every front to +Y. Floor modules have no front and choose their canonical quarter-turn.
snaps=[]
for p in catalog:
 yaw=normalizing_yaw(p['slug'],p['category'])
 candidates=[package_snap(p,a) for a in (0,math.pi/2,math.pi,3*math.pi/2)] if yaw is None else [package_snap(p,yaw)]
 snaps.append(min(candidates,key=lambda d:d['signature']))

# Remove packages that become identical after orientation normalization.
unique=[];by_sig={};removed=[]
for d in snaps:
 if d['signature'] in by_sig:
  kept=by_sig[d['signature']];kept.setdefault('aliases',[]).append(d['meta']['slug'])
  removed.append({'removed':d['meta']['slug'],'kept':kept['meta']['slug'],'reason':'rotation_normalized_exact_duplicate'})
 else:
  d['aliases']=[];by_sig[d['signature']]=d;unique.append(d)

groups=[]
for name in ['01_服务器机柜','02_工作终端','03_中央设备岛','04_维修与机箱','05_门框与标识','06_环境陈设','07_环境支持','08_墙壁组件','09_地板组件']:
 rows=[d for d in unique if group_name(d['meta'])==name]
 if rows:groups.append((name,rows))

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
scene=bpy.context.scene;scene.name='战局区块_通用组件库_v002'
root=bpy.data.collections.new('战局区块_通用组件库_中文资产管理');scene.collection.children.link(root)
source_root=bpy.data.collections.new('01_制作组件_按设施拆分');root.children.link(source_root);source_root.hide_viewport=True;source_root.hide_render=True
output_root=bpy.data.collections.new('02_游戏输出_独立资产包_v002');root.children.link(output_root)
show=bpy.data.collections.new('90_展示与验收_灯光相机');root.children.link(show)
manifest=[];group_cols={};labels={};row_heights=[];y=0.0
for gname,items in groups:
 outg=bpy.data.collections.new(gname);output_root.children.link(outg);group_cols[gname]=outg
 srcg=bpy.data.collections.new(gname);source_root.children.link(srcg)
 x=0.0;max_depth=max(max(d['size'].y,1.0) for d in items);is_floor_grid=gname=='09_地板组件'
 if is_floor_grid:
  cols=6;cell_w=max(d['size'].x for d in items)+1.4;cell_h=max_depth+1.4;rh=(math.ceil(len(items)/cols)-1)*cell_h+max_depth
 else:rh=max_depth
 for item_index,d in enumerate(items):
  p=d['meta'];slug=p['slug'];size=d['size']
  if is_floor_grid:
   col=item_index%cols;row=item_index//cols;pos=Vector((1.25+col*cell_w+size.x/2,y-row*cell_h,0))
  else:
   x+=size.x/2+1.25;pos=Vector((x,y,0))
  pkg=bpy.data.collections.new(f'{slug}_通用包');outg.children.link(pkg)
  spkg=bpy.data.collections.new(f'{slug}_制作源');srcg.children.link(spkg)
  rt=bpy.data.objects.new(f'ROOT_{slug}_通用组件',None);rt.location=pos;rt['front_direction']='+Y';pkg.objects.link(rt)
  names=[]
  for idx,m in enumerate(d['meshes']):
   emissive=any(mat and mat.name=='04_柔和自发光_UI灯光' for mat in m.materials)
   role='自发光' if emissive else '主体'
   o=bpy.data.objects.new(f'{slug}_{role}_输出',m.copy());o.parent=rt;o.matrix_parent_inverse=Matrix.Identity(4);pkg.objects.link(o);names.append(o.name)
   so=bpy.data.objects.new(f'AP_{slug}_{idx:02d}_{role}_制作源',m.copy());spkg.objects.link(so)
  item={'asset_id':'ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY','package_id':f'ENV-BATTLE-COMMON-{slug.upper().replace("_","-")}',
        'name_zh':p.get('name_zh') or p['blender_collection'],'slug':slug,'category':gname,'version':'v002',
        'source_blend':'战局区块_通用组件库_v002.blend','blender_collection':pkg.name,'root_object':rt.name,'objects':names,
        'local_origin':[0,0,0],'showcase_position':[round(v,4) for v in pos],'bounds_size':[round(v,4) for v in size],
        'front_direction':'+Y','normalization_yaw_degrees':d['yaw_deg'],'geometry_signature':d['signature'],
        'deduplicated_source_aliases':d['aliases'],'material_roles':[m.name for m in bpy.data.materials],
        'exported':False,'collision':'not_created','source_room_package':slug}
  manifest.append(item);pdir=PKG/gname[:2]/slug;pdir.mkdir(parents=True,exist_ok=True);(pdir/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2))
  if not is_floor_grid:x+=size.x/2+1.25
 row_heights.append(rh);y-=rh+5.0

y=0.0
for (gname,items),rh in zip(groups,row_heights):
 c=bpy.data.curves.new('标签_'+gname,'FONT');c.body=f'{gname}  {len(items)}件';c.align_x='LEFT';c.size=.72;c.extrude=.012
 o=bpy.data.objects.new('标签_'+gname,c);o.location=(-2.5,y,.05);show.objects.link(o);labels[gname]=o;y-=rh+5.0
bpy.context.view_layer.update()

def bounds(names):
 xs=[];ys=[]
 for n in names:
  for o in group_cols[n].all_objects:
   if o.type=='MESH':
    xs += [(o.matrix_world@Vector(c)).x for c in o.bound_box];ys += [(o.matrix_world@Vector(c)).y for c in o.bound_box]
 return (min(xs)+max(xs))/2,(min(ys)+max(ys))/2,max(xs)-min(xs),max(ys)-min(ys)
def track(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
camd=bpy.data.cameras.new('01_组件分类相机');cam=bpy.data.objects.new('01_组件分类相机',camd);camd.type='ORTHO';show.objects.link(cam);scene.camera=cam
light_objects=[]
for name,loc,energy,size,color in [('主光',(-15,-10,38),5600,24,(.56,.72,1)),('辅光',(25,8,26),3800,20,(.25,.63,1)),('轮廓光',(0,25,20),2600,18,(.18,.42,1))]:
 ld=bpy.data.lights.new(name,'AREA');ld.energy=energy;ld.shape='DISK';ld.size=size;ld.color=color;o=bpy.data.objects.new(name,ld);o.location=loc;show.objects.link(o);track(o,(0,-20,1))
 light_objects.append(o)
w=scene.world or bpy.data.worlds.new('组件库世界');scene.world=w;w.use_nodes=True;bg=next(n for n in w.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.025,.045,.08,1);bg.inputs['Strength'].default_value=.8
scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.55

pages=[('01_设施组件总览.png',[n for n,_ in groups[:6]]),('02_环境支持组件总览.png',['07_环境支持']),('03_墙壁组件总览.png',['08_墙壁组件']),('04_地板组件总览.png',['09_地板组件'])]
camera_states={}
for fname,names in pages:
 for n,c in group_cols.items():c.hide_render=n not in names
 for n,o in labels.items():o.hide_render=n not in names
 cx,cy,bw,bh=bounds(names)
 if fname=='04_地板组件总览.png':cam.location=(cx,cy,85);track(cam,(cx,cy,0));camd.ortho_scale=max(bw/1.5,bh)*1.38;scene.view_settings.exposure=.85
 elif fname=='03_墙壁组件总览.png':cam.location=(cx-38,cy-46,88);track(cam,(cx,cy,1));camd.ortho_scale=max(bw/1.5,bh)*2.15;scene.view_settings.exposure=1.15
 else:cam.location=(cx-38,cy-46,88);track(cam,(cx,cy,1));camd.ortho_scale=max(bw/1.5,bh)*1.95;scene.view_settings.exposure=.55
 for light,loc in zip(light_objects,[(cx-15,cy-12,38),(cx+25,cy+8,28),(cx,cy+25,20)]):light.location=loc;track(light,(cx,cy,1))
 camera_states[fname]=([round(v,4) for v in cam.location],[round(v,6) for v in cam.rotation_euler],round(camd.ortho_scale,4))
 scene.render.filepath=str(OUT/'renders'/fname);bpy.ops.render.render(write_still=True)
scene.view_settings.exposure=.55
for c in group_cols.values():c.hide_render=False
for o in labels.values():o.hide_render=False
cx,cy,bw,bh=bounds([n for n,_ in groups[:6]]);cam.location=(cx-38,cy-46,88);track(cam,(cx,cy,1));camd.ortho_scale=max(bw/1.5,bh)*1.95;scene.render.filepath=str(OUT/'renders/01_设施组件总览.png')

(PKG/'catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
(PKG/'deduplication_report.json').write_text(json.dumps({'source_package_count':len(source_catalog),'excluded_room_specific_packages':['floor_base'],'candidate_package_count':len(catalog),'unique_package_count':len(unique),'removed_duplicates':removed},ensure_ascii=False,indent=2))
tree=['战局区块通用组件库 v002']
for n,items in groups:tree.append(f'├─ {n} ({len(items)})');tree += [f'│  ├─ {d["meta"]["slug"]}' for d in items]
(PKG/'tree.txt').write_text('\n'.join(tree)+'\n')
report={'passed':len(manifest)==len(unique) and len({p['geometry_signature'] for p in manifest})==len(manifest),'source_package_count':len(source_catalog),'excluded_room_specific_packages':['floor_base'],'candidate_package_count':len(catalog),'package_count':len(manifest),
        'removed_duplicate_count':len(removed),'removed_duplicates':removed,'group_count':len(groups),'output_mesh_count':sum(len(p['objects']) for p in manifest),
        'wall_package_count':sum(p['category']=='08_墙壁组件' for p in manifest),'floor_package_count':sum(p['category']=='09_地板组件' for p in manifest),
        'front_direction':'+Y','camera_pages':camera_states,'source_blend':str(SRC/'env_battle_l01_main_02_data_room_layout_source_v003.blend')}
(OUT/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
scene['asset_id']='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';scene['version']='v002';scene['package_count']=len(manifest);scene['deduplicated_source_count']=len(removed)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'战局区块_通用组件库_v002.blend'),compress=True)
print(json.dumps(report,ensure_ascii=False))
