from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
import json,math
O=Path(__file__).resolve().parents[1]
cat=json.loads((O/'component_packages_v001/catalog.json').read_text())
font='/System/Library/Fonts/STHeiti Medium.ttc'
f=ImageFont.truetype(font,22);small=ImageFont.truetype(font,15);title=ImageFont.truetype(font,34)
groups=list(dict.fromkeys(p['category'] for p in cat))
W=1800;H=160+len(groups)*285
im=Image.new('RGB',(W,H),(31,37,43));d=ImageDraw.Draw(im)
d.text((32,25),'天台区块  /  模块化组件库 v001',font=title,fill=(235,240,243))
d.text((34,78),'37 个独立资产包  ·  四共享材质  ·  标准外墙 5 × 0.30 × 11.9 m  ·  Blender 制作源',font=f,fill=(170,186,194))
for gi,g in enumerate(groups):
    y=150+gi*285;d.line((30,y-12,W-30,y-12),fill=(65,78,87),width=1)
    d.text((30,y),g.replace('_','  '),font=f,fill=(191,207,203))
    members=[p for p in cat if p['category']==g]
    for i,p in enumerate(members):
        x=265+i*250
        thumb=Image.open(O/'renders/components'/f'{p["slug"]}.png').convert('RGBA');thumb.thumbnail((240,220))
        im.paste(thumb,(x+(240-thumb.width)//2,y+4),thumb)
        d.text((x+4,y+225),p['name_zh'],font=f,fill=(232,236,239))
        d.text((x+4,y+253),' × '.join(f'{v:.2f}' for v in p['bounds_size'])+' m',font=small,fill=(155,173,184))
im.save(O/'renders/05_全部组件总览.png')
