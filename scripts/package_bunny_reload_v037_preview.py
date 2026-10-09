from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/reload_v037'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
frames=[]
for i in range(82,123):
    frame=Image.new('RGB',(540,574),'#26323c')
    frame.paste(Image.open(O/'frames'/f'{i:03}.png').convert('RGB').resize((540,540)),(0,34))
    ImageDraw.Draw(frame).text((12,7),'机枪换弹 · 左前45° / 枪口上抬',fill='white',font=font)
    frames.append(frame)
frames[0].save(O/'reload.gif',save_all=True,append_images=frames[1:],duration=50,loop=0)
sheet=Image.new('RGB',(1620,574),'#26323c')
for i,n in enumerate([0,16,29]):sheet.paste(frames[n],(i*540,0))
sheet.save(O/'reload_contact_sheet.png')
print('RELOAD_PREVIEW_PACKAGED',len(frames))
