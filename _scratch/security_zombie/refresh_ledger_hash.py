from pathlib import Path
import json,hashlib
p=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/character_transfer_ledger.json')
d=json.loads(p.read_text(encoding='utf-8'))
root=p.parents[2]
files=[
 ('assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v001.blend', 'model'),
 ('assets/art/enemies/normal_enemy_3d/ranged_caster/source/animation/enm_ranged_sporeshooter01_animation_v002.blend', 'animation'),
 ('assets/art/enemies/normal_enemy_3d/ranged_caster/components/enm_ranged_sporeshooter01_visual_top3d.glb', 'component_glb'),
 ('assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn', 'runtime_prefab'),
]
d['files']=[{'path':path,'sha256':hashlib.sha256((Path('I:/工作项目/shellstrom2/ShellStorm2')/path).read_bytes()).hexdigest(),'bytes':(Path('I:/工作项目/shellstrom2/ShellStorm2')/path).stat().st_size,'role':role} for path,role in files]
d['status']='active';d['validation_status']='passed';d['remaining_work']=['full ranged projectile regression retains existing 7 floating-number baseline red']
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\r\n')
print('LEDGER_ACTIVE',d['files'])
