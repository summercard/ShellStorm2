import json,struct,copy,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03';out=root/'outputs/fat_zombie03_reduction'
def read(p):
 r=p.read_bytes();n=struct.unpack_from('<I',r,12)[0];return json.loads(r[20:20+n]),bytearray(r[28+n:])
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
oldpath=out/'original.glb'
if not oldpath.exists():oldpath.write_bytes(glb.read_bytes())
d,buf=read(oldpath);g,gb=read(out/'geometry.glb')
assert [g['nodes'][i]['name'] for i in g['skins'][0]['joints']]==[d['nodes'][i]['name'] for i in d['skins'][0]['joints']]
accessors={}
def view(i):
 v=copy.deepcopy(g['bufferViews'][i]);offset=v.get('byteOffset',0);data=gb[offset:offset+v['byteLength']]
 buf.extend(b'\0'*((-len(buf))%4));v['byteOffset']=len(buf);v['buffer']=0;buf.extend(data)
 idx=len(d['bufferViews']);d['bufferViews'].append(v);return idx
def transfer(i):
 if i in accessors:return accessors[i]
 a=copy.deepcopy(g['accessors'][i])
 if 'bufferView' in a:a['bufferView']=view(a['bufferView'])
 if 'sparse' in a:
  for k in ['indices','values']:a['sparse'][k]['bufferView']=view(a['sparse'][k]['bufferView'])
 idx=len(d['accessors']);d['accessors'].append(a);accessors[i]=idx;return idx
mesh=copy.deepcopy(g['meshes'][0])
for p in mesh['primitives']:
 p['attributes']={k:transfer(v) for k,v in p['attributes'].items()};p['indices']=transfer(p['indices']);p['material']=d['meshes'][0]['primitives'][0]['material']
 for target in p.get('targets',[]):
  for k,v in list(target.items()):target[k]=transfer(v)
d['meshes'][0]=mesh
buf.extend(b'\0'*((-len(buf))%4));d['buffers'][0]['byteLength']=len(buf)
j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
glb.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(buf))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(buf),b'BIN\0')+buf)
old,_=read(oldpath);assert d['animations']==old['animations'];assert d['nodes']==old['nodes'];assert d['skins']==old['skins']
report={'triangles':sum(d['accessors'][p['indices']]['count']//3 for p in mesh['primitives']),'animations_identical':True,'skeleton_identical':True,'materials_identical':d['materials']==old['materials'],'sha256':hashlib.sha256(glb.read_bytes()).hexdigest()}
assert report['triangles']<2000
(out/'export.json').write_text(json.dumps(report,indent=2))
p=pkg/'runtime/enm_normal_fat_zombie03_root_top3d.tscn';p.write_text(p.read_text(encoding='utf-8').replace('"v011"','"v012"'),encoding='utf-8')
print(report)
