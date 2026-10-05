from pathlib import Path
import json,hashlib,subprocess
B=Path('assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/heavy_v016'
assert len(list((P/'frames').glob('*.png')))==96
subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(P/'frames/%04d.png'),'-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(P/'heavy_spin_slam.mp4')],check=True)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(P/'heavy_spin_slam.mp4'),'-vf','fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',str(P/'heavy_spin_slam.gif')],check=True)
p=B/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(version='v016',source='source/enm_boss_monitor002_model_v016.blend',animation_source='source/enm_boss_monitor002_animation_v016.blend',rig_contract='source/rig_contract_v016.json',verification={'animation':'previews/heavy_v016/audit.json','presentation':'previews/heavy_v016/audit.json'});m['preview_vfx'].pop('scale_vs_v014',None);m['preview_vfx']['action']='heavy_spin_slam';m['preview_vfx']['ground_ring_diameters']=[7.8,9.0]
for f in B.rglob('*'):
 if f.is_file() and f.name!='asset_manifest.json' and f.suffix not in ['.blend1','.import'] and ('v016' in f.as_posix() or f.name in ['README.md','boss002_production_ledger.xlsx']):m['files'][f.relative_to(B).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');print('V015 finalized')
