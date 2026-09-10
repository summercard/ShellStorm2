"""Verify evaluated soles and flight in the saved v018 authoring bundle."""
import bpy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v018'
bpy.ops.wm.open_mainfile(filepath=str(PACKAGE / 'source/animation/chr_bunny01_animation_v018.blend'))
results = {}
for scene in bpy.data.scenes:
    state = scene.get('preview_clip')
    if state not in ('moving', 'armed_moving'):
        continue
    bpy.context.window.scene = scene
    shoes = [o for o in scene.objects if o.type == 'MESH' and o.get('component_id') in ('foot_l', 'foot_r')]
    assert len(shoes) == 2, [o.name for o in shoes]
    lowest = 1.0
    flight = 0
    for frame in range(1, scene.frame_end + 1):
        scene.frame_set(frame)
        dg = bpy.context.evaluated_depsgraph_get()
        soles = []
        for obj in shoes:
            evaluated = obj.evaluated_get(dg)
            mesh = evaluated.to_mesh()
            soles.append(min((evaluated.matrix_world @ v.co).z for v in mesh.vertices))
            evaluated.to_mesh_clear()
        lowest = min(lowest, *soles)
        flight += int(min(soles) > .001)
    assert lowest > -.00001, (state, lowest)
    assert flight > 0, (state, flight)
    results[state] = {'evaluated_sole_min_z': lowest, 'both_feet_airborne_frames': flight, 'sampled_frames': scene.frame_end}
report_path = ROOT / 'outputs/character_pipeline/v018/validation.json'
report = json.loads(report_path.read_text())
report['evaluated_shoe_ground_and_flight'] = results
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
ledger_path = PACKAGE / 'character_transfer_ledger_v018.json'
ledger = json.loads(ledger_path.read_text())
ledger['validation'] = report
ledger_path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2))
print('EVALUATED_SOLES_PASS', results)
