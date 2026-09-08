import bpy,json,ast,hashlib,importlib.util
from pathlib import Path
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_east_v021'
spec=importlib.util.spec_from_file_location('old',P/'scripts/blender/reorganize_base_facility_component_packages_v017.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
src=(P/'scripts/blender/deepen_base_facility_loft_v019.py').read_text();tree=ast.parse(src);node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='sig');exec(ast.get_source_segment(src,node))
locked=json.loads((R/'locked_before.json').read_text());current=json.loads(json.dumps({n:sig(bpy.data.objects[n]) for n in locked}));diff=[n for n in locked if locked[n]!=current[n]];report={'locked_match':not diff,'locked_count':len(locked),'differences':diff,'before_digest':hashlib.sha256(json.dumps(locked,sort_keys=True).encode()).hexdigest(),'after_digest':hashlib.sha256(json.dumps(current,sort_keys=True).encode()).hexdigest()};(R/'final_lock.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('FINAL_LOCK',report);assert not diff
