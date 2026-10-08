import bpy,json
from pathlib import Path
P=Path('I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005');out={}
for n in ['before_v004_off_mask.png','before_v004_green_mask.png','v005_off_mask.png','v005_green_mask.png']:
 im=bpy.data.images.load(str(P/n),check_existing=False); w,h=im.size;p=list(im.pixels);a=0;rgb=0
 for i in range(0,len(p),4):
  r,g,b,al=p[i:i+4]
  if al>.02:a+=1
  if al>.02 and max(r,g,b)>.2:rgb+=1
 out[n]={'size':[w,h],'alpha_pixels':a,'nonblack_color_pixels':rgb,'fraction':a/(w*h)};bpy.data.images.remove(im)
(P/'status_light_pixel_metrics.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(out,ensure_ascii=False,indent=2))
