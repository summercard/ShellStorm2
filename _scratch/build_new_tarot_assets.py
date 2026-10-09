from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
src = Path(r"C:/Users/zhuangmenghong/Desktop/新塔罗牌")
out = Path(r"I:/工作项目/shellstrom2/ShellStorm2/outputs/new_tarot_inspect")
out.mkdir(parents=True, exist_ok=True)
files = sorted(src.glob("*.png"))
files = [p for p in files if p.name != "霓虹兔灵塔罗卡牌图鉴.png"]
all_cards=[]
for si,p in enumerate(files,1):
 im=Image.open(p).convert('RGB')
 sheet=[]
 for r in range(2):
  for c in range(5):
   x0=7+c*306; y0=4+r*512
   card=im.crop((x0,y0,min(x0+296,im.width),min(y0+503,im.height)))
   path=out/f'sheet{si}_{r*5+c+1:02d}.png'; card.save(path)
   sheet.append(card); all_cards.append((si,r*5+c+1,p.stem,card))
 # enlarged bottom/title strips, 5 across, 2 rows
 panel=Image.new('RGB',(5*320,2*150),'#202020'); d=ImageDraw.Draw(panel)
 for j,card in enumerate(sheet):
  strip=card.crop((0,395,296,503)).resize((296,108))
  x=(j%5)*320+12; y=(j//5)*150+20
  panel.paste(strip,(x,y)); d.text(((j%5)*320+8,y-16),f'{si}-{j+1}',fill='white')
 panel.save(out/f'sheet{si}_titles.png')
# all full cards, readable 5 across
panel=Image.new('RGB',(5*320,16*360),'#202020'); d=ImageDraw.Draw(panel)
for i,(si,n,name,card) in enumerate(all_cards):
 t=card.resize((190,322))
 x=(i%5)*320+65; y=(i//5)*360+25
 panel.paste(t,(x,y)); d.text(((i%5)*320+8,y+326),f'S{si} C{n}',fill='white')
panel.save(out/'contact_readable.png')
print('count',len(all_cards))
