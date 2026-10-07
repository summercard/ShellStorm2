"""Assemble actual Blender-rendered frames, without altering rendered poses."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs/character_pipeline/weapon_idle_v025'
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
specs = [('sidearm', '短枪 · 单手朝上', 3200), ('longgun', '长枪 · 胸前斜持', 3600), ('machinegun', '机枪 · 低位承重', 4000)]
sheet = Image.new('RGB', (1440, 540), '#252b33')
for index, (family, title, duration) in enumerate(specs):
    frames = [Image.open(p).convert('RGB') for p in sorted((OUT / family).glob('*.png'))]
    assert len(frames) == 32
    frames[0].save(OUT / (family + '_idle.gif'), save_all=True, append_images=frames[1:], duration=[round((i + 1) * duration / 32 / 10) * 10 - round(i * duration / 32 / 10) * 10 for i in range(32)], loop=0)
    sheet.paste(frames[0].resize((480, 480)), (index * 480, 50))
    draw = ImageDraw.Draw(sheet)
    draw.text((index * 480 + 20, 12), title, font=font, fill='white')
    draw.text((index * 480 + 310, 20), '%.1f 秒循环' % (duration / 1000), font=small, fill='#d4d9e0')
sheet.save(OUT / 'standing_weapon_idles.png')
print(OUT / 'standing_weapon_idles.png')
