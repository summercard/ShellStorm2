from pathlib import Path
import subprocess,json,sys,os
R=Path('I:/工作项目/shellstrom2/ShellStorm2'); O=R/'outputs/base99_radio_music_notes'
G='I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'
paths=['src/vfx/VfxRadioMusicNotes3D.gd','src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio.gd','tests/verification/verify_base99_radio_music_notes.gd','tests/verification/verify_base99_radio_music_notes.tscn','assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','_scratch/build_radio_music_notes.gd','_scratch/build_radio_music_notes.tscn']
paths += [str(p.relative_to(R)) for p in (R/'assets/art/vfx/environment_3d/radio_music_notes').glob('*') if p.suffix in ('.tscn','.tres')]
for rel in paths:
 p=R/rel; b=p.read_bytes().replace(b'\r\n',b'\n'); p.write_bytes(b.replace(b'\n',b'\r\n'))
for rel in ['src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio.gd']:
 p=subprocess.run(['git','-C',str(R),'show','HEAD:'+rel],capture_output=True,check=True)
 (O/'backup'/rel).write_bytes(p.stdout)
mode=sys.argv[1] if len(sys.argv)>1 else 'import'
if mode=='import':
 cmd=[G,'--headless','--path',str(R),'--editor','--import']
elif mode=='original':
 cmd=[G,'--path',str(R),'--resolution','1280x720','--position','80,80','res://tests/verification/verify_base99_radio.tscn']
else:
 cmd=[G,'--path',str(R),'--resolution','1280x720','--position','80,80','res://tests/verification/verify_base99_radio_music_notes.tscn']
with (O/f'testlogs/{mode}.log').open('wb') as f:
 p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
(O/f'testlogs/{mode}.exit.json').write_text(json.dumps({'exit':p.returncode}),encoding='utf-8')
print(mode,p.returncode)
