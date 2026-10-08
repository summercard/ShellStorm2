from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/runtime_v029'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
frames=[]
for i in range(20):
    canvas=Image.new('RGB',(960,350),'#26323c');draw=ImageDraw.Draw(canvas)
    for j,(family,label) in enumerate([('sidearm','短枪'),('longgun','长枪'),('machinegun','机枪')]):
        canvas.paste(Image.open(O/family/f'{i:03}.png').convert('RGB').resize((320,320)),(j*320,30))
        draw.text((j*320+15,5),label+' · 游戏内左平移',fill='white',font=font)
    frames.append(canvas)
frames[0].save(O/'gameplay_carry.gif',save_all=True,append_images=frames[1:],duration=30,loop=0)
frames[5].save(O/'gameplay_carry.png')
print('GAMEPLAY_PREVIEW_PACKAGED')
