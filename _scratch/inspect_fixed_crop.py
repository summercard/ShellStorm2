from pathlib import Path
from PIL import Image,ImageDraw
src=Path(r'C:/Users/zhuangmenghong/Desktop/新塔罗牌')
files=sorted([p for p in src.glob('*.png') if p.name!='霓虹兔灵塔罗卡牌图鉴.png'])
out=Path(r'I:/工作项目/shellstrom2/ShellStorm2/outputs/new_tarot_install/fixed_inspect'); out.mkdir(exist_ok=True)
ims=[]
for si,p in enumerate(files,1):
 im=Image.open(p).convert('RGB')
 for pos in range(1,11):
  r,c=divmod(pos-1,5); cl=round(c*im.width/5); cr=round((c+1)*im.width/5); yt=r*512
  card=im.crop((cl+12,yt+7,cr-12,yt+505)); card.thumbnail((135,230)); ims.append((si,pos,card))
panel=Image.new('RGB',(5*160,16*260),'#222');d=ImageDraw.Draw(panel)
for i,(s,n,im) in enumerate(ims):
 x=i%5*160+12;y=i//5*260+20;panel.paste(im,(x,y));d.text((i%5*160+3,y+232),f'{s}-{n}',fill='white')
panel.save(out/'fixed_contact.png')
