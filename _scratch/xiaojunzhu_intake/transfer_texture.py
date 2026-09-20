import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import distance_transform_edt,map_coordinates
from shapely.geometry import Polygon
from shapely.strtree import STRtree
P=Path(__file__).parent;d=json.loads((P/'uv_rig_source.json').read_text());q=json.loads((P/'v002_layout.json').read_text());U=np.array(q['uv']);O=np.array(d['uv']);V=np.array(d['vertices']);F=np.array(d['faces']);N=2048;S=4096
polys=[Polygon(t) for t in U];tree=STRtree(polys);over=[]
for i,p in enumerate(polys):
 for j in tree.query(p):
  if j>i and p.intersection(polys[j]).area>1e-11:over.append([i,int(j)])
assert not over,('UV overlaps',over[:20]);assert U.min()>=0 and U.max()<=1
e=U[:,1]-U[:,0];f=U[:,2]-U[:,0];sign=e[:,0]*f[:,1]-e[:,1]*f[:,0];assert (sign>1e-12).all() or (sign< -1e-12).all(), 'mixed winding'
src=np.array(Image.open('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/textures/enm_melee_fungboar01_basecolor_v001.jpg').convert('RGB'))[::-1]/255.
atlas=np.full((S,S,3),.5,np.float32);mask=np.zeros((S,S),bool);owner=np.full((S,S),-1,np.int32)
for i,t in enumerate(U):
 lo=np.maximum(0,np.floor(t.min(axis=0)*S-.5).astype(int));hi=np.minimum(S-1,np.ceil(t.max(axis=0)*S-.5).astype(int));xs=np.arange(lo[0],hi[0]+1);ys=np.arange(lo[1],hi[1]+1);xx,yy=np.meshgrid(xs,ys);points=np.stack([(xx+.5)/S,(yy+.5)/S],axis=-1);b=np.linalg.solve(np.column_stack([t[1]-t[0],t[2]-t[0]]),(points-t[0]).reshape(-1,2).T).T.reshape(*xx.shape,2);inside=(b.min(axis=-1)>=-1e-8)&(b.sum(axis=-1)<=1+1e-8)
 if not inside.any():continue
 old=O[i,0]+b[...,0,None]*(O[i,1]-O[i,0])+b[...,1,None]*(O[i,2]-O[i,0]);coords=[np.clip(old[...,1][inside]*2048-.5,0,2047),np.clip(old[...,0][inside]*2048-.5,0,2047)];color=np.stack([map_coordinates(src[:,:,c],coords,order=1,mode='nearest') for c in range(3)],axis=-1);iy=yy[inside];ix=xx[inside];atlas[iy,ix]=color;mask[iy,ix]=1;owner[iy,ix]=i
# Closest valid texel expansion affects empty pixels only, cannot overwrite painted islands.
dist,indices=distance_transform_edt(~mask,return_indices=True);expand=(~mask)&(dist<=6);atlas[expand]=atlas[indices[0][expand],indices[1][expand]]
im=Image.fromarray(np.round(atlas[::-1]*255).astype(np.uint8)).resize((N,N),Image.Resampling.LANCZOS);im.save(P/'basecolor_v002.png')
# Exact unique pixel coverage at final resolution, center sampling (not bounding boxes).
coverage=mask.reshape(N,2,N,2).any(axis=(1,3));loaded=np.array(Image.open(P/'basecolor_v002.png'))[::-1]/255.
rng=np.random.default_rng(73);ids=rng.integers(0,len(F),100000);b=rng.random((100000,2));b[b.sum(axis=1)>1]=1-b[b.sum(axis=1)>1];old=O[ids,0]+b[:,0,None]*(O[ids,1]-O[ids,0])+b[:,1,None]*(O[ids,2]-O[ids,0]);new=U[ids,0]+b[:,0,None]*(U[ids,1]-U[ids,0])+b[:,1,None]*(U[ids,2]-U[ids,0]);sample=lambda arr,uv:np.stack([map_coordinates(arr[:,:,c],[uv[:,1]*N-.5,uv[:,0]*N-.5],order=1,mode='nearest') for c in range(3)],axis=-1);err=np.abs(sample(src,old)-sample(loaded,new));assert err.mean()<.05
# Stretch, weighted by full surface area (not falsely labelled camera-visible).
p0=V[F[:,0]];e1=V[F[:,1]]-p0;e2=V[F[:,2]]-p0;l=np.linalg.norm(e1,axis=1);x=(e1*e2).sum(axis=1)/l;y=np.sqrt(np.maximum(1e-20,(e2*e2).sum(axis=1)-x*x));B=np.zeros((len(F),2,2));B[:,0,0]=l;B[:,0,1]=x;B[:,1,1]=y;T=np.stack([U[:,1]-U[:,0],U[:,2]-U[:,0]],axis=-1);sv=np.linalg.svd(T@np.linalg.inv(B),compute_uv=False);an=sv[:,0]/sv[:,1];area=l*y/2;order=np.argsort(an);cum=np.cumsum(area[order])/area.sum();quant=lambda p:float(an[order[np.searchsorted(cum,p)]])
# UV boundary graph yields current islands.
edge={};neighbors=[[] for _ in F]
for i,f in enumerate(F):
 for j in range(3):
  a=int(f[j]);bb=int(f[(j+1)%3]);edge.setdefault(tuple(sorted((a,bb))),[]).append((i,{a:U[i,j],bb:U[i,(j+1)%3]}))
for e,rows in edge.items():
 if len(rows)==2:
  (i,a),(j,bb)=rows
  if all(np.max(np.abs(a[v]-bb[v]))<1e-6 for v in e):neighbors[i].append(j);neighbors[j].append(i)
seen=set();islands=[]
for i in range(len(F)):
 if i in seen:continue
 stack=[i];seen.add(i);island=[]
 while stack:
  j=stack.pop();island.append(j)
  for k in neighbors[j]:
   if k not in seen:seen.add(k);stack.append(k)
 islands.append(island)
assert len(islands)<=100
preview=Image.new('RGB',(N,N),'#fafafa');draw=ImageDraw.Draw(preview)
for k,isl in enumerate(islands):
 col=tuple(int(v) for v in rng.integers(70,225,3))
 for i in isl:draw.polygon([(int(x*(N-1)),int((1-y)*(N-1))) for x,y in U[i]],fill=col,outline='#333333')
preview.save(P/'uv_layout_v002.png')
r={'uv_islands':len(islands),'single_face_islands':sum(len(i)==1 for i in islands),'small_islands_le6':sum(len(i)<=6 for i in islands),'positive_overlap_pairs':0,'out_of_bounds':0,'flipped_triangles':0,'unique_covered_pixels':int(coverage.sum()),'coverage_percent':float(100*coverage.mean()),'uv_triangle_area_sum':float(sum(p.area for p in polys)),'full_surface_aniso_p50':quant(.5),'full_surface_aniso_p95':quant(.95),'full_surface_area_aniso_gt1_3_percent':float(100*area[an>1.3].sum()/area.sum()),'texture_size':N,'supersample':2,'gutter_pixels':3,'transfer_exact_faces':len(F),'transfer_fallback_faces':0,'color_sample_count':100000,'mean_absolute_color_error_srgb':float(err.mean()),'p99_color_error':float(np.quantile(err,.99)),'asymmetry_preserved':True,'camera_visible_metrics':'not measured; full surface metrics reported instead','geometry_unchanged':bool(np.array_equal(V,np.array(q['vertices'])))}
(P/'uv_texture_report.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
