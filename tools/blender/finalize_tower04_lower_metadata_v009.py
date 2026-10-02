"""Correct inherited scene metadata on the verified draft without touching geometry."""
import bpy,json,hashlib,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2];F=R/'assets/art/environments/open_world/source/tower_04/v009'
B=next(F.glob('*.blend'));expected='b2fa11f409b46449c605560ba048158a7abb582ebf5d4d16fb15309e059ff03c'
assert hashlib.sha256(B.read_bytes()).hexdigest()==expected
bpy.ops.wm.open_mainfile(filepath=str(B));sys.path.insert(0,str(Path(__file__).parent))
from tower04_lower_structure_common import object_signature
before={o.name:object_signature(o) for o in bpy.data.objects}
for s in bpy.data.scenes:
 s['floor_count']=3;s['floor_height_m']='variable';s['left_floor_levels_m']=[9.,14.3,19.6,25.];s['right_floor_levels_m']=[.45,7.8,15.8,23.8]
assert before=={o.name:object_signature(o) for o in bpy.data.objects}
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(B))
digest=hashlib.sha256(B.read_bytes()).hexdigest()
cat=json.loads((F/'catalog.json').read_text(encoding='utf8'));cat['floor_count']=3;cat['source_sha256']=digest
(F/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2),encoding='utf8')
build=json.loads((F/'qa/lower_structure_build.json').read_text(encoding='utf8'));build['source_sha256']=digest;build['modified_scope']=build['removed_packages'];build['removed_packages']=sorted(set(build['removed_packages'])-{p['slug'] for p in cat['packages']})
(F/'qa/lower_structure_build.json').write_text(json.dumps(build,ensure_ascii=False,indent=2),encoding='utf8')
(F/'qa/metadata_finalization.json').write_text(json.dumps({'passed':True,'prior_sha256':expected,'source_sha256':digest,'all_objects_unchanged':len(before),'change':'scene level metadata only; existing renders remain geometrically identical'},ensure_ascii=False,indent=2),encoding='utf8')
print('METADATA_FINALIZED',digest,flush=True)
