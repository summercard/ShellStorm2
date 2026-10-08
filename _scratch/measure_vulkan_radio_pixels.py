import bpy,json
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005');names=['radio_off_closeup.png','radio_a_closeup.png','radio_b_closeup.png','attic_off.png','attic_a.png','attic_b.png','before_v004_closeup.png','before_v004_attic.png'];out={}
for n in names:
 p=P/n
 if not p.exists():continue
 im=bpy.data.images.load(str(p),check_existing=False);w,h=im.size;px=list(im.pixels);red=green=0
 for i in range(0,len(px),4):
  r,g,b=px[i],px[i+1],px[i+2]
  if r>.35 and r>g*1.35 and r>b*1.25:red+=1
  if g>.25 and g>r*1.25 and g>b*1.15:green+=1
 out[n]={'size':[w,h],'red_pixels':red,'green_pixels':green,'colored_pixels':red+green,'fraction':(red+green)/(w*h)};bpy.data.images.remove(im)
(P/'pixel_metrics_final.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(out,ensure_ascii=False,indent=2))
