from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];O=R/'outputs/character_pipeline/switch_v032'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
frames=[]
for i in range(139):
    p=O/'switch'/f'{i:03}.png'
    if not p.exists():break
    label='按1收起主武器 · 双枪背负' if i<28 else '空手前进 · 双臂交替前后摆动' if i<52 else '空手后退 · 双臂交替前后摆动' if i<76 else '按2从背后取出副武器' if i<97 else '按1 · 先收副武器，再取主武器' if i<118 else '按2切换副武器'
    frame=Image.new('RGB',(540,574),'#26323c');frame.paste(Image.open(p).convert('RGB').resize((540,540)),(0,34))
    ImageDraw.Draw(frame).text((12,7),label,fill='white',font=font);frames.append(frame)
frames[0].save(O/'weapon_switch.gif',save_all=True,append_images=frames[1:],duration=50,loop=0)
frames[20].save(O/'both_stowed.png')
print('SWITCH_PREVIEW_PACKAGED',len(frames))
