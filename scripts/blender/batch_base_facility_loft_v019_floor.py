import bpy,json,re
from pathlib import Path
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_loft_v019';cat=json.loads((R/'catalog.json').read_text());rec=next(r for r in cat if r['package_id']=='loft_floor_finish');out=bpy.data.collections[rec['output_collection']];groups={}
for o in list(out.objects):
 match=re.search(r'R(\d+)_C',o.name)
 if match:groups.setdefault(int(match[1])//3,[]).append(o)
for k,obs in groups.items():
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name='116_木地板拼铺模块_R%02d到%02d_v019'%(k*3+1,k*3+3);o['source_plank_rows']=[k*3,k*3+2];o['component_type']='static_floor_finish_module';o.data.uv_layers.active_index=0;o.data.uv_layers['PaletteUV'].active_render=True
rec['objects']=[o.name for o in out.objects];rec['output_batching']='12 modules of 3 plank rows plus original-height substrate; 324 editable source planks preserved';(R/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2));(P/'source/art/blender/base_facility_layout/component_packages/v019/loft_floor_finish/asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2));bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('FLOOR_OUTPUTS',len(out.objects))
