"""Raise only the circular roof by one floor; immutable parent and lower building."""
import bpy,sys,json,math,hashlib,shutil
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import tower04_court_common as H
from tower04_lower_structure_common import object_signature
R=H.R;OLD=R/'assets/art/environments/open_world/source/tower_04/v009';OUT=OLD.parent/'v010'
BLEND=OUT/'塔4_圆形屋面升层与旋转楼梯_v010.blend'
assert not BLEND.exists(),'Never overwrite an existing version'
for d in ('qa','previews','component_packages','references'):(OUT/d).mkdir(parents=True,exist_ok=True)
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'));parent=R/meta['source_blend']
bpy.ops.wm.open_mainfile(filepath=str(parent));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;H.setup_materials()
cx,cy=-56.52,-5.16;rx,ry=16.5,12.5
movable={p['slug'] for p in meta['packages'] if p['slug'].startswith(('oval_roof','overgrown_oval_edge'))}
locked={o.name:object_signature(o) for o in bpy.data.objects if o.get('package_id','').split('/')[-1] not in movable}
(OUT/'qa/locked_before.json').write_text(json.dumps(locked,ensure_ascii=False),encoding='utf8')
for p in meta['packages']:
 if p['slug'] in movable:
  for key in ('collection','source_collection'):
   for o in bpy.data.collections[p[key]].objects:o.location.z+=5
  for key in ('world_position','bounds_min','bounds_max'):p[key][2]+=5
  p['component_revision']='v010'
 p['source_blend']=BLEND.relative_to(R).as_posix();p['version']='v010'
root=H.coll('塔4_升层与旋梯_v010',sc.collection);src=H.coll('01_升层制作源',root);src.hide_render=True;src.hide_viewport=True
out=H.coll('02_升层独立组件输出',root)
new=[]
def finish(p):
 m,origin,dims=H.mesh_of(p);c=H.coll(p.name+'_资产包',out);s=H.coll(p.name+'_制作源',src)
 o=bpy.data.objects.new(p.name,m);c.objects.link(o);o.location=origin;o['package_id']='tower_04/'+p.slug;o['asset_id']=meta['asset_id'];o['version']='v010';o['component_definition']=p.definition
 so=o.copy();so.data=m.copy();s.objects.link(so)
 info=dict(asset_id=meta['asset_id'],package_id=o['package_id'],slug=p.slug,display_name=p.name,category=p.category,version='v010',component_revision='v010',source_blend=BLEND.relative_to(R).as_posix(),collection=c.name,source_collection=s.name,objects=[o.name],root_object=o.name,world_position=list(origin),local_origin=[0,0,0],front_direction='-Y',dimensions=dims,bounds_min=[origin[j]-(dims[j]/2 if j<2 else 0) for j in range(3)],bounds_max=[origin[j]+(dims[j]/2 if j<2 else dims[j]) for j in range(3)],material_roles=H.NAMES,component_definition=p.definition,dependencies=[],exported=False,collision_status='not_authored',block_id='open_world',floor_range='25–30m',scene_design_docs=['docs/v0.1/design/tower04_ground_court.md'],asset_ledger='scenes::资产主表::'+meta['asset_id'])
 assert max(dims[:2])<8.01,(p.slug,dims)
 meta['packages'].append(info);new.append(info)

# Original roof at 25m becomes an occupied storey floor, built in local 6m slices.
sys.path.insert(0,str(R.parent/'_scratch/tower04_geometry_libs'))
from shapely.geometry import Polygon,box
ellipse=Polygon([(cx+rx*math.cos(i*math.tau/128),cy+ry*math.sin(i*math.tau/128)) for i in range(128)])
for ix in range(-13,-6):
 for iy in range(-3,2):
  g=ellipse.intersection(box(ix*6,iy*6,(ix+1)*6,(iy+1)*6))
  if g.is_empty or g.area<.01:continue
  p=H.Part(f'raised_floor_{ix+13}_{iy+3}',f'升层下楼板_{ix+13}_{iy+3}','architecture',definition='raised_storey_floor')
  p.prism(list(g.exterior.coords)[:-1],24.65,25.055);finish(p)
# Twenty-four regular structural bays follow the ellipse; north doorway left open.
for i in range(24):
 a=i*math.tau/24;b=(i+1)*math.tau/24
 pts=[Vector((cx+(rx-.25)*math.cos(t),cy+(ry-.25)*math.sin(t),0)) for t in (a,b)]
 p=H.Part(f'raised_bay_{i:02d}',f'圆楼加层窗墙开间_{i:02d}','architecture',definition='raised_storey_window')
 for q in pts:p.rod((*q.xy,25.055),(*q.xy,29.8),.18,H.CREAM,1,12)
 p.rod((*pts[0].xy,29.62),(*pts[1].xy,29.62),.22,H.CREAM,1,10)
 # A 4m north portal provides stair access at both elevations.
 if i not in (5,6):
  for j in range(1,4):
   q=pts[0].lerp(pts[1],j/4);p.rod((*q.xy,25.2),(*q.xy,29.4),.035,H.STEEL,0,6)
  for z in (25.2,27.25,29.4):p.rod((*pts[0].xy,z),(*pts[1].xy,z),.04,H.STEEL,0,6)
  for j in (0,2):
   u=pts[0].lerp(pts[1],(j+.06)/4);v=pts[0].lerp(pts[1],(j+.94)/4)
   p.poly([(*u.xy,25.3),(*v.xy,25.3),(*v.xy,27.1),(*u.xy,27.1)],[(0,1,2,3)],(9,4),2)
 finish(p)
# One full turn, 28 equal risers, clear width 2.1m. Both portals face the round building.
sx,sy=cx,10.2;steps=28;low=25.055;high=30.055;inner=1.0;outer=3.1
for i in range(steps):
 a=-math.pi/2+i*math.tau/steps;b=-math.pi/2+(i+1)*math.tau/steps;z=low+5*(i+1)/steps
 p=H.Part(f'spiral_step_{i:02d}',f'旋梯踏步_{i+1:02d}','architecture',definition='spiral_stair_tread')
 coords=[(sx+r*math.cos(t),sy+r*math.sin(t)) for r,ts in [(inner,[a,b]),(outer,[b,a])] for t in ts]
 p.prism(coords,z-.15,z,H.LIGHT);p.rod((sx+inner*math.cos(a),sy+inner*math.sin(a),z-.23),(sx+outer*math.cos(a),sy+outer*math.sin(a),z-.23),.065,H.STEEL,0,6)
 finish(p)
 for side,r in [('inner',inner),('outer',outer)]:
  p=H.Part(f'spiral_rail_{side}_{i:02d}',f'旋梯{side}扶手_{i+1:02d}','support',definition='spiral_stair_rail')
  u=(sx+r*math.cos(a),sy+r*math.sin(a));v=(sx+r*math.cos(b),sy+r*math.sin(b))
  p.rod((*u,z),(*u,z+1.1),.038,H.STEEL,0,6)
  for h in (.55,1.1):p.rod((*u,z+h),(*v,z+5/steps+h),.038,H.STEEL,0,8)
  finish(p)
for k,z in enumerate((low,high)):
 p=H.Part(f'spiral_landing_{k}',f'旋梯对接平台_{k}','architecture',definition='spiral_stair_landing')
 p.box((sx,7.8,z-.125),(4.4,2.8,.25),H.LIGHT,1,.025)
 for x in (sx-2.2,sx+2.2):p.rod((x,6.4,z+1.1),(x,9.2,z+1.1),.04,H.STEEL,0,8)
 finish(p)
for z in (25.,27.5):
 p=H.Part('spiral_core_'+str(int(z*10)),'旋梯承重芯柱_'+str(z),'architecture',definition='spiral_stair_core');p.rod((sx,sy,z),(sx,sy,z+2.5),.27,H.CREAM,1,20);finish(p)
bpy.context.view_layer.update()
assert all(object_signature(bpy.data.objects[n])==v for n,v in locked.items()),'Unrelated building changed'
for p in meta['packages']:
 f=OUT/'component_packages'/p['category']/p['slug'];f.mkdir(parents=True,exist_ok=True);(f/'asset_manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf8')
meta.update(version='v010',source_blend=BLEND.relative_to(R).as_posix(),package_count=len(meta['packages']),component_definition_count=len({p['component_definition'] for p in meta['packages']}),round_roof_z=30,main_roof_z=25,source_status='awaiting_render_and_audit')
sc['version']='v010';sc['round_roof_z_m']=30.;sc['main_roof_z_m']=25.
cam=H.camera(sc,'CAM_旋梯接口',(-91,57,57),(cx,7,27),49,root)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
meta['source_sha256']=hashlib.sha256(BLEND.read_bytes()).hexdigest();(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
report=dict(passed=True,locked_objects=len(locked),locked_match=True,moved_packages=sorted(movable),new_packages=len(new),parent_sha256=hashlib.sha256(parent.read_bytes()).hexdigest(),source_sha256=meta['source_sha256'],stair=dict(bottom=low,top=high,risers=steps,riser_height=5/steps,clear_width=outer-inner,rail_height=1.1),new_max_xy=max(max(p['dimensions'][:2]) for p in new),runtime_verified=False)
(OUT/'qa/build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print('ROOF_SAVED',report,flush=True)
H.render(sc,cam,OUT/'previews/旋梯与升层.png')
H.render(sc,bpy.data.objects['CAM_参考全景'],OUT/'previews/参考全景.png',(1600,1000),32)
