
import sys as _art_source_sys
from pathlib import Path as _ArtSourcePath
_art_source_sys.path.insert(0, str(_ArtSourcePath(__file__).resolve().parents[1]))
from art_source_paths import source_path
from pathlib import Path
import json,hashlib,shutil,zipfile
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001';B=R/'assets/art/environments/rooftop_courtyard_3d';V=O/'runtime_probe'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
assert json.loads((O/'source_validation_v002.json').read_text())['passed'];assert json.loads((O/'optimized_validation.json').read_text())['passed']
log=(O/'godot_verify_final.log').read_text(encoding='utf-8');assert 'COURTYARD_RUNTIME_OK' in log and 'SCRIPT ERROR' not in log
# Preserve real importer-generated settings at stable paths, no production cache copying.
for p in m['packages']:
    glb=Path(p['expected_glb']);ip=Path(str(glb)+'.import');probe=V/ip.relative_to(R)
    shutil.copy2(probe,ip)
m['runtime_standalone_validated']=True;m['runtime_integrated']=False;m['production_100f_placed']=False;m['runtime_triangles']=85855;m['runtime_status']='standalone_load_validated; formal placement and visual/motion acceptance pending'
m['ledger_registration']={'domain':'scenes','sheet':'资产主表','row':835,'status':'Blender源已完成','prefab_page_registered':False}
m['unresolved']=['80/20 rendered color ratio not satisfied or accepted; geometry surface ratio about 98/2','100F formal placement not performed','14 motion categories authored, not all individually visually validated in Godot','optimized before/after four-view comparison pending review','No independent whitebox Blender/top annotation deliverable; spatial contract extracted from current rooftop code and user dimensions']
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');(source_path(B/'source/prp_rooftop_courtyard/asset_manifest.json')).write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
registration=json.loads((O/'ledger_registration_20261007_235838_805301/registration_report.json').read_text(encoding='utf-8'))
report={'asset_id':m['asset_id'],'display_name':'主塔100F复古天台庭院','version':'v002','status':'Blender source and standalone Godot import delivered; full requested acceptance incomplete','source_blend':m['source_blend'],'optimized_blend':m['optimized_blend'],'prefab':m['runtime_prefab'],'source_polygons':39568,'source_triangles':87464,'optimized_triangles':85905,'runtime_triangles':85855,'triangles_difference_reason':'Godot importer removes degenerate triangles in its mesh conversion; difference50, no silhouette simplification enabled','triangle_budget':200000,'budget_utilization':85855/200000,'dimensions_m':[15,10],'deck_height_design_m':.1,'materials':4,'packages':73,'output_meshes':78,'animations_authored_categories':m['motion_features'],'source_validation':True,'optimized_validation':True,'standalone_runtime_validation':True,'ledger_row':835,'ledger_status':registration['status'],'ledger_structure_gate':True,'ledger_split_gate':True,'source_sha256':m['source_sha256'],'optimized_sha256':m['optimized_sha256'],'source_unchanged_during_optimization':True,'original_session_backup':str(O/'session_before.blend'),'current_blender_opened_source':True,'no_UI_scene':True,'no_people':True,'production_scene_changed':False,'pending':m['unresolved'],'global_gates':{'documentation':'unregistered unrelated verification entries; see documentation_gate_final.log','runtime_naming':'unrelated bunny/chair versioned assets; this facility stable component/runtime names have no versions'},'palette_dependency':'External project shared palette. ZIP deliberately does not duplicate it. Open blend from project source for materials.'}
(O/'delivery_status.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
# Persist machine-readable delivery audit in source, not just removable outputs.
(source_path(B/'source/prp_rooftop_courtyard/delivery_status_v002.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
# Portable files with external palette contract documented in manifest; no private palette PNG.
zip_path=O/'rooftop_courtyard_v002_asset_bundle.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as z:
    for f in B.rglob('*'):
        if f.is_file() and (f.suffix in ['.blend','.json','.glb','.import','.tscn','.gd'] or f.name=='.gdignore') and not f.name.endswith('.blend1'):
            z.write(f,f.relative_to(R).as_posix())
    for f in ['overview.png','top.png','closeup.png','rear.png','delivery_status.json','source_validation_v002.json','optimized_validation.json','optimization.json']:
        z.write(O/f,'previews_and_acceptance/'+f)
print('COURTYARD_DELIVERY_READY',zip_path,zip_path.stat().st_size)
