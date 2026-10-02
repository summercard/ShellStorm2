"""Record the actual model-render review, separate from user visual approval."""
import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[2];F=R/'assets/art/environments/open_world/source/tower_04/v008'
cat=json.loads((F/'catalog.json').read_text(encoding='utf8'))
audit=json.loads((F/'qa/overgrowth_audit.json').read_text(encoding='utf8'))
palette=json.loads((F/'qa/palette_validation.json').read_text(encoding='utf8'))
digest=hashlib.sha256((R/cat['source_blend']).read_bytes()).hexdigest()
assert audit['passed'] and palette['passed'] and audit['source_sha256']==digest
notes={
 'previews/01_塔4_参考全景.png':'五层和月牙凹口完整；外缘绿带与多层垂挂可读，整体仍为游戏化建筑。',
 'previews/02_塔4_俯视轮廓.png':'路线连续、棚架有透空；圆楼屋顶是不规则片状绿团，未封死通路。',
 'previews/03_塔4_天台花园.png':'花池向边缘溢生，绿团与营地分层；中央开敞铺装仍保留。',
 'previews/04_塔4_椭圆左翼.png':'四层返野带、长藤与缺损幕墙同时可见；结构楼板保持原形。',
 'previews/05_塔4_玻璃亭与遮阳棚.png':'棚边密集、锈色框架清楚，玻璃亭缺片；原材质呈风格化反光，非写实透明玻璃。',
 'previews/06_塔4_近景设备与节点.png':'设备位置不变，藤叶覆盖立柱和棚边，叶团与骨架有分层。',
 'mood/末世_平台总览.png':'完整建筑入镜，棕雾已降低；棚边和立面植被成为显著轮廓。',
 'mood/末世_棚下主街.png':'头顶形成浓密叶冠、疏密不一垂挂，右侧花池溢生；主线可读。',
 'mood/末世_右侧营地.png':'营地被成片植被包围，原兔雕塑和设施可辨，未扩大玩法范围。',
 'mood/末世_棚柱节点.png':'主干、分叉、棚边相连，三种阔叶形态与不同长度枝条可读。',
 'mood/末世_营地设施近景.png':'帐篷、水箱、太阳能板前后有叶团，棚架占据画面上部；设施仍偏整洁。',
 'mood/末世_地表近景.png':'砖缝植物、碎屑、细小剥落与既有裂纹可见；地面比参考干净，未做写实积垢贴图。',
}
assert len(notes)==12
for p in notes:assert (F/p).is_file()
report={'passed':True,'scope':'制作方对本轮高覆盖植被修订的自检；不代表用户认可或与效果图完全一致',
 'review_date':'2026-10-02','source_sha256':digest,'user_visual_confirmation':'pending','full_reference_match':False,
 'criteria':{'dense_canopy_is_visual_focus':True,'column_roof_facade_growth':True,'irregular_broadleaf_drapes':True,'visible_nonstructural_damage':True,'original_routes_readable':True},
 'images':[{'path':p,'sha256':hashlib.sha256((F/p).read_bytes()).hexdigest(),'observation':n} for p,n in notes.items()],
 'limits':['保留原低多边形/公共色盘美术语言，不冒充照片级效果图复刻。','参考中的密集城市背景未制作。','局部设备和地面仍比参考整洁；没有额外写实积垢纹理。','高密Blender源约608万输出面；未做引擎导入、LOD、碰撞、导航或运行性能验收。']}
(F/'qa/visual_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
cat['source_status']='dense_overgrowth_source_self_checked_user_review_pending'
cat['reference_atmosphere_status']='stylized_reference_interpretation_not_photoreal_match'
cat['source_sha256']=digest
(F/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('VISUAL_SELF_REVIEW_RECORDED',digest)
