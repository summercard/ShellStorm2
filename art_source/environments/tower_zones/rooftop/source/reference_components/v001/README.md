# 天台区块参考组件库 v001

打开 `天台区块_参考组件库_v001.blend`：

- 场景「天台组件库与参考拼装_v001」：37个独立组件包，按10类排列；隐藏的制作集合保留水泥结构、面板、紧固件、叶片等166个可编辑网格，游戏输出为38个网格。
- 场景「天台_参考拼装展示」：Collection实例拼装演示，50×50m示例地面；可单独移动、替换每个模块。不是项目90×80m正式天台，也不覆盖原有天台源。
- `component_packages_v001/`：与Blender集合逐包对应；`catalog.json`查尺寸/原点/依赖/接点，`tree.txt`查目录。
- `reference_assembly.json`：演示实例位置；`reference/rooftop_reference.png`：用户原始参考。
- `renders/`：全景、俯视、房间近景、外墙接口、结构素模和37件独立预览。

外墙实墙和窗墙均为 **5×0.30×11.9m**，独立底面Z=0；未来逻辑与阻挡保持 **5×0.30×12m**。装配演示的外墙基准Z=-12。女儿墙是独立1.8m矮围护，不能拿它替代12m外墙阻挡。

所有包以XY包围盒中心、底面Z=0为局部原点，正面-Y。地砖厚0.30m，演示摆在Z=-0.30；未来使用现有厚度居中地砖包装时应转换原点。挂藤墙的植物会超出墙体包络，碰撞只应覆盖墙体。房间前后左右由标准墙、窗墙、门洞墙重复组装；门/雨棚/绿化/空调独立。

源文件只有四个标准材质。唯一色盘外链项目公共PNG；无私有贴图或内嵌色盘。材质名称保持公共标准，实际颜色由PaletteUV控制；参考灰色混凝土在项目色盘中采用冷灰表达。

本批为Blender制作交付：未生成GLB、PackedScene、LOD或玩法碰撞，未改变Godot运行引用。灯具的真实点光在展示集合中，未来导入需要包装层明确接管。无动画。

验证：Blender后台运行 `qa/validate_rooftop.py`；使用仓库 `skills_drafts/blender-game-prop-standard/scripts/validate_game_prop.py --all-meshes --max-materials 4 --shared-palette <项目公共PNG>`；结果位于 `qa/task_validation.json` 和 `qa/material_validation.json`。
