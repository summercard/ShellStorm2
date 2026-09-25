from pathlib import Path
import subprocess,json
p=Path(__file__).resolve().parent
exe='D:/Program Files/Blender Foundation/Blender 4.5/blender.exe'
blend=p/'通道桥房间种类_工字型_30x60m_v002.blend'
assert blend.stat().st_mtime >= (p/'build_bridge_room_v002.py').stat().st_mtime,'Source still being built; do not use stale source'
base=[exe,'--factory-startup','--background',str(blend),'--python-exit-code','1']
for mode in ['full','lower','upper','top','complete']:
    with (p/('render_'+mode+'.log')).open('wb') as f:
        r=subprocess.run(base+['--python',str(p/'render_saved.py'),'--',mode],stdout=f,stderr=subprocess.STDOUT)
    assert r.returncode==0,(mode,r.returncode)
    print('RENDER_PASS',mode,flush=True)
root=p.parents[8]
validator=Path.home()/'.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py'
with (p/'validation.log').open('wb') as f:
    r=subprocess.run(base+['--python',str(validator),'--','--max-materials','4','--shared-palette',str(root/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(p/'validator_report.json')],stdout=f,stderr=subprocess.STDOUT)
assert r.returncode==0,r.returncode
v=json.loads((p/'validator_report.json').read_text(encoding='utf-8')); assert v['passed']
print('VALIDATION_PASS',v['output_mesh_count'],v['polygon_count'],v['valid_island_polygon_count'],flush=True)
