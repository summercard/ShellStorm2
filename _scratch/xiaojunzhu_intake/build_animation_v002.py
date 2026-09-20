from pathlib import Path
P=Path(__file__).parent
s=(P/'animate_zombie.py').read_text(encoding='utf-8').replace('animation_v001.blend','animation_v002.blend').replace("+'_v001'","+'_v002'").replace("P/'animation_meta.json'","P/'animation_meta_v002.json'")
s=s.replace('meta=[]',"exec((P/'refine_motion_v002.py').read_text(encoding='utf-8'))\nmeta=[]")
exec(compile(s,str(P/'animate_zombie.py'),'exec'))
