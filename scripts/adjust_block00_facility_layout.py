"""User-directed scene edits; keep source geometry and stable Prefabs unchanged."""
from pathlib import Path
import json,re,math,shutil
import numpy as np
R=Path(__file__).resolve().parents[1];B=R/'assets/art/environments/master_office_3d';O=R/'outputs/block00_story_rooms_20261009/layout_adjustment';O.mkdir(exist_ok=True)
office=B/'runtime/room_instances/master_office/master_office_facilities.tscn';lobby=B/'runtime/room_instances/lobby/lobby_facilities.tscn'
for p in [office,lobby]:
 assert not (O/p.name).exists(),'Adjustment already applied; inspect before rerun'
 shutil.copy2(p,O/p.name)
def transform(s,name,fn):
 pattern=r'(\[node name="'+re.escape(name)+r'"[^\n]*\]\ntransform = Transform3D\()([^)]*)(\))'
 match=re.search(pattern,s);assert match,name
 values=[float(x) for x in match[2].split(',')];new=fn(values)
 return s[:match.start(2)]+', '.join(f'{x:.7f}' for x in new)+s[match.end(2):]
s=office.read_text('utf8');pivot=np.array([-4.8300018,.105,.7])
for name in ['sofa_001','pillow_005','pillow_006','pillow_007','pillow_008','throw_009']:
 s=transform(s,name,lambda a:[x*.7 for x in a[:9]]+list(pivot+(np.array(a[9:])-pivot)*.7))
# Existing floor visual upper bound .083m; rug upper face .120m. Leave 8mm clearance.
s=transform(s,'rug_002',lambda a:a[:10]+[-.029]+a[11:])
s=s.replace('metadata/asset_version = "v001"','metadata/asset_version = "v002"',1);office.write_text(s,encoding='utf8')
m=json.loads((B/'source/env_block00_story_rooms/export/v001/import_manifest.json').read_text('utf8'));d=next(x for x in m['components'] if x['slug']=='constructivist_mural')
def rot(axis,t):
 c=math.cos(t);v=math.sin(t)
 return np.array([[1,0,0],[0,c,-v],[0,v,c]]) if axis==0 else np.array([[c,0,v],[0,1,0],[-v,0,c]]) if axis==1 else np.array([[c,-v,0],[v,c,0],[0,0,1]])
matrix=rot(1,math.pi)@rot(0,math.radians(22))@rot(2,math.radians(-6))
a=d['bounds_min'];b=d['bounds_max'];pts=[matrix@np.array([x,z,-y]) for x in [a[0],b[0]] for y in [a[1],b[1]] for z in [a[2],b[2]]]
pos=[0,.091-min(p[1] for p in pts),-4.7]
s=lobby.read_text('utf8');s=transform(s,'constructivist_mural_014',lambda old:list(matrix.T.flatten())+pos);s=s.replace('metadata/asset_version = "v001"','metadata/asset_version = "v002"',1);lobby.write_text(s,encoding='utf8')
(O/'delta.json').write_text(json.dumps({'sofa_scale':.7,'sofa_accessories_scaled_about_same_pivot':True,'rug_top_m':.091,'floor_visual_max_m':.083,'rug_gap_m':.008,'mural_basis':matrix.tolist(),'mural_position':pos,'mural_lowest_m':.091,'source_unchanged':True},indent=2),encoding='utf8')
print('LAYOUT_ADJUSTED',pos)
