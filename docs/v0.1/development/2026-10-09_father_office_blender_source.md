# 98F 父亲办公室 Blender 源

- 功能：ASSET-PIPELINE / WORLD-BLOCKS；工程版本0.1.0。
- 来源：用户参考图与后续更正“98F最里面的房间”；原布局 `source/art/blender/master_office_layout/source/block_00_master_office_layout_v002.layout.json`。
- 资产：`ENV-BATTLE-FATHER-OFFICE-SOURCE` v002，场景分账本资产主表第836行，Blender源已完成；未接入Godot。
- 源：`assets/art/environments/master_office_3d/source/env_father_office/v002/env_father_office_source_v002.blend`。
- 范围：15×20m、可见墙11.9m，入口保留东侧Y=2.5m。24组件/270实例；保留制作源、独立输出、完整围护与剖视视图层、24独立组件Blend。
- 表现：软包长沙发、织毯、枯植、奖杯/标本陈列、散落纸张、倒柜、碎石与不规则破墙。按公共色盘四材质角色制作。

## 验证

- Blender 5.2.2 LTS 后台重开与三张Cycles渲染完成；渲染启用OPTIX，HIP探测不可用警告不影响实际渲染。
- 任务尺寸、门位净空、组件原点、实例映射、包归属及原布局SHA保持检查通过。47,213个源和输出面通过逐面有面积、单格安全区PaletteUV检查。
- 标准 `validate_game_prop.py` 17项检查通过，四材质、外链公共色盘、主体/自发光分离均通过。
- 场景账本结构门禁与 `verify_ledger_split.py` 通过：1026资产，无缺失、额外资产或列摘要漂移。既有资产内容字段逐格保持。
- 全局文档门禁未通过：已有CHANGELOG第46行缺失链接、4个未注册验证用例，以及子进程Python缺少openpyxl。运行资产命名门禁未通过：报告兔子v022–v024导出、基地旋转椅等路径问题；本次无GLB、TSCN或运行代码变更。这些问题未用本房间制作绕过或修改。
- 未执行：Godot导出、优化、碰撞、导航、正式场景验收。用户视觉确认待完成；技术通过不表示高精度复刻或引擎接入。

技术细节与预览集中在源目录README及JSON验收记录。旧v001保留回溯，不作为正式交付。
