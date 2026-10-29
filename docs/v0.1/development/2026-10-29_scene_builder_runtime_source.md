# 2026-10-29 场景工坊r6：真实关卡房间来源与回接

FeatureID：TOOL-SCENE-EDITOR；模块：TOOLING；工程版本：0.1.0；契约：r6。
设计：[组件场景编辑器](../design/组件场景编辑器设计.md)；历史：[r5工作台](2026-10-29_scene_builder_workbench.md)。

用户指出游戏中为矮墙，工具打开为高墙，并明确应编辑游戏内运行的房间。实测现有rt/cr与EGT静态文件均为11.9m；真实ExpeditionLevel03_3D运行的DungeonRoom3D程序壳墙段为2.8m。此前目录索引仅以文件存在归类，不能证明运行采用；r5加载与UI专项通过不能覆盖此来源缺口。

本轮先冻结r6契约，再补实际生成场景采集、编辑与回接。备份：ShellStorm2-backup/2026-10-29_scene_builder_runtime_source/before_edits；证据：ShellStorm2-work/probes/2026-10-29_scene_builder_runtime_source。所有采集进程启动前隔离APPDATA/LOCALAPPDATA，正式白盒及既有作者场景不覆盖。

验收结果与未执行项在本记录收口。


## 实现与所有权

- r6 / 插件1.2.0。主打开窗口默认“关卡房间”，按正式关卡场景和种子读取，房间名用中文职责加真实ID，列表显示实测墙高。原目录放到“美术场景/参考模板”，rt/cr与EGT明确标为11.9m旧静态参考；没有缩放或覆盖旧文件。
- `runtime_capture.py`通过`workspace_paths.work_path()`定位独立job，启动Godot前隔离APPDATA/LOCALAPPDATA；`capture_runtime.gd`真实实例化正式场景并使用其生成链，在test_mode下提取DungeonRoom3D。每房保留实际墙地Prefab、变换、碰撞和局部门位；剔除脚本、触发器、运行门FSM、动态物件和敌人，提供WhiteboxShell/ArtComponents/Lighting/ConnectionPorts。
- 读取器有阶段、耗时、120秒超时、失败日志和重试；取消支持进程尚未就绪的情况，仅停止自身job。实时运行会话镜像没有实现，复现地图必须输入相同种子，界面和说明明确区分。
- 派生参考缓存位于`.godot/editor/scene_builder_runtime`，不是第二套关卡源。正式美术位于既有关卡目录`runtime_rooms/<实际房间ID>_<几何签名>.tscn`；首次建立后由Godot作者维护，之后优先打开已有场景，不重建覆盖。原有art_std文件、正式白盒和资产账本未改。
- 唯一身份契约`src/world3d/RuntimeRoomArtSource.gd`由工具和游戏共用：房间实际尺寸、类型、size_class、安全房角件、局部门位/开口参与签名，排除种子、世界位移、对端房ID。DungeonRoom3D沿既有static_layout_scene_path入口优先选择匹配签名的美术；未匹配继续旧路径/程序白盒。实际局部帧不套用旧美术旋转猜测；不改生成器拓扑、刷怪、门状态机或存档。
- 回接不会附加塔楼12m相机门墙代理；只恢复原矮墙的camera_lower_wall声明。结构碰撞和墙体几何保真由实际加载后再次测量，不能只核对缓存文件。
- 工作台顶栏保存/另存与Ctrl+S仍走Godot原生保存和撤销，但禁用保存时的场景缩略图生成。对标准空场景、关闭本插件的最小Godot编辑器也复现4.7.2的`list.h:228 p_I->data != this`错误；同路径`save_scene_as(path,false)`反向对照无错误。没有隐藏/忽略引擎错误。脚本编辑与其他独占窗口保留原生快捷键。辅助节点同步释放的稳定路径保留；试验性的延迟释放造成崩溃，已撤回。

代码基线为当前工作区`38d256a0`上的未提交修改；并行任务代码未覆盖。本轮DungeonRoom3D增量相对before_edits备份另存为证据diff，不能把该文件其他任务的整份Git差异归到本轮。

## 最终验收

所有进程启动前隔离用户目录；日志均在上述工程外证据目录，job原始输出位于`ShellStorm2-work/probes/scene_builder_runtime/jobs/`。真实画面使用Compatibility/NVIDIA渲染，headless仅用于数据与几何。

| 检查 | 退出码 | 结果 | 非预期脚本/引擎错误 |
|---|---:|---|---|
| 正式场景采集 `r6_named_rooms_final` | 0 | 种子77003244，28间实际房间；实测墙顶约2.79999995m，包括入口房 | 0/0 |
| 真实运行数据与回接 `runtime_binding_verified.log` | 0 | 283项；28房身份、几何包络、端口、脚本/门FSM隔离；入口/准备房/战斗房实际加载、作者改动存在、低墙几何/结构碰撞保真、门位不符拒绝 | 0/0 |
| 原工程模型 `model_final.log` | 0 | 297项；77份旧参考仍可显式使用，索引126场景/22美术 | 0/0 |
| 原工程布局 `workbench_final.log` | 0 | 15项；340×700无溢出，图像区在900px面板占610px，模式按钮及异步取消/过期结果 | 0/0 |
| 原生编辑器与真实渲染 `native_r6_shortcut.log` | 0 | 77项；实际列表、打开正式房、保存、Ctrl+S真实输入派发、重开保留改动、原生撤销/刷放/参考与旧UI重建 | 0/0 |
| 原生首次建立 `native_r6_first_create.log` | 0 | 76项；独立夹具内首次建立hub_01，保存及重开保留；未在正式工程生成测试房 | 0/0 |
| 功能追溯 / 域边界 / 关卡解耦 / 资产命名 | 0 | 43功能、9命令链接；零新增违规，存量命名欠账未处理 | 不适用 |
| 文档契约 | 1 | 16个既有问题，与r5归一化对照新增0 | 不适用 |

原生编辑器专项使用约20MB隔离夹具与真实采集缓存，只复制依赖、避免测试保存污染正式作者场景；运行回接专项则使用原工程正式关卡和实际DungeonRoom3D代码，测试产物在外部目录。未把夹具的通过扩大成全游戏通过。截图`workbench_r6_scenes.png`已目视核对“关卡房间”、远征03/种子、28房、中文房名与2.80m标识；卡片/工作台截图`workbench_r6.png`亦为真实GPU输出。旧资产别名仍有4条重复UID警告。

预期拒绝：缺失关卡job退出1，Godot退出2并留下两条预期缺文件错误，状态包含原因/日志；启动前取消job退出1且无引擎错误；几何不匹配不加载旧美术。正常采集/回接/GUI最终无非预期错误。

## 修复过程与限制

首版测试脚本顶层preload完整游戏场景导致Autoload尚未就绪时编译失败，改为初始化后load；两轮失败日志保留，不能算通过。首次GUI测试修正变量类型标注与测试搜索假设；运行来源服务的ready信号及打开前同步已补齐。读取缓存有28项不代表UI已同步，实际树内容与活动场景路径均有断言。

保存/切场景期间的引擎错误经关闭本插件的最小场景反向对照定位为原生缩略图保存路径；`native_minimal.log`、`native_blank_save.log`为复现，`native_no_preview_save.log`为无缩略图对照。中间若干GUI迭代虽断言通过但含引擎错误或非零崩溃退出，不签署通过；最终77项与首次建立76项退出0且无错误。延迟释放的试验已撤回，未放宽验收阈值。

新增回接碰撞断言曾发现每房多2–3个layer16相机代理，这是旧静态装配给矮墙房补了塔楼代理；按来源能力隔离该补偿后，入口/准备房结构shape均11个、战斗房12个，与原壳完全一致。失败记录`runtime_binding_delivery.log`与`collision_details.log`保留，最终`runtime_binding_verified.log`283项通过。

当前仅对种子77003244完整验证，并覆盖门位变更拒绝；所有随机种子、远征01/02、新关卡、完整刷怪战斗/读档和正式美术审美未做全量验收，功能整体保持partial。复用范围限定相同房间ID和局部几何，不宣称一种美术能自动适配所有门位，也不宣称读取的是当前玩家会话。`source_sha256.json`仅是本次快照，不是活引用；源再次保存后需重验。

总设计、主设计r6、TOOL_INDEX、MODULE_INDEX、机器注册表、使用说明、开发README及CHANGELOG均已同步本记录。文档16项历史缺口明细见`documentation.json`与`documentation_delta.json`，不夹带修复其他模块。


### 退出阶段复核补记

最终重复时旧夹具曾在77项断言结束后以3221225477退出，不能算整轮成功（`native_r6_delivery.log`）。新增缩略图stop、等待未结束绘制任务及GPU同步，插件子服务由Node统一销毁；专项runner持有测试对象，避免延迟收尾回调丢失。旧夹具的退出崩溃曾复现，未清理用户编辑器缓存，也不宣称所有Godot退出缺陷已经消除。使用同一组代码与实际采集缓存建立约20MB干净夹具，`native_r6_clean_cache.log`77项、退出0、脚本/引擎错误0，覆盖完整打开/保存/快捷键/回接流程与正常退出。后续复跑结果另存`native_r6_clean_cache_repeat.log`。这类夹具退出差异独立保留，功能状态仍为partial。


### 退出阶段的最终修正

`native_r6_clean_cache_repeat.log`在第二轮仍出现77项之后的3221225477，排除了仅靠清理夹具缓存即可解决的假设。最终采集不再对运行实例使用Node.duplicate保留内部SceneState，而是重新实例化**同一路径**的共享Prefab，再逐项转移实际运行Transform、可视属性、材质、碰撞与metadata，并保留运行追加的结构节点；美术组件仍是稳定引用，没有展开、重制或新增资产。预览stop/GPU同步及测试对象生命周期收口一并保留。

该最终实现使用重新采集的28间真实房间，在新的小型夹具中连续执行两轮：`native_r6_fresh_instances.log`、`native_r6_fresh_instances_repeat.log`均77项、退出0、脚本错误0、引擎错误0，包含实际Ctrl+S、保存/重开和正常退出；旧错误日志保留。此对照支持退出不稳定与运行实例状态复制有关，是基于实测的推断，不声称已定位Godot引擎内部唯一根因。最终结构与回接复核为`runtime_binding_fresh_instances.log`，不能把早期失败记录当成当前通过。
