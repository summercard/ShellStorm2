import bpy, json, math
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path('/Users/summercards/ShellStorm2')
SRC=ROOT/'assets/art/environments/tower_zones/battle/source/room_instances/main_room_02/v003'
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/common_components/v001'
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'renders').mkdir(exist_ok=True)
(OUT/'component_packages_v001').mkdir(exist_ok=True)
catalog=json.loads((SRC/'component_packages_v003/catalog.json').read_text())
selected=[p for p in catalog if p['category'] in {'facilities','support'}]

groups=[
 ('01_服务器机柜',[f'north_{i:02d}' for i in range(8)]+[f'east_{i:02d}' for i in range(6)]),
 ('02_工作终端',['west_desk','west_control','north_control','technician_chair']),
 ('03_中央设备岛',[f'island_{i:02d}' for i in range(3)]),
 ('04_维修与机箱',[f'fault_tray_{i:02d}' for i in range(3)]+[f'wall_service_{i:02d}' for i in range(3)]+[f'equipment_case_{i:02d}' for i in range(4)]),
 ('05_门框与标识',['east_portal','west_portal','data_banner']),
 ('06_环境陈设',[f'planter_{i:02d}' for i in range(3)]),
 ('07_环境支持',['north_utilities','east_utilities','south_utilities','west_utilities','floor_cabling','fixed_papers']),
]
by_slug={p['slug']:p for p in selected}
assert set(by_slug)=={s for _,slugs in groups for s in slugs}

def world_mesh_copy(obj,anchor):
    mesh=obj.data.copy()
    mesh.transform(Matrix.Translation(-anchor) @ obj.matrix_world)
    return mesh

snap={}
for p in selected:
    obs=[bpy.data.objects[n] for n in p['objects']]
    pts=[]
    for o in obs:
        pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo=Vector((min(v.x for v in pts),min(v.y for v in pts),min(v.z for v in pts)))
    hi=Vector((max(v.x for v in pts),max(v.y for v in pts),max(v.z for v in pts)))
    anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    snap[p['slug']]={'meta':p,'anchor':anchor,'size':hi-lo,
        'objects':[(o.name,world_mesh_copy(o,anchor),o.hide_render) for o in obs]}

# fresh scene, retain shared materials/images referenced by copied meshes
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections): bpy.data.collections.remove(c)
scene=bpy.context.scene
scene.name='战局区块_通用组件库_v001'
root=bpy.data.collections.new('战局区块_通用组件库_中文资产管理');scene.collection.children.link(root)
source_root=bpy.data.collections.new('01_制作组件_按设施拆分');root.children.link(source_root)
output_root=bpy.data.collections.new('02_游戏输出_独立资产包_v001');root.children.link(output_root)
show=bpy.data.collections.new('90_展示与验收_灯光相机');root.children.link(show)
source_root.hide_viewport=True;source_root.hide_render=True

output_manifest=[];group_collections={};label_objects={}
y=0.0
row_heights=[]
for gi,(gname,slugs) in enumerate(groups):
    group=bpy.data.collections.new(gname);output_root.children.link(group);group_collections[gname]=group
    src_group=bpy.data.collections.new(gname);source_root.children.link(src_group)
    x=0.0;row_h=max(snap[s]['size'].y for s in slugs)
    for slug in slugs:
        d=snap[slug];size=d['size']; x+=size.x/2+1.15
        position=Vector((x,y,0))
        pkg=bpy.data.collections.new(f"{d['meta']['blender_collection']}_通用包");group.children.link(pkg)
        srcpkg=bpy.data.collections.new(f"{d['meta']['blender_collection']}_制作源");src_group.children.link(srcpkg)
        rootobj=bpy.data.objects.new(f'ROOT_{slug}_通用组件',None);rootobj.location=position;pkg.objects.link(rootobj)
        names=[]
        for idx,(oldname,mesh,hide_render) in enumerate(d['objects']):
            obj=bpy.data.objects.new(f'{slug}_{"主体" if idx==0 else "自发光"}_输出',mesh.copy())
            obj.parent=rootobj;obj.matrix_parent_inverse=Matrix.Identity(4);pkg.objects.link(obj);names.append(obj.name)
            src=bpy.data.objects.new(f'AP_{slug}_{idx:02d}_{"主体" if idx==0 else "自发光"}_制作源',mesh.copy());srcpkg.objects.link(src)
        item={
          'asset_id':'ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY','package_id':f'ENV-BATTLE-COMMON-{slug.upper().replace("_","-")}',
          'name_zh':d['meta'].get('name_zh') or d['meta']['blender_collection'],'slug':slug,'category':gname,'version':'v001',
          'source_blend':'战局区块_通用组件库_v001.blend','blender_collection':pkg.name,'root_object':rootobj.name,
          'objects':names,'local_origin':[0,0,0],'showcase_position':[round(v,4) for v in position],
          'bounds_size':[round(v,4) for v in size],'front_direction':'+Y','material_roles':[m.name for m in bpy.data.materials],
          'exported':False,'collision':'not_created','source_room_package':slug
        }
        output_manifest.append(item)
        pdir=OUT/'component_packages_v001'/gname[:2]/slug;pdir.mkdir(parents=True,exist_ok=True)
        (pdir/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2))
        x+=size.x/2+1.15
    row_heights.append(row_h);y-=row_h+4.8

# Labels are presentation objects and not part of output packages.
y=0.0
for (gname,slugs),rh in zip(groups,row_heights):
    curve=bpy.data.curves.new('标签_'+gname,'FONT');curve.body=gname;curve.align_x='LEFT';curve.size=.75;curve.extrude=.015
    obj=bpy.data.objects.new('标签_'+gname,curve);obj.location=(-2.2,y,0.06);obj.rotation_euler=(0,0,0);show.objects.link(obj);label_objects[gname]=obj
    y-=rh+4.8

# camera/lights
bpy.context.view_layer.update()
def bounds_for(collection_names):
    xs=[];ys=[]
    for name in collection_names:
      for o in group_collections[name].all_objects:
        if o.type=='MESH':
          xs.extend((o.matrix_world@Vector(c)).x for c in o.bound_box);ys.extend((o.matrix_world@Vector(c)).y for c in o.bound_box)
    return (min(xs)+max(xs))/2,(min(ys)+max(ys))/2,max(xs)-min(xs),max(ys)-min(ys)
main_names=[g[0] for g in groups[:6]]
cx,cy,width,height=bounds_for(main_names)
camd=bpy.data.cameras.new('01_组件总览相机');cam=bpy.data.objects.new('01_组件总览相机',camd);show.objects.link(cam)
camd.type='ORTHO';camd.ortho_scale=max(width/1.5,height)*2.45;cam.location=(cx-40,cy-48,92)
def track(o,t): o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
track(cam,(cx,cy,1.5));scene.camera=cam
for name,loc,energy,size,color in [('主光',(cx-15,cy-10,35),5200,22,(0.56,0.72,1)),('辅光',(cx+24,cy+6,24),3600,18,(0.25,0.63,1)),('轮廓光',(cx,cy+25,18),2400,16,(0.18,0.42,1))]:
    ld=bpy.data.lights.new(name,'AREA');ld.energy=energy;ld.shape='DISK';ld.size=size;ld.color=color
    ob=bpy.data.objects.new(name,ld);ob.location=loc;track(ob,(cx,cy,1));show.objects.link(ob)
world=scene.world or bpy.data.worlds.new('组件库世界');scene.world=world;world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(0.025,0.045,0.08,1);bg.inputs['Strength'].default_value=.48
scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.5
scene.render.filepath=str(OUT/'renders/01_设施组件总览.png')

(OUT/'component_packages_v001/catalog.json').write_text(json.dumps(output_manifest,ensure_ascii=False,indent=2))
tree=['战局区块通用组件库 v001']
for g,slugs in groups:
    tree.append(f'├─ {g} ({len(slugs)})')
    tree += [f'│  ├─ {s}' for s in slugs]
(OUT/'component_packages_v001/tree.txt').write_text('\n'.join(tree)+'\n')
report={'passed':len(output_manifest)==43 and all(len(p['objects']) in (1,2) for p in output_manifest),
        'package_count':len(output_manifest),'group_count':len(groups),'output_mesh_count':sum(len(p['objects']) for p in output_manifest),
        'source_mesh_count':sum(len(p['objects']) for p in output_manifest),'empty_packages':[],
        'source_blend':str(SRC/'env_battle_l01_main_02_data_room_layout_source_v003.blend')}
(OUT/'qa').mkdir(exist_ok=True);(OUT/'qa/task_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
scene['asset_id']='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';scene['package_count']=43;scene['source_room']='ENV-BATTLE-L01-ROOM-MAIN-02'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'战局区块_通用组件库_v001.blend'),compress=True)
group_collections['07_环境支持'].hide_render=True;label_objects['07_环境支持'].hide_render=True
main_cam_location=cam.location.copy();main_cam_rotation=cam.rotation_euler.copy();main_cam_scale=camd.ortho_scale
bpy.ops.render.render(write_still=True)
# The long wall utility/cabling modules receive a dedicated overview so they do not shrink all facilities.
for name,col in group_collections.items(): col.hide_render=(name!='07_环境支持')
for name,obj in label_objects.items(): obj.hide_render=(name!='07_环境支持')
cx,cy,width,height=bounds_for(['07_环境支持']);cam.location=(cx-48,cy-58,65);track(cam,(cx,cy,1.0));camd.ortho_scale=max(width/1.5,height)*1.42
scene.render.filepath=str(OUT/'renders/02_环境支持组件总览.png');bpy.ops.render.render(write_still=True)
cam.location=main_cam_location;cam.rotation_euler=main_cam_rotation;camd.ortho_scale=main_cam_scale;scene.render.filepath=str(OUT/'renders/01_设施组件总览.png')
for col in group_collections.values(): col.hide_render=False
for obj in label_objects.values(): obj.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'战局区块_通用组件库_v001.blend'),compress=True)
print(json.dumps(report,ensure_ascii=False))
