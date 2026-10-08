"""Isolate user:// before Autoload and capture bounded Godot verification logs."""
from pathlib import Path
import os,sys,subprocess,json,time,re
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline'/os.environ.get('BUNNY_VERIFICATION_BATCH','runtime_v029');O.mkdir(parents=True,exist_ok=True)
G=os.environ.get('GODOT_BIN','I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe')
name=sys.argv[1];visual='--visual' in sys.argv
env=dict(os.environ,APPDATA=str(R/'_scratch/bunny_runtime_userdata'/name),LOCALAPPDATA=str(R/'_scratch/bunny_runtime_localdata'/name))
args=[G,'--path',str(R),'--audio-driver','Dummy']
args+=['--rendering-method','gl_compatibility','--resolution','720x720'] if visual else ['--headless']
args+=['--editor','--import','--quit'] if name=='import' else ['--quit-after','900','res://tests/verification/'+name+'.tscn']
if visual:args+=['--','--visual']
path=O/(name+('_visual' if visual else '')+'.log');start=time.time()
with path.open('wb') as f:
    try:p=subprocess.run(args,cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW);code=p.returncode
    except subprocess.TimeoutExpired:code=124
content=path.read_text(encoding='utf-8',errors='replace')
bad=[s for s in content.splitlines() if 'SCRIPT ERROR' in s or s.startswith('ERROR:')]
report=dict(scene=name,visual=visual,exit_code=code,unexpected_errors=bad,seconds=time.time()-start,user_data_isolated_before_autoload=True,log=str(path))
path.with_suffix('.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False));print('\n'.join(s for s in content.splitlines() if '_OK' in s or 'BUNNY_' in s))
sys.exit(code or (1 if bad else 0))
