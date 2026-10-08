from pathlib import Path
import json,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'outputs/character_pipeline'/('directional_'+(sys.argv[1] if len(sys.argv)>1 else 'v027'))
specs=json.loads((OUT/'specs.json').read_text())
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
for state,s in specs.items():
    frames=[Image.open(p).convert('RGB') for p in sorted((OUT/state).glob('*.png'))]
    assert len(frames)==20
    frames[0].save(OUT/(state+'.gif'),save_all=True,append_images=frames[1:],duration=50 if s['speed']=='walking' else 40,loop=0)
for speed in ('walking','moving'):
    frames=[]
    for i in range(20):
        canvas=Image.new('RGB',(960,1050),'#252b33');d=ImageDraw.Draw(canvas)
        for row,(family,cn) in enumerate([('sidearm','短枪'),('longgun','长枪'),('machinegun','机枪')]):
            for col,(direction,dc) in enumerate([('strafe_left','左平移'),('strafe_right','右平移'),('backward','后退（侧视）')]):
                state=f'{family}_{speed}_{direction}'
                canvas.paste(Image.open(OUT/state/f'{i:03}.png').resize((320,320)),(col*320,row*350+30))
                d.text((col*320+10,row*350+4),cn+' '+dc,font=font,fill='white')
        frames.append(canvas)
    frames[0].save(OUT/(speed+'_overview.gif'),save_all=True,append_images=frames[1:],duration=50 if speed=='walking' else 40,loop=0)
    frames[5].save(OUT/(speed+'_overview.png'))
print('PREVIEWS_PACKAGED')
