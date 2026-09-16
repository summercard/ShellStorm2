import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Matrix

ROOT=Path('/Users/summercards/ShellStorm2')
SRC=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v002'
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v003';PKG=OUT/'component_packages_v003'
for p in [OUT,OUT/'renders',OUT/'qa',PKG]:p.mkdir(parents=True,exist_ok=True)
catalog=json.loads((SRC/'component_packages_v002/catalog.json').read_text());by={p['slug']:p for p in catalog}
keep={
 '01_服务器机柜':['north_00','north_03'],
 '02_工作终端':['west_desk','north_control','technician_chair'],
 '03_中央设备岛':['island_00','island_01'],
 '04_维修与机箱':['fault_tray_00','wall_service_00','wall_service_01','wall_service_02','equipment_case_00'],
 '05_门框与标识':['data_banner','east_portal'],
 '06_环境陈设':['planter_00'],
 '07_环境支持':['north_utilities','east_utilities','south_utilities','floor_cabling','fixed_papers'],
 '08_墙壁组件':['wall_standard_5m'],
 '09_地板组件':['floor_tile_r01_c01','floor_tile_r01_c02'],
}
selected=[s for rows in keep.values() for s in rows if s!='wall_standard_5m']

snap={}
for slug in selected:
 p=by[slug];root=bpy.data.objects[p['root_object']]
 meshes=[]
 for name in p['objects']:
  o=bpy.data.objects[name];m=o.data.copy();m.transform(o.matrix_local);meshes.append(m)
 snap[slug]={'meta':p,'meshes':meshes,'source_slug':slug}

def recenter(meshes):
 pts=[v.co for m in meshes for v in m.vertices];lo=Vector((min(v.x for v in pts),min(v.y for v in pts),min(v.z for v in pts)));hi=Vector((max(v.x for v in pts),max(v.y for v in pts),max(v.z for v in pts)))
 shift=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
 for m in meshes:m.transform(Matrix.Translation(shift))
 return hi-lo

# User requested item 04-1 to be square to the component axes.
meshes=snap['fault_tray_00']['meshes'];pts=[v.co for m in meshes for v in m.vertices]
mx=sum(v.x for v in pts)/len(pts);my=sum(v.y for v in pts)/len(pts);xx=sum((v.x-mx)**2 for v in pts);yy=sum((v.y-my)**2 for v in pts);xy=sum((v.x-mx)*(v.y-my) for v in pts)
angle=.5*math.atan2(2*xy,xx-yy)
for m in meshes:m.transform(Matrix.Rotation(-angle,4,'Z'))
recenter(meshes);snap['fault_tray_00']['straightened_yaw_degrees']=round(-math.degrees(angle),4)

def make_wall():
 m=bpy.data.meshes.new('标准墙_5x0.3x11.9_网格');x,y,z=2.5,.15,11.9
 verts=[(-x,-y,0),(x,-y,0),(x,y,0),(-x,y,0),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
 faces=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(4,0,3,7)];m.from_pydata(verts,[],faces);m.update()
 m.materials.append(bpy.data.materials['02_细腻哑光_青绿大面']);uv=m.uv_layers.new(name='PaletteUV');uv.active=True;uv.active_render=True
 coords=[(.912,.112),(.948,.112),(.948,.148),(.912,.148)]
 for p in m.polygons:
  for i,li in enumerate(p.loop_indices):uv.data[li].uv=coords[i%4]
 return m
wall_mesh=make_wall();snap['wall_standard_5m']={'meta':{'slug':'wall_standard_5m','name_zh':'战局通用标准墙 5×0.3×11.9m'},'meshes':[wall_mesh],'source_slug':'procedural_standard_wall'}
for d in snap.values():d['size']=recenter(d['meshes'])

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
scene=bpy.context.scene;scene.name='战局区块_通用组件库_v003'
root=bpy.data.collections.new('战局区块_通用组件库_中文资产管理');scene.collection.children.link(root)
srcroot=bpy.data.collections.new('01_制作组件_按设施拆分');root.children.link(srcroot);srcroot.hide_viewport=True;srcroot.hide_render=True
outroot=bpy.data.collections.new('02_游戏输出_独立资产包_v003');root.children.link(outroot)
show=bpy.data.collections.new('90_展示与验收_灯光相机');root.children.link(show)
manifest=[];group_cols={};labels={};row_heights=[];y=0
for gname,slugs in keep.items():
 og=bpy.data.collections.new(gname);outroot.children.link(og);group_cols[gname]=og;sg=bpy.data.collections.new(gname);srcroot.children.link(sg)
 x=0;rh=max(max(snap[s]['size'].y,1) for s in slugs)
 for slug in slugs:
  d=snap[slug];size=d['size'];x+=size.x/2+1.5;pos=Vector((x,y,0));pc=bpy.data.collections.new(slug+'_通用包');og.children.link(pc);sc=bpy.data.collections.new(slug+'_制作源');sg.children.link(sc)
  rt=bpy.data.objects.new('ROOT_'+slug+'_通用组件',None);rt.location=pos;rt['front_direction']='+Y';pc.objects.link(rt);names=[]
  for i,m in enumerate(d['meshes']):
   em=any(mat and mat.name=='04_柔和自发光_UI灯光' for mat in m.materials);role='自发光' if em else '主体'
   o=bpy.data.objects.new(f'{slug}_{role}_输出',m.copy());o.parent=rt;o.matrix_parent_inverse=Matrix.Identity(4);pc.objects.link(o);names.append(o.name)
   so=bpy.data.objects.new(f'AP_{slug}_{i:02d}_{role}_制作源',m.copy());sc.objects.link(so)
  item={'asset_id':'ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY','package_id':f'ENV-BATTLE-COMMON-{slug.upper().replace("_","-")}',
   'name_zh':d['meta'].get('name_zh') or d['meta'].get('blender_collection',slug),'slug':slug,'category':gname,'version':'v003','source_blend':'战局区块_通用组件库_v003.blend',
   'blender_collection':pc.name,'root_object':rt.name,'objects':names,'local_origin':[0,0,0],'showcase_position':[round(v,4) for v in pos],
   'bounds_size':[round(v,4) for v in size],'front_direction':'+Y','source_component':d['source_slug'],'straightened_yaw_degrees':d.get('straightened_yaw_degrees',0),
   'material_roles':[m.name for m in bpy.data.materials],'exported':False,'collision':'not_created'}
  manifest.append(item);pd=PKG/gname[:2]/slug;pd.mkdir(parents=True,exist_ok=True);(pd/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2));x+=size.x/2+1.5
 row_heights.append(rh);y-=rh+4.5

y=0
for (gname,slugs),rh in zip(keep.items(),row_heights):
 c=bpy.data.curves.new('标签_'+gname,'FONT');c.body=f'{gname}  {len(slugs)}件';c.size=.72;c.extrude=.012;o=bpy.data.objects.new('标签_'+gname,c);o.location=(-2.5,y,.05);show.objects.link(o);labels[gname]=o;y-=rh+4.5
bpy.context.view_layer.update()
def bounds(names):
 xs=[];ys=[]
 for n in names:
  for o in group_cols[n].all_objects:
   if o.type=='MESH':xs += [(o.matrix_world@Vector(c)).x for c in o.bound_box];ys += [(o.matrix_world@Vector(c)).y for c in o.bound_box]
 return (min(xs)+max(xs))/2,(min(ys)+max(ys))/2,max(xs)-min(xs),max(ys)-min(ys)
def track(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
camd=bpy.data.cameras.new('01_组件分类相机');cam=bpy.data.objects.new('01_组件分类相机',camd);camd.type='ORTHO';show.objects.link(cam);scene.camera=cam
lights=[]
for name,energy,size,color in [('主光',5600,24,(.56,.72,1)),('辅光',3800,20,(.25,.63,1)),('轮廓光',2600,18,(.18,.42,1))]:
 ld=bpy.data.lights.new(name,'AREA');ld.energy=energy;ld.shape='DISK';ld.size=size;ld.color=color;o=bpy.data.objects.new(name,ld);show.objects.link(o);lights.append(o)
w=scene.world or bpy.data.worlds.new('组件库世界');scene.world=w;w.use_nodes=True;bg=next(n for n in w.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.025,.045,.08,1);bg.inputs['Strength'].default_value=.8
scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.65
pages=[('01_设施组件总览.png',list(keep)[:6]),('02_环境支持组件总览.png',['07_环境支持']),('03_标准墙组件.png',['08_墙壁组件']),('04_地板组件.png',['09_地板组件'])]
for fname,names in pages:
 for n,c in group_cols.items():c.hide_render=n not in names
 for n,o in labels.items():o.hide_render=n not in names
 cx,cy,bw,bh=bounds(names)
 if fname=='04_地板组件.png':cam.location=(cx,cy,45);track(cam,(cx,cy,0));camd.ortho_scale=max(bw/1.5,bh)*1.55
 elif fname=='03_标准墙组件.png':cam.location=(cx,cy-30,6);track(cam,(cx,cy,6));camd.ortho_scale=14.5
 else:cam.location=(cx-22,cy-28,48);track(cam,(cx,cy,1));camd.ortho_scale=max(bw/1.5,bh)*1.9
 for light,loc in zip(lights,[(cx-12,cy-10,30),(cx+18,cy+7,22),(cx,cy+18,16)]):light.location=loc;track(light,(cx,cy,1))
 scene.render.filepath=str(OUT/'renders'/fname);bpy.ops.render.render(write_still=True)
for c in group_cols.values():c.hide_render=False
for o in labels.values():o.hide_render=False
cx,cy,bw,bh=bounds(list(keep)[:6]);cam.location=(cx-22,cy-28,48);track(cam,(cx,cy,1));camd.ortho_scale=max(bw/1.5,bh)*1.9;scene.render.filepath=str(OUT/'renders/01_设施组件总览.png')
(PKG/'catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2));tree=['战局区块通用组件库 v003']
for n,slugs in keep.items():tree.append(f'├─ {n} ({len(slugs)})');tree += [f'│  ├─ {s}' for s in slugs]
(PKG/'tree.txt').write_text('\n'.join(tree)+'\n')
removed={g:[p['slug'] for p in catalog if p['category']==g and p['slug'] not in slugs] for g,slugs in keep.items()}
report={'passed':len(manifest)==23,'package_count':len(manifest),'group_count':len(keep),'output_mesh_count':sum(len(p['objects']) for p in manifest),'kept_by_group':keep,
 'removed_by_group':removed,'wall_size_m':[5,.3,11.9],'wall_package_count':1,'floor_package_count':2,'fault_tray_straightened_yaw_degrees':snap['fault_tray_00']['straightened_yaw_degrees']}
(OUT/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));scene['asset_id']='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';scene['version']='v003';scene['package_count']=23
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'战局区块_通用组件库_v003.blend'),compress=True);print(json.dumps(report,ensure_ascii=False))
