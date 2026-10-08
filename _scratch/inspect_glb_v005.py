import json,struct
from pathlib import Path
p=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb'); b=p.read_bytes(); off=12; out={}
while off<len(b):
 n,t=struct.unpack_from('<II',b,off); d=b[off+8:off+8+n]; out[hex(t)] = n
 if t==0x4e4f534a: j=json.loads(d.rstrip(b' '))
 off+=8+n
print(json.dumps({'chunks':out,'materials':[m.get('name') for m in j.get('materials',[])],'images':j.get('images',[]),'textures':j.get('textures',[]),'nodes':[n.get('name') for n in j.get('nodes',[])],'meshes':[m.get('name') for m in j.get('meshes',[])]},ensure_ascii=False,indent=2))
