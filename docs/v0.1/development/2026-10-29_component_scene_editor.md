# 2026-10-29 Godot 组件场景编辑器

FeatureID：TOOL-SCENE-EDITOR；工程版本：0.1.0。
设计：[组件场景编辑器设计](../design/组件场景编辑器设计.md)。

## 交付范围

新增 `addons/shellstorm_scene_builder` 入口与 `tools/scene_builder` 编辑器实现，项目启用插件。读取现有218件共享组件，提供搜索、套件筛选、收藏和异步缩略图；白盒新建与任意白盒选择；单件、连续笔刷、矩形、直线铺放；格心吸附与标高；同格地砖替换、防叠加、擦除；点光与聚光灯，后续使用原生选择/移动/检查器。每次铺放在原生逐场景撤销历史中记一条操作。

正式TSCN只拥有组件实例根，Prefab内部保持实例边界。白盒预览与画笔辅助不设scene owner、不入盘，白盒原文件不覆盖。工具另有导出过滤插件；共享导出边界脚本与本机三个发行预设也添加排除项（`export_presets.cfg` 是本机忽略文件，不作为版本化交付唯一保障）。

示例：`tools/scene_builder/examples/component_room_demo.tscn`，复用正式组件，含棋盘地砖、墙段、办公室陈设与可编辑点光。它是工具演示，不登记为新生产资产，不进入发行包。

未修改关卡生成、刷怪、门状态机、存档或经济。远征03“模板→美术变体→运行房间”的正式接线仍是独立任务；本次交付用于快速制作和保存美术布局。地表笔刷是组件铺放，不包括地形雕刻、纹理权重绘制。

## 验收记录

- 生成/保存专项：`test_layout_model.gd`，exit 0，39项检查，预期故障0、非预期SCRIPT ERROR/ERROR 0。实际读取共享目录与Prefab；25×25矩形、L形、U形分别铺25/42/60格；验证插值、批次上限、相位、墙边界吸附、门墙放置、保存重开、引用边界和灯光属性。
- 原生编辑器交互专项：`test_editor_actions.gd`，headless editor exit 0，26项通过，预期引擎故障0、非预期SCRIPT ERROR/ERROR 0。覆盖真实3D输入回调的拖刷插值、矩形铺放、替换/擦除/灯光撤销与重做、变换后的组件分组、辅助不入盘；400件批次115ms，整批撤销与元数据计数正确。
- 最终撤销实现将do/undo绑定到场景节点原生方法，而非插件实例，避免停用插件后撤销回调悬空。最终复核 `native_undo_final.log`：exit 0、26项专项断言仍通过、400件117ms；**该轮工程启动不是无错误通过**：`BreakableClutter3D.gd:198` 的既有类型推断错误触发10条SCRIPT ERROR（含依赖编译链）及1条加载ERROR，涉及FateCardGameBridge等工具外脚本，未修改这些文件。当前工作区还有其他任务的运行时代码变化，未覆盖或回退。
- 带渲染编辑器：Compatibility真实渲染器，exit 0，专项28项通过（含两项渲染输出检查），400件批次114ms；已目视检查Godot编辑器自身视口输出 `component_editor.png`，参数横排且可访问。**本轮渲染日志不是零错误**：有1条非预期SCRIPT ERROR与对应1条加载ERROR，均来自未改动的 `res://_scratch/stair_rail_probe/probe_mid_map.gd:49`（dy类型推断）；另有旧房间UID重复、Compatibility不支持景深、多个编辑器占用语言服务端口的告警。工具自身未出现SCRIPT ERROR。原生桌面捕获工具超时，图片由Godot原生编辑器viewport输出，未把headless图当画面验收。
- `check_feature_traceability.py`：exit 0（42 features）；`check_domain_boundaries.py`、`check_level_decoupling.py`、`check_asset_runtime_naming.py`：exit 0。
- `check_documentation_contracts.py`：exit 1，15条工具外既有断链，以及原有3个未登记验收场景（verify_base_lamp_dynamics / verify_base_lamp_visual / verify_stairwell_turn_rail）。本工具文档链接和feature追溯无新增问题。检查时仅对进程设置UTF-8与bundled openpyxl的PYTHONPATH，未安装或修改系统Python。
- 未执行：整关游戏游玩、实际发行PCK导出；本次没有改变游戏运行链路。

测试进程启动前使用工程外隔离APPDATA。日志位于 `ShellStorm2-work/probes/2026-10-29_component_scene_editor/`。已有原文件备份位于 `ShellStorm2-backup/2026-10-29_component_scene_editor/before_edits/`。工作区里其他任务的参考资料与运行时代码修改未纳入本次编辑。

## 操作入口

Godot右侧“组件拼装”；未出现时在项目设置的插件页启用 ShellStorm Component Scene Builder。详细操作见 [工具说明](../../../tools/scene_builder/README.md)。

## 总设计与工具类归档补充（2026-10-29）

用户明确本模块属于工具类，要求先更新总设计，保持开发记录与索引可追溯。本次仅维护文档与机器登记元数据，工具代码、游戏运行代码、关卡资产与既有验收结论未变。

- 总设计 `docs/v0.1/README.md` 新增 §20“工具类：开发与内容制作”，登记用途、输入输出、Owner、保存所有权与关卡交接。
- 新增 `docs/v0.1/TOOL_INDEX.md` 作为工具类总索引，贯通总设计、独立设计、操作入口、程序入口、验收与本开发记录。
- 模块索引、设计目录和机器注册表统一标记 `TOOL-SCENE-EDITOR` 属于 `TOOLING` / 工具类 / 场景美术制作；机器登记补充 `category=tooling`、`module_id=TOOLING` 与 `tool_index`，保持既有状态和验收条目。
- 功能关系跟踪表区分通用测试工具链与独立编辑器；制作框架把本工具放入“②制作工具”。总设计中的七大玩法系统数量与完成度定义保持原口径。
- 文档标准新增工具类登记要求，覆盖总设计、工具索引、模块/机器登记、独立设计及开发记录，后续工具按同一链路维护。
- 本轮未重跑Godot或整关游戏测试；原工具测试只作为原开发记录的时点证据。

本轮文档验证：

- `check_feature_traceability.py`：exit 0，42个已登记ID的设计、Owner、开发记录与验收引用完整。
- `check_documentation_contracts.py`：exit 1；变更前16项、变更后16项，归一行号后对比新增问题0。保留原有15条断链与原有3个未登记验收场景汇总问题。
- `git diff --check`：exit 0；本轮维护文档使用CRLF。
- 工程外报告：`ShellStorm2-work/sessions/2026-10-29_scene_editor_tooling_docs/documentation_before.json` 与 `documentation_after.json`。
- 本轮写入前备份：`ShellStorm2-backup/2026-10-29_scene_editor_tooling_docs/before_edits/`。


## 资产浏览、自由放置与已有房间索引（r3）

来源：用户要求套件大标签/类型小标签索引、图片卡片与旋转3D预览，反馈关闭地砖吸附仍只能落在格点；要求已有美术场景按套件与房名列表打开，并补充优化操作手感。先将独立设计推进至r3，再实现本轮变化，同步总设计§20、工具总索引、模块索引、机器登记、工具说明及开发目录/CHANGELOG。

- 组件目录仍只有既有共享catalog一个事实源，当前218件、8个套件。新增 `catalog_tags.gd` 优先读取显式kit_tag/type_tag，存量按Prefab来源、slot_role、slug/category投影；套件与类型分别筛选，保留完整原名、ID、别名和路径检索，卡片只显示短标题与图像。
- `preview_stage.gd`、`asset_preview.gd`、`thumbnail_service.gd` 使用隔离World3D，将离树实例移除脚本/处理、碰撞、声音、粒子和资产自带灯光后渲染。预览只归一化临时包装节点，不修改共享模型/材质。卡片有加载占位、失败标记；视口按需渲染、缓存到`.godot/editor/scene_builder_thumbnails/`，依赖时间戳和重导入触发更新，切换筛选优先处理当前页。交互预览支持拖动旋转、滚轮缩放和复位。
- 放置的真正原因修复：旧代码无论格心开关如何都调用snap_point；现在显式网格吸附总开关默认关闭，只有开启时才取整。格心/墙边是吸附的相位选项；自由笔刷按间距采样，保留非格点起点。实际组件半透明轮廓跟随落点，合法绿色、越界/占门红色；辅助仍无owner、不会存盘。补测发现点击事件未同步轮廓位置，已补齐鼠标按键事件的预览更新。
- `scene_index.gd`、`scene_browser.gd` 不实例化房间脚本，只读扫描正式room_instances、场景根元数据与现有关卡设计源，按关卡/套件/房名显示树形列表；支持搜索、双击和原生打开；白盒默认隐藏，可独立显示；旧路径别名去重。目录外场景经文件入口打开/保存后仅记为本机编辑器路径书签，不另建场景登记事实源。显示名不重命名正式文件。
- 操作手感：场景列表、保存、模式、间距、标高与角度置顶；自由/吸附状态持续可见。切换套件卡片清除上一套件搜索和小标签，显示筛选命中数与空结果提示。预览可折叠、与列表可拖动分隔条调整高度；搜索输入短延时合并刷新。正式实例、原生撤销与保存边界保持原契约。

本轮没有制作/修改美术资产，不修改台账、房间摆位、关卡生成与运行时绑定；工作区其他任务的资产/台账/运行代码变更不属于本轮。已有文件备份：`ShellStorm2-backup/2026-10-29_scene_builder_asset_browser/before_edits/`。原始测试日志与真实渲染图片：`ShellStorm2-work/probes/2026-10-29_scene_builder_asset_browser/`。

### r3 最终验收

- 正式工程 `model_project_delivery.log`：exit 0，**59项通过**，预期故障0、非预期SCRIPT ERROR/ERROR 0。涵盖目录、二级筛选/收藏、套件卡片切换、真实场景索引/别名去重/白盒开关/房名激活路径，以及原有轮廓、批次、Prefab保存重开和灯光属性。扫描当前正式目录并加工具示例探针路径共124项，默认显示20项美术场景，8个组件套件；这些数字为测试时点扫描结果。
- 正式工程 Compatibility 编辑器 `render_final_pass.log`：exit 0，**39项通过、断言失败0**；包含真实鼠标回调的非格点单件落点、自由笔刷保留起点/间距与整笔撤销、网格相位、实际组件轮廓位置、3D预览旋转、真实缩略图、场景列表渲染与原有撤销/重做/保存边界。400件批次126ms，整批撤销与计数恢复正确。已目视检查原生视口图片 `asset_browser_final.png` 及对话框原生纹理 `asset_browser_final_scenes.png`。
- **上述编辑器专项不是工程启动零错误通过**：预期故障0；非预期4条SCRIPT ERROR和2条加载ERROR来自工具外既有探针：`_scratch/stair_rail_probe/probe_mid_map.gd:49` 的dy类型推断，`tests/verification/probe_block00_stairwell_block.gd:83/98/99` 的art_root/band_lo/band_hi类型推断。工具自身最终无SCRIPT ERROR；没有修改这些探针。另有旧房间UID重复与Compatibility景深告警。纯脚本编译隔离探针、模型专项与正式工程原生编辑器验收分别保留，不将隔离工程当成整工程通过。
- 未执行：整关游玩、实际发行PCK导出；没有接入或更改关卡运行模板池。当前功能状态继续保留partial，收口条件和工程外错误见本记录；不以旧测试覆盖当前事实。

- r3文档收尾：`check_feature_traceability.py` exit 0（43个功能、7个命令引用），`check_domain_boundaries.py`、`check_level_decoupling.py`、`check_asset_runtime_naming.py`均exit 0。`check_documentation_contracts.py` exit 1，仍为原有16项（15条断链及3个未登记验收场景的汇总项），归一行号与本轮基线比较新增0；`git diff --check` exit 0。新增工具脚本无尾空格，使用CRLF。套件卡片只切换目录，交互预览始终跟随实际选中的组件，避免预览与当前画笔不一致。

## 远征03白盒发现与参考加载修复（r4）

来源：用户反馈“我的远征03的房间，为什么读取不到白盒”。读取现有文件后确认，用户保存的`art_std_25x25_b.tscn`仍关联有效的`rt_std_25x25_static_layout.tscn`，本次未修改其场景内容。实际缺陷在编辑器入口：whiteboxes()只枚举rt前缀，漏掉9份cr通道和56份EGT共享参考；EGT根没有level_id，原索引把它归到共享房型，搜索远征03也不会命中；已有美术场景列表默认隐藏白盒。参考实际加载时也无状态反馈，失败路径静默返回，显示透明度只有12%。

先更新独立设计至r4，再修复：

- MODEL白盒查询改为复用场景索引的元数据投影，覆盖当前12份rt、9份cr、56份EGT，共77个来源。EGT保持共享归属，使用明确的远征03检索别名；不改资产归属、正式台账或运行时生成策略。
- 增加“浏览白盒库并新建…”白盒专用列表，默认显示白盒并搜索远征03，选择走另存为美术场景；从白盒列表到保存对话框先关闭原模态窗口，避免两个模态窗口冲突。原快速白盒下拉与文件选择保留。
- 新建EGT来源场景保留shell_id、egt_kind、门向与几何/端口，缺少template_id时使用shell_id。美术根记录来源与参考，不继承whitebox标记；EGT美术默认输出到远征03目录。不会覆盖任何已有白盒或美术文件。
- 顶部持续显示参考已加载、已隐藏、当前场景为白盒、未关联及资源失败等状态，提供重载与可撤销关联/更换入口。关联只修改参考元数据，保留已有组件摆位；撤销/重做通过元数据变化重建辅助，不绑定插件对象的撤销回调。预览禁用脚本、碰撞、导航、灯光、声音与粒子，无owner、不会存盘。
- 参考透明度默认30%且可调整，让成功加载的参考更容易看到。输出仍只是美术制作场景，不等于与flow运行时绑定；没有把EGT参考库误称为当前运行时固定房间名单。

本轮已有文件备份：`ShellStorm2-backup/2026-10-29_scene_builder_whitebox_discovery/before_edits/`。测试日志与截图：`ShellStorm2-work/probes/2026-10-29_scene_builder_whitebox_discovery/`。总设计、工具索引、模块索引、使用说明与开发入口同步维护。

### r4 验收与限制

- 正式工程 `model_final.log`：exit 0，**297项通过、失败0、SCRIPT ERROR/ERROR 0**。77个来源逐一创建成功（12房间+9通道+56共享参考）；尺寸/端口、白盒标记分离、壳ID、EGT美术存盘分类和白盒专用列表路径均验证。纯脚本编译检查通过。
- Compatibility真实编辑器 `editor_render.log`：输出 **52项断言通过、失败0**，其中参考加载/隐藏、透明度、关联与原生撤销重做、缺失路径可见反馈、白盒列表77项及选择后进入另存、EGT输出目录均已执行；400件批次231ms。已目视检查 `whitebox_editor.png`、`whitebox_editor_whiteboxes.png`。截图时77份来源均可检索，后续排序将本关来源优先于共享参考；最终模型专项在排序后重跑通过。
- **该GUI轮不能记为干净退出或整工程通过**：脚本输出52项通过后，外层进程在210秒超时被结束，编辑器期间仍在扫描动作/加载工具外探针。日志有6条非预期SCRIPT ERROR、3条加载ERROR，来自工具外既有探针 `capture_expedition03_clutter.gd:71/72`、`_scratch/stair_rail_probe/probe_mid_map.gd:49`、`probe_block00_stairwell_block.gd:83/98/99` 的类型推断；本工具未出现SCRIPT ERROR。预期拒绝1项为缺失参考路径，只有UI反馈，没有引擎错误。随后headless editor复核在180秒超时，停在重新打开场景阶段，专项未执行，不能算通过；没有改动工具外探针。
- `check_documentation_contracts.py` exit 1，仍为原有16项，归一行号对比新增0；`check_feature_traceability.py` exit 0（43功能、7命令引用）；`check_asset_runtime_naming.py` exit 0；`git diff --check` exit 0。编辑过的工具脚本使用CRLF、无尾空格。
- 未执行：整关游玩、发行PCK导出。关卡运行时模板绑定仍不在本轮范围；工具收口状态继续保留partial，不以断言通过掩盖进程超时或工具外错误。
