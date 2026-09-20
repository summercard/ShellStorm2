import json,shutil,hashlib,zipfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
P=Path(__file__).parent;root=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/melee_chaser');out=Path('I:/工作项目/shellstrom2/outputs/little_zombie_v002');out.mkdir(exist_ok=True)
blend=root/'source/model/enm_melee_fungboar01_model_v002.blend';shutil.copy2(blend,out/blend.name);tex=root/'source/model/textures/enm_melee_fungboar01_basecolor_v002.png';shutil.copy2(tex,out/tex.name)
for f in ['uv_layout_v002.png','uv_texture_report.json','rig_validation.json']:
 shutil.copy2(P/f,out/f)
for f in ['v002_front.png','v002_back.png','v002_side.png','v002_hand_rest.png','v002_hand_flex.png','v002_body_pose.png','v002_checker.png']:
 shutil.copy2(P/f,root/'previews'/f)
canvas=Image.new('RGB',(1440,1190),'#f4f5f7');draw=ImageDraw.Draw(canvas);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
items=[('v002_front.png','小僵尸 / 正面'),('v002_back.png','背面 / 保留左右差异'),('v002_body_pose.png','身体关节测试'),('v002_hand_rest.png','四指 / 静止'),('v002_hand_flex.png','手指 / 弯曲测试'),('uv_layout_v002.png','UV / 67岛，无单面岛')]
for k,(f,label) in enumerate(items):
 im=Image.open(P/f).convert('RGB');im.thumbnail((470,540));x=(k%3)*480+(480-im.width)//2;y=(k//3)*590+42;canvas.paste(im,(x,y));draw.text(((k%3)*480+15,(k//3)*590+8),label,fill='#18212d',font=font)
canvas.save(out/'小僵尸_v002_预览.png')
r={'display_name':'小僵尸','asset_id':'ENM-MELEE-FUNGBOAR01','source_path':str(blend),'source_sha256':hashlib.sha256(blend.read_bytes()).hexdigest(),'status':'model_only_pending_animation','uv':json.loads((P/'uv_texture_report.json').read_text()),'rig':json.loads((P/'rig_validation.json').read_text()),'limitations':['保留原网格，四指各两节。低模拓扑不保证大角度握拳无挤压。','67岛满足100上限，未达50最佳目标；全表面p95拉伸2.327，尚非低拉伸重拓扑版本。','未执行游戏相机可见面积射线统计、全部mipmap距离验收或Blender UI截图；已重开文件渲染与数值检查。','无正式动作库、无Godot接入。']}
(out/'小僵尸_v002_验收记录.json').write_text(json.dumps(r,ensure_ascii=False,indent=2).replace('\n','\r\n'),encoding='utf-8')
with zipfile.ZipFile(out/'小僵尸_v002_源文件包.zip','w',zipfile.ZIP_DEFLATED) as z:
 for f in [blend,tex,out/'小僵尸_v002_预览.png',out/'小僵尸_v002_验收记录.json',out/'uv_layout_v002.png']:
  z.write(f,('textures/'+f.name) if f==tex else f.name)
readme=root/'README.md';data=readme.read_text(encoding='utf-8');readme.write_bytes(data.replace('\r\n','\n').replace('\n','\r\n').encode('utf-8'))
print('DELIVERED',out)
