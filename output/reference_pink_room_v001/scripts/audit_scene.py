import bpy,json,os,math
from mathutils import Vector
out=os.path.dirname(bpy.data.filepath)
root=next(c for c in bpy.context.scene.collection.children if c.name.startswith('粉色电竞卧室'))
report={'scope':'独立Blender设计稿还原；不包含Godot接入。','unit_scale_m_per_blender_unit':bpy.context.scene.unit_settings.scale_length,'reference_interior_mm':[350,300,200],'original_scene_backup':'原始空场景备份.blend','material_count':len(bpy.data.materials),'object_count':len(bpy.data.objects),'packages':[]}
for idx,c in enumerate(root.children):
 if c.name.startswith('90_'):continue
 objects=list(c.objects);pts=[o.matrix_world@Vector(v) for o in objects if o.type in {'MESH','CURVE'} for v in o.bound_box]
 lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 item={'package_id':'room_%02d'%idx,'name':c.name,'source_blend':'粉色电竞卧室_高还原_v001.blend','collection':c.name,'objects':[o.name for o in objects],'object_count':len(objects),'bbox_min_mm':[round(x*100,3) for x in lo],'bbox_max_mm':[round(x*100,3) for x in hi],'size_mm':[round((hi[i]-lo[i])*100,3) for i in range(3)],'editable_components':True,'runtime_exported':False,'purpose':'fixed_display_attachment' if idx>10 else 'reference_scene_asset'}
 directory=out+'/component_packages/'+item['package_id'];os.makedirs(directory,exist_ok=True)
 json.dump(item,open(directory+'/asset_manifest.json','w'),ensure_ascii=False,indent=2);report['packages'].append(item)
report['empty_packages']=[c.name for c in root.children if not len(c.objects)]
report['multiple_collection_objects']=[o.name for o in root.all_objects if len(o.users_collection)!=1]
report['non_finite_transforms']=[o.name for o in root.all_objects if any(not math.isfinite(v) for row in o.matrix_world for v in row)]
report['game_palette_validation']='独立参考图颜色制作源使用对象颜色与共享材质，非ShellStorm2公共色盘游戏输出；不能宣称运行时验收通过。'
report['geometry_counts']={'mesh_objects':sum(o.type=='MESH' for o in root.all_objects),'curve_objects':sum(o.type=='CURVE' for o in root.all_objects),'editable_vertices':sum(len(o.data.vertices) for o in root.all_objects if o.type=='MESH')}
report['scene_structure_passed']=not(report['empty_packages'] or report['multiple_collection_objects'] or report['non_finite_transforms'])
json.dump(report,open(out+'/场景结构验收.json','w'),ensure_ascii=False,indent=2)
open(out+'/component_packages/catalog.json','w').write(json.dumps(report['packages'],ensure_ascii=False,indent=2))
open(out+'/component_packages/tree.txt','w').write('\n'.join(p['package_id']+' / '+p['name']+' / '+str(p['object_count'])+' objects' for p in report['packages']))
print(json.dumps({k:v for k,v in report.items() if k!='packages'},ensure_ascii=False))
