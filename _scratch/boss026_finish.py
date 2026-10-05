from pathlib import Path
import json,subprocess,hashlib
B=Path('assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/remaining_v026';spec=json.loads((P/'clips.json').read_text());ff='ffmpeg'
for name,n in spec.items():
 assert len(list((P/name).glob('*.png')))==n,(name,n)
 subprocess.run([ff,'-y','-loglevel','error','-framerate','30','-i',str(P/name/'%04d.png'),'-vf',f"drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':text='{name}':fontsize=23:fontcolor=white:x=22:y=22:box=1:boxcolor=black@0.5:boxborderw=8",'-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(P/(name+'.mp4'))],check=True)
sets={'special':['special_prepare','special_insert','special_channel','special_channel','special_recover'],'hurt_preview':['hurt'],'stun':['stun_enter','stun_loop','stun_loop','stun_exit'],'turns':['turn_left','turn_right']}
sets['all_remaining']=sets['special']+sets['hurt_preview']+sets['stun']+sets['turns']
for key,seq in sets.items():
 lst=P/(key+'_concat.txt');lst.write_text(''.join("file '"+str((P/(n+'.mp4')).resolve()).replace('\\','/')+"'\n" for n in seq),encoding='utf-8')
 subprocess.run([ff,'-y','-loglevel','error','-f','concat','-safe','0','-i',str(lst),'-c','copy',str(P/(key+'.mp4'))],check=True)
 subprocess.run([ff,'-y','-loglevel','error','-i',str(P/(key+'.mp4')),'-vf','fps=20,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',str(P/(key+'.gif'))],check=True)
p=B/'asset_manifest.json';m=json.loads(p.read_text(encoding='utf-8'));m.update(version='v026',source='source/enm_boss_monitor002_model_v026.blend',animation_source='source/enm_boss_monitor002_animation_v026.blend',rig_contract='source/rig_contract_v026.json',verification={'animation':'previews/remaining_v026/audit.json','preservation':'previews/remaining_v026/old_actions.json'})
m['formal_animations_authored']=['idle','move','melee_keyboard','melee_cable','heavy_spin_slam']+list(spec);m['formal_animations']=m['formal_animations_authored'];m['preview_vfx']={'current_preview':'remaining five categories; no attack FX','previous_attack_previews_retained':True}
for f in B.rglob('*'):
 if f.is_file() and f.name!='asset_manifest.json' and f.suffix not in ['.blend1','.import'] and ('v026' in f.as_posix() or f.name in ['README.md','boss002_production_ledger.xlsx']):m['files'][f.relative_to(B).as_posix()]=hashlib.sha256(f.read_bytes()).hexdigest()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
print('V026 complete: 15 authored clips, 10 new, five categories')
