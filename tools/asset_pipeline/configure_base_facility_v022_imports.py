from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
data=json.loads((ROOT/'source/art/blender/base_facility_layout/export/v022/export_manifest.json').read_text())
for p in data['packages'].values():
 glb=ROOT/p['glb']; imp=Path(str(glb)+'.import')
 if not imp.exists(): raise RuntimeError(f'missing import contract: {imp}')
 text=imp.read_text()
 text=text.replace('import_script/path=""','import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"')
 text=text.replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=0')
 imp.write_text(text)
print(f'V022_IMPORT_CONTRACTS_CONFIGURED={len(data["packages"])}')
