from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/carry_v031'
before=R/'outputs/character_pipeline/carry_v031_before'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
canvas=Image.new('RGB',(960,1020),'#26323c');draw=ImageDraw.Draw(canvas)
for row,(family,label) in enumerate([('longgun','长枪'),('machinegun','机枪')]):
    for col,(folder,title) in enumerate([(before,'调整前'),(O,'调整后')]):
        canvas.paste(Image.open(folder/(family+'_idle_top.png')).convert('RGB').resize((480,480)),(col*480,row*510+30))
        draw.text((col*480+16,row*510+4),label+' · '+title,fill='white',font=font)
canvas.save(O/'carry_comparison.png')
frames=[]
for i in range(20):
    frame=Image.new('RGB',(720,390),'#26323c');draw=ImageDraw.Draw(frame)
    for j,(family,label) in enumerate([('longgun','长枪斜持'),('machinegun','机枪斜持 · 收近身体')]):
        frame.paste(Image.open(O/family/f'{i:03}.png').convert('RGB').resize((360,360)),(j*360,30))
        draw.text((j*360+12,4),label,fill='white',font=font)
    frames.append(frame)
frames[0].save(O/'carry_refined.gif',save_all=True,append_images=frames[1:],duration=30,loop=0)
print('V031_PREVIEW_PACKAGED')
