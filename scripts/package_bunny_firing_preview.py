"""Contact sheet/GIF from real Godot frames, without altering source imagery."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/firing_v030'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
frames=[]
for i in range(16):
    canvas=Image.new('RGB',(960,1020),'#26323c');draw=ImageDraw.Draw(canvas)
    for row,(family,label) in enumerate([('sidearm','短枪'),('longgun','长枪'),('machinegun','机枪')]):
        for col,(direction,title) in enumerate([('strafe_left','左平移'),('strafe_right','右平移'),('backward','后退')]):
            canvas.paste(Image.open(O/(family+'_'+direction)/f'{i:03}.png').convert('RGB').resize((320,320)),(col*320,row*340+20))
            draw.text((col*320+12,row*340),label+' · '+title+'射击',fill='white',font=font)
    frames.append(canvas)
frames[0].save(O/'gameplay_firing.gif',save_all=True,append_images=frames[1:],duration=40,loop=0)
frames[4].save(O/'gameplay_firing.png')
print('FIRING_PREVIEW_PACKAGED')
