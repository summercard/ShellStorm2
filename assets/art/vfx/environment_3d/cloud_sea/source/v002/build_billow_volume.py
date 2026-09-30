"""Offline periodic 3D density: R broad rounded Worley, G medium Worley, B soft erosion.
Original image-2 density retained separately; no scenery pixels enter the game texture.
"""
from pathlib import Path
import numpy as np
import json
from PIL import Image
SOURCE=Path(__file__).resolve().parent
ASSET=SOURCE.parent.parent
N=128
rng=np.random.default_rng(990932)
z,y,x=np.meshgrid(np.arange(N,dtype=np.float32)/N,np.arange(N,dtype=np.float32)/N,np.arange(N,dtype=np.float32)/N,indexing='ij')
coords=np.stack([x,y,z],axis=-1)
def worley(cells):
 p=coords*cells
 base=np.floor(p).astype(np.int16)
 frac=p-base
 points=rng.uniform(.15,.85,(cells,cells,cells,3)).astype(np.float32)
 dist=np.full((N,N,N),9,dtype=np.float32)
 for dz in [-1,0,1]:
  for dy in [-1,0,1]:
   for dx in [-1,0,1]:
    offset=np.array([dx,dy,dz],dtype=np.int16)
    cell=(base+offset)%cells
    feature=points[cell[...,2],cell[...,1],cell[...,0]]+offset
    dist=np.minimum(dist,np.sqrt(np.sum((feature-frac)**2,axis=-1)))
 return np.clip(1-dist/1.08,0,1)
def value_noise(cells):
 p=coords*cells;b=np.floor(p).astype(np.int16);f=p-b;f=f*f*(3-2*f)
 table=rng.random((cells,cells,cells),dtype=np.float32);result=np.zeros((N,N,N),dtype=np.float32)
 for dz in [0,1]:
  for dy in [0,1]:
   for dx in [0,1]:
    c=(b+np.array([dx,dy,dz]))%cells
    weight=(f[...,0] if dx else 1-f[...,0])*(f[...,1] if dy else 1-f[...,1])*(f[...,2] if dz else 1-f[...,2])
    result+=table[c[...,2],c[...,1],c[...,0]]*weight
 return result
broad=worley(7);medium=worley(17)
erosion=value_noise(13)*.65+value_noise(31)*.35
# Increasing contrast preserves full curved lobes rather than a flat uniformly gray field.
channels=np.stack([np.clip(broad*1.22+.08,0,1),np.clip(medium*1.15+.05,0,1),erosion],axis=-1)
(SOURCE/'noise.raw').write_bytes(np.round(channels*255).astype('uint8').tobytes())
spec=json.loads((SOURCE/'texture_bake.json').read_text('utf-8'))
spec['noise']={'dimensions':[128,128,128],'channels':'RGB: broad Worley / medium Worley / soft erosion'}
(SOURCE/'texture_bake.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
img=Image.open(SOURCE/'T_VFX_Cloud_Billow_Density_01_TILE.png').convert('L')
# Shader samples are data, not sRGB color. Generated source is never modified.
img.save(ASSET/'cloud_billow_density.png')
print('BILLOW_VOLUME_BAKED dimensions=128^3 channels=RGB bytes='+str(N**3*3))
