from pathlib import Path
from PIL import Image
src=Path(r'C:/Users/zhuangmenghong/Desktop/新塔罗牌')
for p in sorted(src.glob('*.png')):
 if p.name=='霓虹兔灵塔罗卡牌图鉴.png': continue
 im=Image.open(p).convert('RGB'); print('\n',p.name)
 for pos in [1,2,3,4,5,6,7,8,9,10]:
  r,c=divmod(pos-1,5); xl=round(c*im.width/5); xr=round((c+1)*im.width/5); yt=r*512; yb=(r+1)*512
  pts=[]
  for y in range(yt,yb):
   for x in range(xl,xr):
    R,G,B=im.getpixel((x,y))
    if G>80 and G>R*1.25 and G>B*1.12: pts.append((x,y))
  print(pos,(min(x for x,y in pts)-xl,min(y for x,y in pts)-yt,max(x for x,y in pts)-xl,max(y for x,y in pts)-yt),len(pts))
