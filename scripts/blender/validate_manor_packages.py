"""Normalize each library into a stand-alone active scene and run the skill validator."""
import bpy,json,hashlib,sys,importlib.util,contextlib,io,shutil
from pathlib import Path
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017'
C=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components']
validator=Path('C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py')
spec=importlib.util.spec_from_file_location('prop_validator',validator);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
reports=[]
for e in C:
 path=R/e['component_blend'];bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.scenes=src.scenes
 sc=next(s for s in dst.scenes if s is not None);bpy.context.window.scene=sc
 for other in list(bpy.data.scenes):
  if other!=sc:bpy.data.scenes.remove(other)
 # Materials not used by a component are removed from the individual file.
 for mat in list(bpy.data.materials):
  if mat.users==0:bpy.data.materials.remove(mat)
 normalized=W/'normalized_packages'/path.name;normalized.parent.mkdir(exist_ok=True)
 for image in bpy.data.images:
  if image.source=='FILE':image.filepath=str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png')
 bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(normalized),compress=True,relative_remap=False)
 # Actually reopen it, so a library-only empty startup scene cannot pass.
 bpy.ops.wm.open_mainfile(filepath=str(normalized))
 assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])>0
 for o in bpy.context.scene.objects:
  if o.type=='MESH':assert o.parent and o.parent.name.startswith('ROOT_')
 report_path=W/(e['slug']+'_qa.json')
 sys.argv=['validate_game_prop','--','--all-meshes','--shared-palette',str(R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'),'--json',str(report_path)]
 stream=io.StringIO()
 try:
  with contextlib.redirect_stdout(stream):module.main()
 except SystemExit as err:code=err.code
 report=json.loads(report_path.read_text(encoding='utf-8'));reports.append({'slug':e['slug'],'exit_code':code,'passed':report['passed'],'failed_checks':[k for k,v in report['checks'].items() if not v]})
 shutil.copy2(normalized,path)
 e['component_blend_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
 mp=S/'component_packages'/e['slug']/'asset_manifest.json';m=json.loads(mp.read_text(encoding='utf-8'));m['component_blend_sha256']=e['component_blend_sha256'];mp.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'component_catalog.json').write_text(json.dumps({'components':C},ensure_ascii=False,indent=2),encoding='utf-8')
(W/'package_validation.json').write_text(json.dumps({'components':reports,'passed':all(r['passed'] for r in reports)},ensure_ascii=False,indent=2),encoding='utf-8')
print('MANOR_PACKAGE_VALIDATION',json.dumps(reports))
