import json
import numpy as np
from pathlib import Path
P=Path(__file__).parent;d=json.loads((P/'uv_stitched.json').read_text());U=np.array(d['uv']);islands=d['islands'];shapes=[]
# minimum bounding rectangle orientations without changing island shape
for ids in islands:
 points=U[ids].reshape(-1,2);best=None
 for angle in np.linspace(0,np.pi/2,91):
  R=np.array([[np.cos(angle),-np.sin(angle)],[np.sin(angle),np.cos(angle)]]);p=points@R.T;lo=p.min(0);size=p.max(0)-lo;score=size.prod()
  if best is None or score<best[0]:best=(score,R,lo,size)
 shapes.append((ids,*best[1:]))
order=sorted(range(len(shapes)),key=lambda i:-max(shapes[i][3]));gap=.004
# maxrects all splitting, contained free rectangles pruned

def pack(scale):
 free=[(gap,gap,1-2*gap,1-2*gap)];places={}
 for i in order:
  size=shapes[i][3]*scale+gap;opts=[]
  for j,(x,y,w,h) in enumerate(free):
   for rot in [False,True]:
    a,b=size[::-1] if rot else size
    if a<=w and b<=h:opts.append((min(w-a,h-b),max(w-a,h-b),j,rot,a,b))
  if not opts:return None
  _,_,j,rot,a,b=min(opts);x,y,_,_=free[j];places[i]=(x,y,rot);new=[]
  for xx,yy,w,h in free:
   if x>=xx+w or x+a<=xx or y>=yy+h or y+b<=yy:new.append((xx,yy,w,h));continue
   if x>xx:new.append((xx,yy,x-xx,h))
   if x+a<xx+w:new.append((x+a,yy,xx+w-x-a,h))
   if y>yy:new.append((xx,yy,w,y-yy))
   if y+b<yy+h:new.append((xx,y+b,w,yy+h-y-b))
  free=[r for k,r in enumerate(new) if not any(k!=l and r[0]>=t[0]-1e-12 and r[1]>=t[1]-1e-12 and r[0]+r[2]<=t[0]+t[2]+1e-12 and r[1]+r[3]<=t[1]+t[3]+1e-12 for l,t in enumerate(new))]
 return places
lo=.01;hi=2
for _ in range(30):
 mid=(lo+hi)/2
 if pack(mid):lo=mid
 else:hi=mid
places=pack(lo)
for i,(ids,R,base,size) in enumerate(shapes):
 p=U[ids]@R.T-base;x,y,rot=places[i]
 if rot:p=np.stack([p[...,1],size[0]-p[...,0]],axis=-1)
 U[ids]=p*lo+(x,y)
(P/'uv_packed.json').write_text(json.dumps(U.tolist()));print('PACK_OK',len(shapes),'uniform_scale',lo)
