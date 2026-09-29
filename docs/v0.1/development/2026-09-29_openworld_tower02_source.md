# 开放世界塔2 Blender源制作

- FeatureID：ASSET-PIPELINE；工程版本：0.1.0；资产版本：v001。
- 来源：用户提供施工高楼参考图，指定塔2、与主塔平级、平面70×50米；后续明确顶面灰色。
- 独立资产：ENV-OPENWORLD-TOWER02；不归入主塔内部房间或远征房型库。
- 主体楼板平面70×50米，底面Z=0，X/Y居中；20层×4.2米为参考图推定美术尺度，不构成玩法层高契约。塔吊和外架单独计算总包络。
- 源：`assets/art/environments/open_world/source/tower_02/v001/塔2_施工高楼_70x50m_v001.blend`。
- 62个独立包：21层结构、2核心筒、8立面脚手架、8爬架屏、1施工电梯、15屋顶柱、1固定材料堆、3屋顶模板、3塔吊。制作源隐藏，游戏输出默认显示；每包有磁盘清单。
- 屋顶平台与模板顶面使用公共色盘冷灰色，四共享材质，逐面有面积PaletteUV；贴图外链且未打包。
- 验收：`qa/palette_validation.json`记录逐面UV/材质检查；`qa/source_audit.json`记录独立包、尺寸、网格预算与唯一归属；`previews/`保存全景、俯视、屋顶、立面、背面五图。
- 本次为外观建筑源：楼梯为可编辑展示结构，未做可玩楼层洞口与导航契约；未导出GLB、未制作运行时碰撞/LOD、未接入Godot。账本仅登记Blender源完成。
- 可重建脚本：`tools/blender/build_openworld_tower02_v001.py`；最终灰顶与灯光：`tools/blender/set_tower02_gray_roof.py`。重建先运行构建器，再运行灰顶脚本与验收脚本。
- 用户原参考图位于 `C:/Users/zhuangmenghong/Desktop/d8422a61-6eb1-4d99-9cea-6c613997ba66.png`。
- 实测：主体楼板70.0×50.0m；含外架与三塔吊总包络118.918×56.255×135.046m；63个输出网格、241494三角形；源包归属验收通过。
- 全局门禁本轮退出1：文档门禁报告三个既有未注册验证场景（swivel_chairs、spawn_ramp、pushable_base_chairs）及子进程缺少openpyxl；运行命名门禁报告既有角色/椅子资源的带版本路径。本次没有修改这些资源或验证场景，不将全局门禁计为通过。
- 登记：场景账本资产主表第248行，ENV-OPENWORLD-TOWER02，Blender源已完成；查重公式、总览范围、下拉范围及无损基线已同步。structure与verify_ledger_split均退出0。场景域full退出1，报告152项已有资源问题，无tower_02/ENV-OPENWORLD-TOWER02条目；不批量回填其他资产哈希。
