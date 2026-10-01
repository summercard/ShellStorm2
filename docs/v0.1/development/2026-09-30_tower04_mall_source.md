# 塔4曲线天台商场 · Blender源交付

FeatureID：ASSET-PIPELINE；工程版本0.1.0；资产`ENV-OPENWORLD-TOWER04`，源v001。设计与范围见[塔4美术源契约](../design/tower04_mall_source.md)。

## 本次内容

- 主体总包络150×50m，地面Z=0；左翼五层×5m、主体屋顶25m，长翼三层、主要露台15m，最高护栏26.27m。层高、不可见背部和功能附属件为美术补充，不改变主塔楼层契约。
- 还原左翼椭圆体块、回旋檐口、中部凹入、波浪悬挑露台、圆钝长叶格构棚及树形分叉柱、右端玻璃亭；补充弧形楼梯、9组曲线景观岛、分层灌木与棕榈、4个独立固定长椅、铺装、排水沟/检修盖、灯柱、入口雨棚、背侧风扇空调与楼梯出口。
- 112个独立资产包，122个输出网格；隐藏制作源与可见输出分离；Collection、磁盘manifest、catalog对应。未将整栋商场焊成单网格。
- 直接读取塔楼03原有四角色材质，无新建材质或迭代副本；独立审计逐节点/输入/连线对比原材质，签名一致。颜色只通过PaletteUV变化；公共色盘及其导入契约、塔楼03源文件的SHA保持不变；无MipMap设置保持关闭。
- 六张Cycles/OptiX真实渲染：参考全景、俯视轮廓、花园、左翼、玻璃亭/顶棚、背侧。相机与展示灯光不进入游戏输出。

## 源与验收

源：`assets/art/environments/open_world/source/tower_04/v001/塔4_曲线天台商场_150x50m_v001.blend`。复建脚本`tools/blender/build_tower04_mall_source.py`，独立审计`tools/blender/audit_tower04_mall_source.py`。

保存后重新打开源文件：包络、层数、材质来源、原资产锁定、112包唯一归属和清单对应全部通过，见源目录`qa/source_audit.json`。使用技能提供的严格`validate_game_prop.py --all-meshes --max-materials 4 --shared-palette ...`验收输出及隐藏源全部网格，逐面UV安全色格、有面积UV岛、活动/渲染层、Closest和唯一外链贴图全部通过，见`qa/palette_validation.json`。

场景账本追加第816行，状态仅“Blender源已完成”；查重公式、总览区间、下拉验证扩展至新行；无损基线新增本AssetID，原有资产内容/指纹及其它页签不变。不填写不存在的Prefab行；事务备份放项目外`../_scratch/tower04_ledger_backup/`。

结构门禁与无损基线检查通过（987项，9域）。场景域全量检查有153条历史SHA债务，改前/改后问题列表逐项相同；运行命名门禁仍有既有带版本路径/引用债务，本批不生成components/runtime路径。文档门禁仍有3个旧未注册验证入口，本批未新增Godot验证场景，不修复无关历史债务。最终输出52,187多边形；严格UV检查含隐藏制作源共104,374面全部通过。

## 未执行范围

本次仅Blender建筑源完成并登记；未导出GLB、未生成Godot PackedScene、未接入主场景、未制作碰撞/导航/LOD或游戏性能验收。未提交/推送。旧塔楼、基地、云海及其它未提交改动不在本次范围。
