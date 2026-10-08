import bpy,json
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005');spec={'closeup':(400,200,680,450),'attic':(380,40,560,190)};out={}
for n in ['before_v004_closeup.png','radio_off_closeup.png','radio_a_closeup.png','radio_b_closeup.png','before_v004_attic.png','attic_off.png','attic_a.png','attic_b.png']:
 p=P/n
 if not p.exists():continue
 im=bpy.data.images.load(str(p),check_existing=False);w,h=im.size;kind='closeup' if 'closeup' in n else 'attic';x0,y0,x1,y1=spec[kind];px=list(im.pixels);red=green=0
 for y in range(y0,min(y1,h)):
  for x in range(x0,min(x1,w)):
   i=(y*w+x)*4;r,g,b=px[i],px[i+1],px[i+2]
   if r>.35 and r>g*1.35 and r>b*1.25:red+=1
   if g>.25 and g>r*1.25 and g>b*1.15:green+=1
 out[n]={'roi':[x0,y0,x1,y1],'roi_pixels':(x1-x0)*(y1-y0),'red_pixels':red,'green_pixels':green,'colored_pixels':red+green,'fraction':(red+green)/((x1-x0)*(y1-y0))};bpy.data.images.remove(im)
(P/'pixel_metrics_final_roi.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(out,ensure_ascii=False,indent=2))
