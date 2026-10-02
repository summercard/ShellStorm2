"""Store the per-view lower-structure assessment, with immutable-top evidence."""
import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[2];F=R/'assets/art/environments/open_world/source/tower_04/v009'
cat=json.loads((F/'catalog.json').read_text(encoding='utf8'));sha=hashlib.sha256((R/cat['source_blend']).read_bytes()).hexdigest()
qa=json.loads((F/'qa/lower_structure_audit.json').read_text(encoding='utf8'));uv=json.loads((F/'qa/palette_validation.json').read_text(encoding='utf8'))
assert qa['passed'] and uv['passed'] and qa['source_sha256']==sha
observations={
 '参考全景.png':'原五层通底青色幕墙消失；左侧架空、圆弧退台与跨层肋，中央通透空间和右翼厚实墙/内退窗带均可见；顶层原轮廓保留。',
 '俯视轮廓.png':'屋面、路线、花池、棚架、设施和顶层植被保持原布局；下层走廊位于月牙凹口下部。',
 '下部_左楼架空与退台.png':'独立大柱承托左楼，突出退台分出单层下段和跨层上段；窗洞可见真实内部楼板，无实心圆柱填充。',
 '下部_右翼窗墙.png':'宽竖向混凝土实墙、厚层间边梁、内退窗梃与缺片玻璃关系明确；三段不等高窗墙替代五排等高玻璃。',
 '下部_中央架空.png':'中央原封闭体量打开；9m联系走廊连接左楼，末段下降至右翼7.8m接口，大柱与主平台相接。'}
images=[]
for name,note in observations.items():
 p=F/'previews'/name;assert p.is_file();images.append({'path':'previews/'+name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'observation':note})
report={'passed':True,'source_sha256':sha,'review_date':'2026-10-02','review_scope':'制作方对用户可见下部结构的逐图复核；不代表单张图片提供了精确米制尺寸或背面信息','user_visual_confirmation':'pending','top_unchanged':qa['top_unchanged'],'images':images,
 'reference_structure_features':['架空弧形商场','突出环形退台','跨层圆角混凝土肋','细窗梃及破损开口','中央架空与下层连接','右翼厚混凝土及内退窗带'],
 'comparison':{'before':'../v008/previews/01_塔4_参考全景.png','after':'previews/参考全景.png','camera':'CAM_参考全景','unchanged_camera_and_lights':True,'resolution':[1600,1000],'cycles_samples':48},
 'inferences':['左楼9/14.3/19.6m、右翼0.45/7.8/15.8m为依据原25m屋顶锚点推定的制作标高。','参考遮挡的背侧使用同一结构体系补足。','下层联系走廊的完整转折与坡段是连接既有两端标高的必要补全。'],
 'limits':['原色盘/风格化材质保持，不声称照片级表面复刻。','背景城市、地面场地不属于本次红线建筑范围。','仅Blender源；未导入Godot或进行运行性能验收。']}
(F/'qa/visual_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
cat['source_status']='lower_structure_self_checked_user_review_pending';cat['reference_projection']='locked v008 roof anchors; visible lower structure reconstructed from single reference view';cat['uncertainties']=report['inferences'];cat['source_sha256']=sha
(F/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('LOWER_STRUCTURE_VISUAL_REVIEW',sha)
