# v0.1 工具类总索引

适用工程版本：`0.1.0`。归属模块：`TOOLING`。本页维护开发与内容制作工具的分类、入口和交接关系；具体规则由工具独立设计拥有，开发结果保存在独立开发记录中。

总设计入口：[游戏总设计 §20](README.md)；统一追溯：[模块与功能索引](MODULE_INDEX.md)、[机器注册表](feature_registry.json)；文档维护规则：[文档标准 §9](../DOCUMENTATION_STANDARD.md)。

## 1. 工具类定位

工具类是支持开发者与美术人员生产内容的横向模块。具备独立编辑界面、输入输出契约和维护周期的工具，以 `TOOL-*` 登记；场景编辑器归入“工具类 / 场景美术制作”。工具的实现与验收状态单独跟踪，七大玩法系统的数量和完成度口径保持原定义。

场景制作链路为：**白盒与共享组件目录 → Godot组件场景编辑器 → 保存组件引用的美术TSCN → 关卡装配接入与验收**。其中，制作美术布局由工具负责，将布局加入关卡模板池和运行时装配由关卡模块负责。共享组件的制作、导入、版本与资产登记继续遵循资产生产链路。

## 2. 已登记独立工具

| 工具 | FeatureID | 分类与Owner | 主设计与使用入口 | 开发记录 | 当前范围与状态 |
|---|---|---|---|---|---|
| Godot组件场景编辑器 | `TOOL-SCENE-EDITOR` | 工具类 / 场景美术制作；`ShellStormSceneBuilder EditorPlugin` | [独立设计](design/组件场景编辑器设计.md)、[使用说明](../../tools/scene_builder/README.md)；Godot右侧“场景工坊” | [初版](development/2026-10-29_component_scene_editor.md)、[r5工作台](development/2026-10-29_scene_builder_workbench.md)、[r6历史采集](development/2026-10-29_scene_builder_runtime_source.md)、[r7唯一房间列表](development/2026-11-01_scene_workshop_unique_rooms.md)、[r8固定陈设](development/2026-11-01_fixed_room_furnishing.md) | r7默认打开只读列出现行游戏绑定的正式房间TSCN，同路径唯一，不要求种子或Python；新建/关联白盒使用专用选择器。共享组件检索、预览、摆放、笔刷、灯光、撤销和原生保存沿用。工具状态保持 `partial`；r7统计与验收见原记录。r8冻结固定陈设归正式TSCN、全部合法门位制作净空；58份文本PackedScene格式统一，旧组/metadata兼容；r8陈设保持、全门位制作净空、编辑器保存负测与4房画面专项已通过；额外可玩回归失败/超时及守卫覆盖限制见r8记录，不升级整关验收。 |

## 3. 场景编辑器的事实所有者

| 内容 | 事实所有者 | 工具的职责 |
|---|---|---|
| 组件ID与稳定Prefab路径 | [共享组件catalog](../../assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json) | 读取和检索已有登记；刷新目录 |
| 模型、材质、碰撞与原点 | 共享组件Prefab及其制作源 | 实例化稳定引用，沿组件更新链迭代 |
| 组件摆位、房内灯光与作者编辑 | 正式美术TSCN；远征03固定陈设（含Furn_*）按r8契约禁止运行时覆盖 | 打开同一正式文件，原生编辑；制作时校验全部合法门位前净空 |
| 正式房间身份与可用资源路径 | 现行关卡绑定及共享运行资源契约 | 只读发现、按路径去重，不另建种子房间或替代登记 |
| 画笔、吸附参数、白盒参考与编辑辅助 | EditorPlugin / Godot编辑器会话 | 编辑交互、整笔撤销、辅助不入盘 |
| 关卡骨架、动态门位与房间生成 | `WORLD-PLAN`及运行时装配器 | 作为布局制作约束与接入交接依据 |

程序入口：[插件配置](../../addons/shellstorm_scene_builder/plugin.cfg)、[工具实现](../../tools/scene_builder/editor_plugin.gd)。独立验收入口：[布局与保存专项](../../tools/scene_builder/test_layout_model.gd)、[原生编辑器交互专项](../../tools/scene_builder/test_editor_actions.gd)。隔离用户目录的启动方式见使用说明。

## 4. 新增与维护规则

每个独立工具都要在以下位置留下同一个稳定ID：

1. 总设计的工具类章节：用途、生产链位置与范围。
2. 本索引：工具分类、Owner、操作入口、输入输出、状态和开发记录。
3. `MODULE_INDEX.md`与`feature_registry.json`：独立设计、实现Owner、验收入口和当前状态。
4. 独立设计：接口、输出所有权、失败与撤销、保存与发行边界。
5. `development/`：开发变更、实际验证结果、错误和未执行项。

工具功能变化时同步以上链路；新增普通检查脚本或辅助脚本时，在所属模块下登记用途与验收即可。现有Blender白盒搭建入口见[关卡区块设计](05.1_关卡区块设计.md)及[开发记录](development/2026-09-14_blender_level_builder_addon.md)，其制作源阶段与Godot正式布局阶段分别维护。
