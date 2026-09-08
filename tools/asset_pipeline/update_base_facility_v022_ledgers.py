from pathlib import Path
import json, hashlib
ROOT=Path(__file__).resolve().parents[2]
export_path=ROOT/'source/art/blender/base_facility_layout/export/v022/export_manifest.json'
data=json.loads(export_path.read_text())
data['packages']['hologram_terminal_platform']['bbox_blender']={'min':[3.7956285,0.5156285,0.04],'max':[6.2043715,2.9243715,1.8648558]}
export_path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
canonical={
'loft_bed_and_bedding':'loft/loft_bed_and_bedding','loft_bedside_lamp':'loft/loft_bedside_lamp',
'hologram_terminal_platform':'underloft/hologram_terminal_platform','corridor_emergency_light_group':'support/corridor_emergency_light_group',
'east_power_distribution':'east_facilities/east_power_distribution','east_industrial_pipeline_system':'east_facilities/east_industrial_pipeline_system',
'east_maintenance_workstation':'east_facilities/east_maintenance_workstation','east_work_together_poster':'east_facilities/east_work_together_poster',
'east_small_safety_devices':'east_facilities/east_small_safety_devices','weapon_workshop_station':'underloft/weapon_workshop_station',
'south_wall_information_boards':'warehouse/south_wall_information_boards','water_purifier':'warehouse/water_purifier',
'heavy_supply_shelf':'warehouse/heavy_supply_shelf','northwest_l_stair':'architecture/northwest_l_stair'}
for slug,sub in canonical.items():
 p=ROOT/'source/art/blender/base_facility_layout/component_packages'/sub/'asset_manifest.json'
 d=json.loads(p.read_text()); e=data['packages'][slug]
 d['version']='v022'; d['source_blend']=data['source_blend']; d['derived_blend']=data['derived_blend']; d['expected_export']=Path(e['glb']).name
 d['v022_update']={'wall_contact_adjusted':slug in {'east_power_distribution','east_industrial_pipeline_system','east_maintenance_workstation','east_work_together_poster','east_small_safety_devices','weapon_workshop_station','south_wall_information_boards','water_purifier','heavy_supply_shelf'},'downward_faces_removed':e['downward_triangles_removed'],'triangles_after':e['triangles_after']}
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
ledger=ROOT/'assets/art/environments/base_facility_3d/source/env_base99_updates_v022_import_manifest.json'; ld=json.loads(ledger.read_text()); ld['source_sha256']=hashlib.sha256((ROOT/data['source_blend']).read_bytes()).hexdigest(); ld['packages']=data['packages']; ledger.write_text(json.dumps(ld,ensure_ascii=False,indent=2)+'\n')
print('BASE99_V022_LEDGERS_UPDATED=14')
