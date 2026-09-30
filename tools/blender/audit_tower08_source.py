"""Independent disk-open QA for Tower 8. No source or runtime modification."""
import bpy, json, math, hashlib
from pathlib import Path
from mathutils import Vector
from collections import Counter
P=Path(bpy.data.filepath).parent
catalog=json.loads((P/'catalog.json').read_text(encoding='utf8'))
game=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
src=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
obs=[o for o in game.all_objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
mn=[min(v[j] for v in points) for j in range(3)]; mx=[max(v[j] for v in points) for j in range(3)]
size=[mx[j]-mn[j] for j in range(3)]
packages=catalog['packages']; problems=[]; empty=[]; owners=Counter(); bad_boxes=[]
for item in packages:
 c=bpy.data.collections.get(item['collection'])
 if not c or not len(c.objects): empty.append(item['slug']); continue
 for o in c.objects: owners[o.name]+=1
 file=P/'component_packages'/item['category']/item['slug']/'asset_manifest.json'
 if not file.exists() or json.loads(file.read_text(encoding='utf8'))!=item: problems.append(item['slug'])
 p=[o.matrix_world@v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices]
 if p:
  amin=[min(v[j] for v in p) for j in range(3)]; amax=[max(v[j] for v in p) for j in range(3)]
  if any(abs(amin[j]-item['bounds_min'][j])>.003 or abs(amax[j]-item['bounds_max'][j])>.003 for j in range(3)): bad_boxes.append(item['slug'])
used_cells=Counter(); forbidden_gray=0; triangle_count=0; actual_white=0
image=next(i for i in bpy.data.images if i.source=='FILE' and '设施低亮' in i.name)
pixels=image.pixels[:]; iw,ih=image.size
for o in obs:
 o.data.calc_loop_triangles(); triangle_count+=len(o.data.loop_triangles)
 uv=o.data.uv_layers['PaletteUV']
 for face in o.data.polygons:
  co=uv.data[face.loop_start].uv
  col=min(9,int(co.x*10)); row=min(9,int((1-co.y)*10)); used_cells[(col,row)]+=1
  if col==9 and row in (8,9): forbidden_gray+=1
  x=min(iw-1,int(co.x*iw)); y=min(ih-1,int(co.y*ih)); rgb=pixels[(y*iw+x)*4:(y*iw+x)*4+3]
  if min(rgb)>.95: actual_white+=1
checks=dict(width_50m=abs(size[0]-50)<.003,depth_34m=abs(size[1]-34)<.003,height_96m=abs(size[2]-96)<.003,base_z_zero=abs(mn[2])<.0001,xy_centered=abs(mx[0]+mn[0])<.003 and abs(mx[1]+mn[1])<.003,materials_exactly_four=len(bpy.data.materials)==4,source_hidden=src.hide_viewport and src.hide_render,output_visible=not game.hide_render and not game.hide_viewport,packages_nonempty=not empty,one_output_owner=all(owners[o.name]==1 for o in obs),manifest_match=not problems,package_bounds_match=not bad_boxes,no_bright_white_gray=forbidden_gray==0,no_pure_white=actual_white==0,external_unpacked_palette=image.packed_file is None,no_collision_or_runtime_scripts=not any(o.type=='ARMATURE' for o in obs),reference_cameras_six=len([o for o in bpy.context.scene.objects if o.type=='CAMERA'])==6)
report=dict(passed=all(checks.values()),checks=checks,asset_id=catalog['asset_id'],source_blend=bpy.data.filepath,bounds_min=mn,bounds_max=mx,dimensions_m=size,package_count=len(packages),category_counts=dict(Counter(x['category'] for x in packages)),output_mesh_count=len(obs),source_mesh_count=len([o for o in src.all_objects if o.type=='MESH']),editable_font_count=len([o for o in src.all_objects if o.type=='FONT']),triangles=triangle_count,polygons=sum(len(o.data.polygons) for o in obs),vertices=sum(len(o.data.vertices) for o in obs),material_count=len(bpy.data.materials),used_palette_cells=[dict(column=c+1,row=r+1,faces=n) for (c,r),n in sorted(used_cells.items())],empty_packages=empty,manifest_errors=problems,bounds_errors=bad_boxes,forbidden_gray_faces=forbidden_gray,pure_white_faces=actual_white,source_sha256=hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),runtime_status='未导出；未接入；无碰撞；未做LOD',scope_lock='新建独立塔8源目录；没有修改已有塔楼、公共色盘、账本或运行时',scale_assumptions=catalog['scale_basis'])
(P/'qa/source_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(0 if report['passed'] else 1)
