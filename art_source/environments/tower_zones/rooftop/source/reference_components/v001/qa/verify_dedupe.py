"""Environment equivalent of the current character-only asset_guard gate."""
import json,hashlib,openpyxl
from pathlib import Path
O=Path(__file__).resolve().parents[1];R=Path('/Users/summercards/ShellStorm2')
cat=json.loads((O/'component_packages_v001/catalog.json').read_text())
w=openpyxl.load_workbook(O/'qa/registry_before.xlsx',read_only=True)
old_ids=set();old_paths=set();old_hashes=set()
for s in w:
    for row in s.values:
        if row and isinstance(row[0],str):old_ids.add(row[0])
        for v in row:
            if isinstance(v,str) and (v.startswith('assets/') or v.startswith('source/')):old_paths.add(v)
            if isinstance(v,str) and len(v)==64 and all(c in 'abcdef0123456789' for c in v):old_hashes.add(v)
ids=[p['package_id'] for p in cat];paths=[p['source_blend']+'#'+p['blender_collection'] for p in cat]
keys=[('场景','environment_module_3d','rooftop_reference',p['slug'],'Z-up/-Y','reference') for p in cat]
sha=hashlib.sha256((O/'天台区块_参考组件库_v001.blend').read_bytes()).hexdigest()
checks={'unique_ids':len(set(ids))==37,'no_preexisting_child_ids':not (set(ids)&old_ids),'unique_dedupe_keys':len(set(keys))==37,'unique_collection_paths':len(set(paths))==37,'new_source_path':cat[0]['source_blend'] not in old_paths,'new_source_hash':sha not in old_hashes,'explicit_child_variants':all(p['dedupe_classification']=='child_variant' for p in cat),'existing_parent':all(p['variant_of'] in old_ids for p in cat)}
report={'passed':all(checks.values()),'checks':checks,'classification':'child_variant; existing rooftop/floor/facade identities retained','asset_guard_limit':'scripts/asset_guard.py requires character_transfer_ledger; environment-specific gate used without inventing character data','sha256':sha}
(O/'qa/dedupe_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False));raise SystemExit(0 if report['passed'] else 1)
