from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/reload_v034'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
frames=[]
for i in range(123):
    frame=Image.new('RGB',(540,574),'#26323c')
    frame.paste(Image.open(O/'frames'/f'{i:03}.png').convert('RGB').resize((540,540)),(0,34))
    label=['短枪换弹','长枪换弹','机枪换弹'][i//41]+' · 随实际换弹进度播放'
    ImageDraw.Draw(frame).text((12,7),label,fill='white',font=font);frames.append(frame)
frames[0].save(O/'reload.gif',save_all=True,append_images=frames[1:],duration=50,loop=0)
sheet=Image.new('RGB',(1620,574),'#26323c')
for i,n in enumerate([25,66,107]):sheet.paste(frames[n],(i*540,0))
sheet.save(O/'reload_contact_sheet.png')
print('RELOAD_PREVIEW_PACKAGED',len(frames))
