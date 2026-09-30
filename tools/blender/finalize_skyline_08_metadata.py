"""Finalize source metadata and embed editable font, while keeping palette external."""
import bpy,json
from pathlib import Path
R=Path(__file__).resolve().parents[2]; folder=Path(bpy.data.filepath).parent
doc='docs/v0.1/development/2026-09-30_skyline08_building_source.md'
designs=[doc,'docs/v0.1/10.1_3D场景美术生产流程.md']
idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf8'))
domain=next(x for x in idx['domains'] if x['key']=='scenes')
ledger=(Path(idx['ledger_dir'])/domain['file']).as_posix()
catalog=json.loads((folder/'catalog.json').read_text(encoding='utf8'))
catalog['scene_design_docs']=designs; catalog['asset_ledger']=ledger+'#资产主表::ENV-OPENWORLD-SKYLINE08'
catalog['visual_review']='reference camera, top, equipment, billboard and back reviewed; stylized palette wear and no photorealistic texture'
for item in catalog['packages']:
 item['scene_design_docs']=designs; item['asset_ledger']=catalog['asset_ledger']
 p=folder/'component_packages'/item['category']/item['slug']/'asset_manifest.json'
 p.write_text(json.dumps(item,ensure_ascii=False,indent=2),encoding='utf8')
(folder/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf8')
bpy.context.scene['scene_design_docs']=json.dumps(designs,ensure_ascii=False)
bpy.context.scene['asset_ledger']=catalog['asset_ledger']
bpy.context.scene['source_status']='Blender源已完成；未导出GLB或接入Godot'
for obj in bpy.context.scene.objects:
 if obj.get('asset_id'):
  obj['block_id']='open_world'; obj['floor_range']='1F–8F＋天台'; obj['asset_ledger']=catalog['asset_ledger']
for font in bpy.data.fonts:
 if font.filepath and font.filepath!='<builtin>' and not font.packed_file: font.pack()
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('SKYLINE08_METADATA_FINALIZED')
