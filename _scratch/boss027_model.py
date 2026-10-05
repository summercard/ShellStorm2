import bpy,json
from pathlib import Path
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v026.blend'))
for s in bpy.data.scenes:s['asset_version']='v027'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v027.blend'))
p=B/'source/rig_contract_v026.json';m=json.loads(p.read_text());m['version']='v027';m['preview_vfx_note']='Separate preview-only dizzy orbit, one-frame hit flash and cable-bone electric current. No runtime export.';(B/'source/rig_contract_v027.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
