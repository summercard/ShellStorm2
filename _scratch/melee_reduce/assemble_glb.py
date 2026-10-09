import json,struct,copy,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/melee_chaser';out=root/'outputs/melee_zombie_reduction'
def read(p):
 r=p.read_bytes();n=struct.unpack_from('<I',r,12)[0];return json.loads(r[20:20+n]),bytearray(r[28+n:])
original=pkg/'components/enm_melee_fungboar01_visual_top3d.glb'
if not (out/'original.glb').exists():(out/'original.glb').write_bytes(original.read_bytes())
d,buf=read(out/'geometry.glb');old,ob=read(out/'original.glb');nodes={n.get('name'):i for i,n in enumerate(d['nodes'])};copied={}
def transfer(i):
 if i in copied:return copied[i]
 a=copy.deepcopy(old['accessors'][i]);v=copy.deepcopy(old['bufferViews'][a['bufferView']]);start=v.get('byteOffset',0)
 buf.extend(b'\0'*((-len(buf))%4));v['byteOffset']=len(buf);buf.extend(ob[start:start+v['byteLength']]);v['buffer']=0;a['bufferView']=len(d['bufferViews']);d['bufferViews'].append(v);idx=len(d['accessors']);d['accessors'].append(a);copied[i]=idx;return idx
d['animations']=[];removed=[]
for anim in old['animations']:
 new={'name':anim['name'],'channels':[],'samplers':[]}
 for channel in anim['channels']:
  name=old['nodes'][channel['target']['node']].get('name')
  if name not in nodes:removed.append(name);continue
  sampler=copy.deepcopy(anim['samplers'][channel['sampler']]);sampler['input']=transfer(sampler['input']);sampler['output']=transfer(sampler['output'])
  c=copy.deepcopy(channel);c['target']['node']=nodes[name];c['sampler']=len(new['samplers']);new['samplers'].append(sampler);new['channels'].append(c)
 d['animations'].append(new)
assert all(any(x in n for x in ['Thumb','Index','Middle','Pinky','Ring']) for n in removed)
buf.extend(b'\0'*((-len(buf))%4));d['buffers'][0]['byteLength']=len(buf);j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
candidate=out/'candidate.glb';candidate.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(buf))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(buf),b'BIN\0')+buf)
report={'triangles':sum(d['accessors'][p['indices']]['count']//3 for p in d['meshes'][0]['primitives']),'bones':len(d['skins'][0]['joints']),'clips':[a['name'] for a in d['animations']],'removed_channels_bones':sorted(set(removed)),'preserved_animation_accessor_bytes':True,'sha256':hashlib.sha256(candidate.read_bytes()).hexdigest()}
assert report['triangles']<1800 and report['bones']==20 and len(report['clips'])==6
(out/'export.json').write_text(json.dumps(report,indent=2));print(report)
