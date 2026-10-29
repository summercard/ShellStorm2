# v0.1 工具类总索引

适用工程版本：`0.1.0`。归属模块：`TOOLING`。本页维护开发与内容制作工具的分类、入口和交接关系；具体规则由工具独立设计拥有，开发结果保存在独立开发记录中。

总设计入口：[游戏总设计 §20](README.md)；统一追溯：[模块与功能索引](MODULE_INDEX.md)、[机器注册表](feature_registry.json)；文档维护规则：[文档标准 §9](../DOCUMENTATION_STANDARD.md)。

## 1. 工具类定位

工具类是支持开发者与美术人员生产内容的横向模块。具备独立编辑界面、输入输出契约和维护周期的工具，以 `TOOL-*` 登记；场景编辑器归入“工具类 / 场景美术制作”。工具的实现与验收状态单独跟踪，七大玩法系统的数量和完成度口径保持原定义。

场景制作链路为：**白盒与共享组件目录 → Godot组件场景编辑器 → 保存组件引用的美术TSCN → 关卡装配接入与验收**。其中，制作美术布局由工具负责，将布局加入关卡模板池和运行时装配由关卡模块负责。共享组件的制作、导入、版本与资产登记继续遵循资产生产链路。

## 2. 已登记独立工具

| 工具 | FeatureID | 分类与Owner | 主设计与使用入口 | 开发记录 | 当前范围与状态 |
|---|---|---|---|---|---|
| Godot组件场景编辑器 | `TOOL-SCENE-EDITOR` | 工具类 / 场景美术制作；`ShellStormSceneBuilder EditorPlugin` | [独立设计](design/组件场景编辑器设计.md)、[使用说明](../../tools/scene_builder/README.md)；Godot右侧“场景工坊” | [初版记录](development/2026-10-29_component_scene_editor.md)、[r5工作台重构](development/2026-10-29_scene_builder_workbench.md)、[r6实际房间](development/2026-10-29_scene_builder_runtime_source.md) | 已具备正式关卡/种子采集实际房间、保留2.8m壳体及门位、正式TSCN编辑与几何匹配回接，以及打开/新建/保存主流程、顶部模式按钮、可调大预览、后台读取/进度/重试与旧UI重建，以及房间/通道/EGT共享白盒检索、参考加载状态与可撤销关联、套件/类型两级组件索引、缩略图与旋转3D预览、自由放置/可选吸附、地面笔刷、灯光与原生撤销，以及关卡/套件/房名场景列表；验收收口状态保留为 `partial`，工具外错误见开发记录。运行房间来源与回接契约见r6；全种子、跨关卡和完整游戏验收未覆盖。 |

## 3. 场景编辑器的事实所有者

| 内容 | 事实所有者 | 工具的职责 |
|---|---|---|
| 组件ID与稳定Prefab路径 | [共享组件catalog](../../assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json) | 读取和检索已有登记；刷新目录 |
| 模型、材质、碰撞与原点 | 共享组件Prefab及其制作源 | 实例化稳定引用，沿组件更新链迭代 |
| 组件摆位、房内灯光与作者编辑 | 正式美术TSCN | 原生选择、移动、旋转、保存、另存变体 |
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
