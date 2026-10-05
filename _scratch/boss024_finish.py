from pathlib import Path
import json,hashlib,subprocess
B=Path('assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/cable_v024';assert len(list((P/'frames').glob('*.png')))==60
subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(P/'frames/%04d.png'),'-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(P/'melee_cable.mp4')],check=True)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(P/'melee_cable.mp4'),'-vf','fps=30,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',str(P/'melee_cable.gif')],check=True)
p=B/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(version='v024',source='source/enm_boss_monitor002_model_v024.blend',animation_source='source/enm_boss_monitor002_animation_v024.blend',rig_contract='source/rig_contract_v024.json',verification={'animation':'previews/cable_v024/audit.json','presentation':'previews/cable_v024/initial_audit.json'})
m['formal_animations_authored']=['idle','move','melee_keyboard','heavy_spin_slam','melee_cable'];m['formal_animations']=m['formal_animations_authored'];m['preview_vfx']={'collection':'BOSS002_CABLE_PREVIEW','action':'melee_cable','palette':'keyboard cyan / magenta / white','style':'unoutlined ribbons sampled from actual cable tip','export':False,'frames':[9,34]}
for f in B.rglob('*'):
 if f.is_file() and f.name!='asset_manifest.json' and f.suffix not in ['.blend1','.import'] and ('v024' in f.as_posix() or f.name in ['README.md','boss002_production_ledger.xlsx']):m['files'][f.relative_to(B).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
