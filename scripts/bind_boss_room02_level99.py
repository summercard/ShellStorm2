"""Read-only audit of the formal level99 Boss02 binding. Layout ownership is TSCN."""
import json
from pathlib import Path
R=Path(__file__).resolve().parents[1]
p=R/'art_source/design/whitebox/tower_zones/99/v001/data/floors/floor_00.json'
rooms={r['key']:r for r in json.loads(p.read_text('utf8'))['rooms']}
assert rooms['entry']['center_m']==[2.5,2.5]
assert rooms['boss']['center_m']==[2.5,-95]
assert rooms['boss']['floor_offset_m']==-12
assert rooms['boss']['connection_ports'][0]['outward']==[0,1]
assert rooms['boss']['connection_ports'][0]['height_m']==12
assert (R/'assets/art/environments/tower_zones/expedition/runtime/room_instances/99/f00_boss_static_layout.tscn').is_file()
print('LEVEL99_BOSS02_FORMAL_BINDING_OK; existing TSCN preserved')
