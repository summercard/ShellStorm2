"""Preserve original semantic islands; try small-island rigid stitching, audit each candidate."""
import json, math
from pathlib import Path
import numpy as np
from shapely.geometry import Polygon
from shapely.strtree import STRtree
P=Path(__file__).parent;d=json.loads((P/'uv_rig_source.json').read_text());F=d['faces'];U=np.array(d['uv'],float);V=np.array(d['vertices']);islands=json.loads((P/'source_islands.json').read_text());edges={}
for i,f in enumerate(F):
 for j,a in enumerate(f):
  b=f[(j+1)%3];edges.setdefault(tuple(sorted((a,b))),[]).append(i)
# Split source fold faces into sign-consistent connected patches before safe stitching.
original_count=len(islands);a=U[:,1]-U[:,0];b=U[:,2]-U[:,0];sgn=np.sign(a[:,0]*b[:,1]-a[:,1]*b[:,0]);neighbors=[[] for _ in F]
for ff in edges.values():
 if len(ff)==2:
  a,b=ff
  if sgn[a]==sgn[b]:neighbors[a].append(b);neighbors[b].append(a)
patches=[]
for isl in islands:
 remain=set(isl)
 while remain:
  seed=remain.pop();todo=[seed];patch=[seed]
  while todo:
   f=todo.pop()
   for g in neighbors[f]:
    if g in remain:remain.remove(g);todo.append(g);patch.append(g)
  patches.append(patch)
islands=patches
print('source fold repair patches',len(islands))
# Normalize whole-island orientation; original atlas contains mirrored island winding.
for isl in islands:
 t=U[isl];a=t[:,1]-t[:,0];b=t[:,2]-t[:,0];sg=a[:,0]*b[:,1]-a[:,1]*b[:,0]
 if not ((sg>0).all() or (sg<0).all()):
  assert len(isl)==1 and abs(sg[0])<1e-15, ('source island fold',isl,sg.tolist())
  fi=isl[0];xyz=V[F[fi]];ab=xyz[1]-xyz[0];ac=xyz[2]-xyz[0];le=np.linalg.norm(ab);xx=np.dot(ac,ab)/le;yy=np.sqrt(max(1e-16,np.dot(ac,ac)-xx*xx));U[fi]=np.array([[0,0],[le,0],[xx,yy]])*.35
  continue
 if (sg<0).all():U[isl,:,0]*=-1
owner={f:k for k,isl in enumerate(islands) for f in isl};groups={k:set(isl) for k,isl in enumerate(islands)};log=[]
def overlap(fs,uv):
 polys=[Polygon(uv[f]) for f in fs];tree=STRtree(polys)
 for i,p in enumerate(polys):
  if not p.is_valid or p.area<1e-13:return True
  for j in tree.query(p):
   if j>i and p.intersection(polys[j]).area>1e-11:return True
 return False
# Try attaching an island at its longest shared boundary. Similarity transform preserves its shape.
for iteration in range(150):
 candidates=[]
 for e,ff in edges.items():
  if len(ff)!=2:continue
  a,b=ff;ga,gb=owner[a],owner[b]
  if ga==gb:continue
  if len(groups[ga])>len(groups[gb]):a,b=b,a;ga,gb=gb,ga
  if len(groups[ga])>24:continue
  candidates.append((len(groups[ga]),-np.linalg.norm(V[e[0]]-V[e[1]]),ga,gb,a,b,e))
 candidates.sort(); accepted=False;tried=set()
 for n,_,ga,gb,a,b,e in candidates:
  if (ga,gb) in tried:continue
  tried.add((ga,gb));ia=[F[a].index(v) for v in e];ib=[F[b].index(v) for v in e]
  sa=U[a,ia];sb=U[b,ib];z1=complex(*(sa[1]-sa[0]));z2=complex(*(sb[1]-sb[0]));ratio=z2/z1
  if not .65<abs(ratio)<1.55:continue
  ids=sorted(groups[ga]);old=U[ids].copy();z=(old[:,:,0]-sa[0,0])+1j*(old[:,:,1]-sa[0,1]);z=z*ratio+complex(*sb[0]);U[ids]=np.stack([z.real,z.imag],axis=-1)
  union=sorted(groups[ga]|groups[gb]);bad=overlap(union,U)
  log.append({'source':ga,'target':gb,'faces':n,'accepted':not bad,'reason':'local_positive_overlap' if bad else 'continuous_edge_shape_preserved'})
  if bad:U[ids]=old;continue
  groups[gb]|=groups.pop(ga)
  for f in ids:owner[f]=gb
  accepted=True;break
 if not accepted:break
 if len(groups)<=50:break
# Export per-face exact coordinates; Blender pack can rotate and translate whole islands only.
result={'uv':U.tolist(),'islands':[sorted(v) for v in groups.values()],'merge_log':log,'original_islands':len(islands),'final_before_pack':len(groups)}
(P/'uv_stitched.json').write_text(json.dumps(result));print('STITCH',len(islands),'->',len(groups),'accepted',sum(x['accepted'] for x in log),'rejected',sum(not x['accepted'] for x in log))
