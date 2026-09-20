import json,collections
from pathlib import Path
P=Path(__file__).parent;d=json.loads((P/'uv_rig_source.json').read_text());fs=d['faces'];uv=d['uv'];vs=d['vertices']; adj=collections.defaultdict(list)
for i,f in enumerate(fs):
 for j,a in enumerate(f):
  b=f[(j+1)%len(f)];adj[tuple(sorted((a,b)))].append((i,{a:uv[i][j],b:uv[i][(j+1)%len(f)]}))
nei=[[] for f in fs]
for e,rows in adj.items():
 if len(rows)==2:
  (i,a),(j,b)=rows
  if all(max(abs(a[v][k]-b[v][k]) for k in range(2))<1e-6 for v in e):nei[i].append(j);nei[j].append(i)
islands=[];seen=set()
for i in range(len(fs)):
 if i in seen:continue
 st=[i];seen.add(i);isl=[]
 while st:
  j=st.pop();isl.append(j)
  for k in nei[j]:
   if k not in seen:seen.add(k);st.append(k)
 islands.append(isl)
print('UV ISLANDS',len(islands),'sizes',sorted(map(len,islands)));print('boundary',sum(len(x)==1 for x in adj.values()),'nonmanifold',sum(len(x)>2 for x in adj.values()))
for side in ['L','R']:
 gi=d['groups'].index(side+'_Hand');ids=[i for i,w in enumerate(d['weights']) if any(g==gi and v>.1 for g,v in w)];print(side,'hand verts',len(ids));print([(i,[round(c,4) for c in vs[i]]) for i in ids])
(P/'source_islands.json').write_text(json.dumps(islands))
