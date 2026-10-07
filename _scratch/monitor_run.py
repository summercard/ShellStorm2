import os,sys,subprocess,json,re,time
from pathlib import Path
R=Path.cwd();D=R/'_scratch/monitor_qa_project';Q=R/'assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime'
env=os.environ.copy();env['APPDATA']=str(R/'_scratch/monitor_userdata');env['PYTHONIOENCODING']='utf-8'
G='I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'
name=sys.argv[1];visual='visual' in name
args=[G,'--path',str(D),'--audio-driver','Dummy']
args += ['--rendering-method','gl_compatibility','--resolution','960x720','--position','80,80'] if visual else ['--headless']
args += ['--editor','--import','--quit'] if name=='import' else ['res://tests/verification/'+name+'.tscn']
if '--sequence' in sys.argv:args += ['--','--sequence']
p=Q/(name+'.log');start=time.time()
with p.open('wb') as f:
 try:r=subprocess.run(args,cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW);code=r.returncode
 except subprocess.TimeoutExpired:code=124
t=p.read_text(encoding='utf-8',errors='replace');bad=[s for s in t.splitlines() if 'SCRIPT ERROR' in s or s.startswith('ERROR:')]
print(json.dumps({'scene':name,'exit_code':code,'unexpected_errors':bad[:20],'error_count':len(bad),'seconds':round(time.time()-start,1),'log':str(p)},ensure_ascii=False))
print('\n'.join(s for s in t.splitlines() if '_OK' in s or 'MONITOR' in s))
sys.exit(code or (1 if bad else 0))
