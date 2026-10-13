"""Prepare stable import contracts and initial Godot room specification. Never overwrite room01."""
import json,sys,shutil,hashlib,math
from pathlib import Path
from PIL import Image
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'scripts'))
from workspace_paths import work_path
W=work_path('outputs/boss_room02_import/spec.json').parent
D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v027'
M=json.loads((D/'import_manifest.json').read_text('utf8'));snap=json.loads((W/'presentation_snapshot.json').read_text('utf8'))
base=R/'assets/art/environments/tower_zones/expedition';runtime=base/'runtime/room_type_components/boss_room_02';runtime.mkdir(parents=True,exist_ok=True)
backup=R.parent/'ShellStorm2-backup/2026-10-13_boss_room02_import/before_edits';backup.mkdir(parents=True,exist_ok=True)
def back(p):
 if p.exists():
  q=backup/p.relative_to(R);q.parent.mkdir(parents=True,exist_ok=True)
  if not q.exists():shutil.copy2(p,q)
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def g(v):return [v[0],v[2],-v[1]]
def transform(m,recenter=True):
 # C M C^-1, C maps Blender (x,y,z) to Godot (x,z,-y).
 C=[[1,0,0],[0,0,1],[0,-1,0]];Ci=[[1,0,0],[0,0,-1],[0,1,0]]
 A=[[sum(C[i][k]*m[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
 B=[[sum(A[i][k]*Ci[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
 p=g([m[0][3],m[1][3]+(22.5 if recenter else 0),m[2][3]])
 return [B[i][j] for j in range(3) for i in range(3)]+p
def box(part):
 lo=part['bounds_min'];hi=part['bounds_max'];return {'kind':'box','position':g([(a+b)/2 for a,b in zip(lo,hi)]),'size':g([hi[i]-lo[i] for i in range(3)])[:2]+[hi[1]-lo[1]]}
allrecords=[]
for d in M['components']:
 slug=d['slug'];p=R/d['glb_path'];imp=Path(str(p)+'.import')
 # Canonical scene post-import, all image content deliberately outside GLB.
 template=(base/'components/room_type_components/boss_room/server_rack/server_rack_visual_top3d.glb.import').read_text('utf8')
 rel=p.relative_to(R).as_posix();old='assets/art/environments/tower_zones/expedition/components/room_type_components/boss_room/server_rack/server_rack_visual_top3d.glb';template=template.replace(old,rel).replace('uid="uid://cijgms68ul2od"','')
 key=hashlib.md5(('res://'+rel).encode()).hexdigest();template=template.replace('server_rack_visual_top3d.glb-03f035bdcd65afc29433bb7eb446d251','env_boss_room02_'+slug+'_visual_top3d.glb-'+key)
 template=template.replace('animation/import=true','animation/import=false');imp.write_text(template,encoding='utf8')
 parts=snap['parts'].get(slug,[]);cols=[]
 if slug in ('deck_armor_5m','deck_emblem_5m'):
  lo=d['bounds_min'];hi=d['bounds_max'];cols=[box({'bounds_min':lo,'bounds_max':hi})]
 elif slug=='bridge_deck_5m':cols=[box(x) for x in parts if x['name']=='桥面底盘']
 elif slug=='bridge_threshold':cols=[box(x) for x in parts if x['name']=='连续门槛承重板']
 elif slug=='exit_portal':cols=[box(x) for x in parts if x['name'] in ('装甲主门垛','上部门机横梁')]
 elif slug=='exit_passage':cols=[box(x) for x in parts if x['name'] in ('出口内廊地坪','内廊侧墙','内廊顶板')]
 elif slug=='stair_landing_5m':cols=[box(x) for x in parts if x['name'] in ('平台底板','平台栏杆柱','平台扶手')]
 elif slug=='stair_flight_5m':
  steps=[x for x in parts if x['name']=='踏步承托'];ylo=min(x['bounds_min'][1] for x in steps);yhi=max(x['bounds_max'][1] for x in steps);zlow=min(x['bounds_max'][2] for x in steps);zhigh=max(x['bounds_max'][2] for x in steps)
  # Continuous convex ramp top follows the step front noses, not a giant AABB.
  pts=[]
  for x in (-2.5,2.5):
   for y,z in ((yhi,zlow),(ylo,zhigh),(yhi,zlow-.3),(ylo,zhigh-.3)):pts.append(g([x,y,z]))
  cols=[{'kind':'convex','points':pts}]+[box(x) for x in parts if '扶手' in x['name'] or '栏杆立柱' in x['name']]
 elif slug in ('deck_barrier_5m','bridge_rail_5m','exit_leaf_a','exit_leaf_b','door_seal_frame','portal_backing_5m') or slug.startswith('shell_'):
  cols=[{'kind':'mesh'}] # Exact static surface avoids blocking door openings or guardrail gaps.
 elif slug in ('equipment_cluster','damaged_cabinet_open','damaged_cabinet_crushed'):
  cols=[box({'bounds_min':d['bounds_min'],'bounds_max':d['bounds_max']})]
 d['collisions']=cols;d['collision_policy']='continuous_ramp_and_rail' if slug=='stair_flight_5m' else ('segmented_structure' if cols and cols[0]['kind']=='box' else ('exact_static_mesh' if cols else 'visual_only'))
 d['collision_owner']='self' if cols else 'none'
 d['bounds_size_m_godot']=[d['bounds_size_m'][0],d['bounds_size_m'][2],d['bounds_size_m'][1]]
 if slug.startswith('screen_'):
  name={'screen_left':'screen_left_telemetry.png','screen_center':'screen_center_datacube.png','screen_right':'screen_right_signal.png'}[slug]
  src=D/'textures'/name
  if not src.exists():src=next((D/'textures').glob('*'+slug.split('_')[1]+'*.png'))
  out=R/'assets/art/shared/textures/general'/('env_boss_room02_'+slug+'.png');out.parent.mkdir(parents=True,exist_ok=True)
  im=Image.open(src);im.thumbnail((1024,1024),Image.Resampling.LANCZOS);im.save(out)
  d['screen_texture']='res://'+out.relative_to(R).as_posix();d['screen_source_texture']=str(src);d['screen_texture_budget']=1024
 allrecords.append(d)
records=json.loads((D/'component_instances.json').read_text('utf8'))['instances']
for r in records:r['godot_transform']=transform(r['matrix_room_local'])
spec={'room_id':'boss_room_02','level_id':'expedition_01','block_id':'expedition','asset_id':'ENV-EXPEDITION-L01-BOSS-ROOM-02','version':'v027','components':allrecords,'instances':records,'lights':snap['lights'],'cameras':snap['cameras'],'coordinate_contract':{'mapping':'(x,z,-(y+22.5))','source_bounds_xy_m':[[-40,-72.5],[40,27.5]],'room_frame_origin_blender_m':[0,-22.5,0],'origin_mode':'footprint_center_walk_plane','walk_plane_z_m':0,'front_axis_godot':'+Z'},'runtime_scene':'res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_boss_room_02_static_layout.tscn'}
for x in spec['lights']+spec['cameras']:x['godot_transform']=transform(x['matrix'])
write(W/'spec.json',spec)
# Whitelist reproducible import settings without changing existing import contracts.
gitignore=R/'.gitignore';back(gitignore);text=gitignore.read_text('utf8');marker='# Boss room02 reproducible imports'
if marker not in text:gitignore.write_text(text+'\n'+marker+'\n!assets/art/environments/tower_zones/expedition/components/room_type_components/boss_room_02/**/*.glb.import\n!assets/art/shared/textures/general/env_boss_room02_*.png.import\n',encoding='utf8')
print('PREPARED',len(allrecords),len(records))
