import json,shutil,zipfile,hashlib
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
P=Path(__file__).parent;meta=json.loads((P/'animation_meta.json').read_text());out=Path('I:/工作项目/shellstrom2/outputs/little_zombie_animations_v001');out.mkdir(exist_ok=True);(out/'source/model').mkdir(parents=True,exist_ok=True);(out/'source/animation').mkdir(parents=True,exist_ok=True)
for field,sub in [('model','model'),('animation','animation')]:
 src=Path(meta[field]);shutil.copy2(src,out/'source'/sub/src.name);meta[field+'_sha256']=hashlib.sha256(src.read_bytes()).hexdigest()
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20);cards=[]
for e in meta['clips']:
 frames=[]
 for i in range(24 if e['loop'] else 25):
  im=Image.open(P/'animation_frames'/(e['id']+'_%02d.png'%i)).convert('RGB');canvas=Image.new('RGB',(420,456),'#f4f5f7');canvas.paste(im,(0,36));ImageDraw.Draw(canvas).text((10,7),e['scene'][3:]+' / '+str(e['duration'])+'s',font=font,fill='#1c2835');frames.append(canvas)
 durations=[round(e['duration']*1000/24)]*len(frames)
 if not e['loop']:durations[-1]=1000
 frames[0].save(out/(e['id']+'.gif'),save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2)
 strip=Image.new('RGB',(420*4,456),'white')
 for k,j in enumerate([0,8,12,24]):
  im=Image.open(P/'animation_frames'/(e['id']+'_%02d.png'%j)).convert('RGB');strip.paste(im,(k*420,36));ImageDraw.Draw(strip).text((k*420+10,7),e['scene'][3:]+'  '+str(round(j/24*e['duration'],2))+'s',font=font,fill='#1c2835')
 strip.save(out/(e['id']+'_关键帧.png'))
 cards.append('<section><h2>'+e['scene'][3:]+'</h2><img src="'+e['id']+'.gif"><p>'+str(e['duration'])+' 秒 · '+('循环' if e['loop'] else '源动作单次；此GIF为方便查看重复播放')+'</p></section>')
html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>小僵尸 六动作预览</title><style>body{background:#f4f5f7;color:#172635;font:16px sans-serif;margin:32px}main{display:grid;grid-template-columns:repeat(3,minmax(260px,1fr));gap:20px}section{background:white;padding:16px;border-radius:12px}img{width:100%}h2{font-size:19px}p{color:#586574}</style><h1>小僵尸 · 六段动画</h1><p>v002 模型 / 独立动画源 v001 / 30fps / 未接入 Godot。解压保留 source 结构，在动画文件顶部场景列表切换六段。</p><main>'+''.join(cards)+'</main></html>'
(out/'动画预览.html').write_text(html,encoding='utf-8');meta['validation']=json.loads((P/'animation_validation.json').read_text());meta['status']='authored_source_checked_pending_art_review_and_runtime';meta['runtime_timing']={'telegraph':.38,'recovery':.34,'stagger':.16,'note':'art clip durations differ; later integrate by state phase, no gameplay changes'};meta['limitations']=['无完整12状态映射，仅用户指定6段动作。','地面检测为最低网格高度；不等同支撑脚锁定或零滑步。','大幅姿态存在低模软组织压缩，未声明零自穿插。','动态预览按每动作24个采样间隔输出，不是逐帧视频。']
(out/'animation_transfer_ledger_v001.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
with zipfile.ZipFile(out/'小僵尸_六动作_Blender源文件包.zip','w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted((out/'source').rglob('*.blend')):z.write(f,f.relative_to(out))
 z.write(out/'animation_transfer_ledger_v001.json','animation_transfer_ledger_v001.json')
print('ANIMATION_PACKAGE_READY',out)
