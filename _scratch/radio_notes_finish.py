from pathlib import Path
import subprocess,sys,json,hashlib,re
R=Path('I:/工作项目/shellstrom2/ShellStorm2'); O=R/'outputs/base99_radio_music_notes'
G='I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'
for p in [R/'docs/v0.1/14.6_特效系统与制作规范.md',R/'src/vfx/VfxRadioMusicNotes3D.gd',R/'tests/verification/verify_base99_radio_music_notes.gd',R/'tests/verification/verify_base99_radio.gd',R/'_scratch/build_radio_music_notes.gd',*(R/'assets/art/vfx/environment_3d/radio_music_notes').glob('*.tscn')]:
 p.write_bytes(p.read_bytes().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
# 验收运行时，使用独立已命名日志，绝不修改存档。
for name,scene in [('notes_final','verify_base99_radio_music_notes'),('original_final','verify_base99_radio')]:
 with (O/f'testlogs/{name}.log').open('wb') as f:
  p=subprocess.run([G,'--path',str(R),'--resolution','1280x720','--position','80,80',f'res://tests/verification/{scene}.tscn'],stdout=f,stderr=subprocess.STDOUT)
 (O/f'testlogs/{name}.exit.json').write_text(json.dumps({'exit':p.returncode}),encoding='utf-8')
 print(name,p.returncode,flush=True)
