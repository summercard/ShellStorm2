from pathlib import Path
import json,subprocess,hashlib
B=Path('assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/impact_electric_v027';spec=json.loads((P/'clips.json').read_text());ff='ffmpeg'
for name,n in spec.items():
 assert len(list((P/name).glob('*.png')))==n,(name,n)
 subprocess.run([ff,'-y','-loglevel','error','-framerate','30','-i',str(P/name/'%04d.png'),'-vf',f"drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':text='{name}':fontsize=23:fontcolor=white:x=22:y=22:box=1:boxcolor=black@0.5:boxborderw=8",'-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(P/(name+'.mp4'))],check=True)
sets={'special':['special_prepare','special_insert','special_channel','special_channel','special_recover'],'stun':['stun_enter','stun_loop','stun_loop','stun_exit']}
sets['all_updated']=sets['stun']+sets['special']
for key,seq in sets.items():
 lst=P/(key+'_concat.txt');lst.write_text(''.join("file '"+str((P/(n+'.mp4')).resolve()).replace('\\','/')+"'\n" for n in seq),encoding='utf-8')
 subprocess.run([ff,'-y','-loglevel','error','-f','concat','-safe','0','-i',str(lst),'-c','copy',str(P/(key+'.mp4'))],check=True)
 subprocess.run([ff,'-y','-loglevel','error','-i',str(P/(key+'.mp4')),'-vf','fps=20,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',str(P/(key+'.gif'))],check=True)

p=B/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(version='v027',source='source/enm_boss_monitor002_model_v027.blend',animation_source='source/enm_boss_monitor002_animation_v027.blend',rig_contract='source/rig_contract_v027.json',verification={'animation':'previews/impact_electric_v027/audit.json','effects':'previews/impact_electric_v027/fx_audit.json'})
m['preview_vfx']={'current_preview':'stun single bounce, dizzy expression/stars and one-frame yellow hit; grounded special electric cable','collection':'BOSS002_DIZZY_ELECTRIC_PREVIEW','runtime_integrated':False,'previous_attack_previews_retained':True}
for f in B.rglob('*'):
 if f.is_file() and f.name!='asset_manifest.json' and f.suffix not in ['.blend1','.import'] and ('v027' in f.as_posix() or f.name in ['README.md','boss002_production_ledger.xlsx']):m['files'][f.relative_to(B).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
print('v027 previews and manifest complete')
