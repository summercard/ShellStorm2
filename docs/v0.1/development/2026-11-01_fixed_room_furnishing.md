# 远征03：正式房间固定陈设与结构兼容

日期：2026-11-01；记录ID：WORLD-PLAN-20261101-FIXED-FURNISHING；功能ID：`WORLD-PLAN`、`TOOL-SCENE-EDITOR`；工程版本：0.1.0。
设计依据：[远征03设计 §7.5.2](../design/远征关卡03设计.md)、[组件场景编辑器设计 r8](../design/组件场景编辑器设计.md)、[场景生产流程 r5](../10.1_3D场景美术生产流程.md)；代码基线：`7120c0ca7`加本会话未提交的r7工具修正；交付提交：工作区；代码、布局、编辑器保存负测与四房画面专项已完成，额外可玩回归失败/超时与原始加载对照按下表分列。

## 来源、范围与所有权

用户在[唯一正式房间列表](2026-11-01_scene_workshop_unique_rooms.md)完成后继续明确：门墙与连接由关卡种子/装配决定，陈设固定在编辑器维护的同一正式TSCN；工坊展示和编辑的必须是游戏实际引用的文件，并核查房间文件格式是否统一。此要求授权本轮修正陈设运行写入权；不把上轮“只改工具”的范围扩大成当时已修改游戏。

已先冻结设计：正式TSCN独占作者陈设（含历史 `Furn_*`）的节点、父子层级、局部Transform、启用、碰撞引用/覆写与作者灯光。运行时禁止按名字、来源标记或主题配方删除、重建、改摆/隐藏陈设；空陈设保持空，无生成兜底。关卡继续拥有房间整体摆位、门位/门墙、连接和既有玩法状态。

本轮实现停止运行时覆盖作者陈设、共享全部合法门位的净空查询与工具制作校验，并对现有冲突家具及附属物做可追溯定点调整。没有整屋重烘焙或删件放行，没有改变稳定文件路径、组件几何、玩法规则或远征01/02/99包装。

| 修改点 | 最终行为与边界 |
|---|---|
| `DungeonRoom3D` | 移除唯一的家具重建调用及不再使用的函数/常量；原TSCN陈设原样实例化，墙地重建与门FSM不改 |
| `RoomArtLayoutContract` | 只读查询，复用 `RoomDoorLane.lane_offsets()` 与 `ManorFurnishing._door_boxes()`；实际碰撞盒8顶点经全部父链Transform投影后取凸包并作SAT检测，支持编辑中的XYZ旋转，不复制门位/净空公式 |
| 工坊门口保护与保存 | 对全部合法门位保护；保存/另存前检查实际陈设碰撞，冲突时显示实例和门位并拒绝该工具保存命令；**不宣称引擎级强制门禁**，原生编辑器外部Ctrl+S等未接入守卫的保存可绕过 |
| 公馆烘焙器 | 限于新房初始化；已存在的正式文件不覆盖；新房若全合法门前净空不合格则拒绝生成，不作运行时兜底 |

净空校验是只读制作约束，游戏加载不依赖工具；不会因关掉插件重新获得改摆陈设的写入权。

## 已完成的只读结构审计

审计输入是工坊 `scene_index.game_rooms()` 返回的58个实际正式资源路径，不是目录全扫。

| 关卡 | 正式文件 | format | 根类型 | ArtComponents | Lighting分组 | ConnectionPorts | Prefab实例引用 | 直接GLB引用 | 缺引用 |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|
| 远征01 | 13 | 3 | Node3D | 0 | 0 | 12 | 1304 | 0 | 0 |
| 远征02 | 26 | 3 | Node3D | 0 | 0 | 0 | 1099 | 0 | 0 |
| 远征03 | 18 | 3 | Node3D | 18 | 0 | 0 | 1437 | 0 | 0 |
| 已登记的99测试关卡 | 1 | 3 | Node3D | 0 | 0 | 0 | 1 | 0 | 0 |

58份均为Godot文本PackedScene `format=3`、Node3D根、根无脚本，以组件Prefab引用组成，0缺引用、0直接GLB引用；**序列化格式已统一，分组和metadata语义仍有兼容差异**。远征03十八份只有 `ArtComponents`，无 `Lighting/ConnectionPorts/WhiteboxShell` 分组；这不代表没有灯光或运行时门，而是这些分组未保存于房间文件。01/02/99的旧平铺结构与字段保持兼容，不为凑齐组名重存/复制，避免破坏NodePath及玩法引用。

远征03根 `room_id` 记录的是烘焙样本，唯一资源身份仍按现行共享契约，不在本轮因字段整理改键。房间附加的真实碰撞树优先于组件元数据；不能因Prefab标记 `visual_only/collision_shape_count=0` 就否认房间保存的碰撞。

结构证据：`ShellStorm2-work/probes/2026-11-01_scene_workshop_structure/structure_audit.md`、同目录 `audit.json`、`engine.log`。无Autoload最小项目的Godot文本/Node数学探针退出0，非预期脚本/引擎错误0；未据此签署真实物理、画面或全关可达性。

## 全合法门位净空基线与资源改动

只读审计读取18份资源中的241件 `Furn_*` 实例、150份显式BoxShape3D家具碰撞；合法门槽由共享 `RoomDoorLane.lane_offsets()` 提供，四面合计308个候选槽。按父链Transform和实际OBB/SAT检测，标准净空基线为131个家具×门槽冲突对、118件家具、126个门槽，18份房型均有冲突。没有侧边0.35m余量时仍有111对，表示侵入门内通道，不等同每对都完全堵死角色。

固定陈设需要在制作阶段避开全部合法门位，而非只避开烘焙样本。本轮对18份正式资源仅修改149行 `Furn_*` Transform的原点分量：118件冲突碰撞家具及31件桌面/依附陈设联动搬移，最大位移5.49m。总物件241件、150份显式碰撞全部保留，92件家具原位置保留；名字、旋转、缩放、Prefab引用、碰撞尺寸及其余文本不变。没有删除物件或整屋重烘焙。

调整后全合法门前净空冲突为0，未引入新的家具碰撞交集。18份正式文件的SHA与迁移候选完全一致，原稿/候选核对无额外变化，未被编辑器主进程改写；新增脚本补齐稳定UID sidecar。这里“无新增交集”不等于删除所有既有构图交叠。逐文件前后SHA-256、每节点原/新位置及冲突数量登记于 `ShellStorm2-work/sessions/2026-11-01_fixed_room_furnishing/migration_plan.json`，与原始备份可逐行核对。

场景XLSX账本没有这些 `runtime_rooms` 布局的独立条目；本轮没有改共享组件、组件ID、模型或组件哈希，因此不回写组件行掩盖布局变化。正式房间布局的SHA变化与定点差异独立登记在上述迁移清单，不把组件台账未改误称布局文件哈希未变。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 退出码 / 预期故障 / 非预期脚本错误 | 证据与限制 |
|---|---|---|---|
| 58份正式文件结构与碰撞文本审计 | 无Autoload独立最小项目；Godot 4.7.2；不接触正式存档 | 退出0；预期故障0；非预期脚本/引擎错误0 | 上述structure证据；只读，无GLB加载/整关实例化 |
| `test_fixed_furnishing.gd`：24种子陈设/门口专项 | 工程外隔离项目，Autoload前独立用户目录；headless运行结构/物理查询 | 退出0；7136检查、失败0、非预期脚本/引擎错误0；58文件核查，实际采用18份美术，3888个门位样本（每门3条射线+1次胶囊查询） | `fixed_full24.log`、`fixed_full24_result.json` |
| 最终 `test_fixed_furnishing.gd --quick`（8顶点凸包修订后） | 隔离项目与用户目录；headless | 退出0；824检查、失败0、非预期脚本/引擎错误0；58文件、18资源池静态/旋转碰撞负测、2种子使用14资源、342个门位射线/胶囊样本 | `fixed_quick.log`、`fixed_quick_result.json`；查询修订不改运行代码，未重复24种子物理专项 |
| 固定陈设保持及边界覆盖（同一专项） | 同上 | 正式文件→运行时非结构节点/Transform/Prefab/碰撞相等；DATA_ONLY→ACTIVE、空陈设无兜底、手改Furn旋转缩放、自定义Marker、作者灯光、两装配分支及重新实例化通过 | 不把生成器metadata作为唯一判据；读档单列 |
| 全合法门位净空与家具互撞 | 只读查询+定点资源迁移复核 | 全部门前冲突0；新家具交集0；物件241及碰撞150保持 | `migration_plan.json`，保留旧交集口径 |
| `test_layout_model.gd` | 隔离项目与用户目录；headless | 退出0；417检查、失败0、非预期脚本/引擎错误0 | `layout.log`、`layout_result.json` |
| `probe_expedition03_save_roundtrip` | 隔离用户数据；headless | 退出0；STATE_PROBE OK；非预期脚本/引擎错误0 | `save.log`、`save_result.json`；宝箱/杂物快照回归，不宣称完整存档通关 |
| 原生Metal编辑器 `--scene-builder-runtime-probe`（打开/保存/净空负测/重开） | 隔离编辑器与用户目录；真实渲染 | 退出0；74项检查、失败0；非预期脚本/引擎错误0。真实添加CollisionBody侵入合法门口后点击保存，被拒且正式磁盘原文不变；有效Marker保存/重开保持 | `editor_native.log`、`editor_native_result.json`、`editor_native_scenes.png`；不宣称外部原生保存已强制受控 |
| 四房渲染与人工画面核对 | OpenGL真实渲染器；评审照明 | 退出0；非预期脚本/引擎错误0。已亲眼查看25×25战斗房、45×40大堂、25×25整备房、50×40Boss房，家具完整、门前净空保留 | `visual.log`、`visual_result.json`及`render/`四图；评审照明不等于实战光照验收 |
| 额外 `probe_expedition03_playable`（随机种子加载） | 隔离用户数据；headless | 退出1；6项可玩断言失败，另有2条material null引擎错误和1条数组越界脚本错误 | `playable.log`、`playable_result.json`；本次加载未成功生成房间，不记整关通过；不在本轮修关卡生成器 |
| 固定种子可玩真实渲染回归 | 隔离项目；原生渲染；240秒上限 | 退出124（超时）；8条material null引擎错误。已到达rooms28/doors28、blocked0、reachable28/28及门样式、弃局交互、封门刷怪alive_after7、清房恢复、靠近开/走远关；最终像素段未完成 | `playable_native.log`、`playable_native_result.json`；仅上述观测成立，整套不记通过 |
| 原始未修改 `DungeonRoom3D` 的加载链对照基线 | 隔离项目与用户目录；headless loading-only | 退出0，但同样出现2条Parameter material null引擎错误；不记无错误通过 | `baseline_loading.log`及结果JSON；证明至少headless加载空材质是既有问题，不外推native全部8错误/超时已归因 |
| `check_documentation_contracts.py` | 当前Python；静态检查 | 退出1；45项问题（43既有断链、验收注册缺3项合并1项、缺openpyxl合并1项）；新文档无断链报告 | `documentation_final.log`；最终仍45项，新记录无断链；未签署全仓文档通过 |
| `check_level_decoupling.py` | 静态检查 | 退出0；7容器、违例0 | `level_decoupling.log` |
| `check_workspace_hygiene.py` | 静态检查 | 退出1；工程已有 `_scratch`（含拉取备份/10月旧日志），本机缺 `export_presets.cfg` | `workspace_hygiene.log`；本轮隔离项目已移除，过程证据保留工程外 |
| `check_asset_runtime_naming.py` | 静态检查 | 退出1；bunny v022/v023/v024三条既有命名路径旧债 | `runtime_naming.log`；本轮未新增版本运行路径 |

除另行注明，证据目录为 `ShellStorm2-work/sessions/2026-11-01_fixed_room_furnishing/`。验证以本轮实际日志为准，未执行项、预期失败注入与非预期错误分别登记；不会把一次退出0与错误日志并存的运行记为通过。查询投影最后补齐8个顶点并取凸包以覆盖编辑中XYZ旋转，属于只读制作检查，快速重验824项已通过；不改变运行代码，未因此重复24种子物理专项，全量证据保留上述full24日志。专项探针的初稿类型/预加载修正日志保留为 `fixed_initial_parse_error.log`、`fixed_initial_preload_errors.log` 等；最终7136项结果来自修正后的完整重跑，不把初稿失败算通过。

## 状态、回滚与未完成项

- r8陈设保持、全合法门前净空、编辑器拒绝保存负测、四房画面与XYZ旋转快速复验已完成。额外可玩回归存在随机布局加载失败、材质错误和原生超时；原始加载对照仅定位了headless空材质旧问题，未归因全部原生错误。功能状态保持 `partial`，不提升工程版本或整关完成状态。
- 已执行24种子结构/门口物理查询、流送重建、有限存档快照回归、编辑器保存负测和4房评审画面；未执行全种子穷举、完整关卡通关/存档续玩、目标设备、操作系统物理鼠标键盘派发及实战光照外观验收。native可玩最终像素段未完成；不得用这些专项替代整套通过。
- 模板ID透传等本轮无关问题不因固定陈设修改隐式迁移；本轮没有调整生成器或放宽可玩/像素阈值。插件外部原生保存绕过净空守卫仍是明确限制。
- 本轮改前备份在 `ShellStorm2-backup/2026-11-01_fixed_room_furnishing/before_edits/`，包含上轮尚未提交的r7工具内容；回滚逐文件核对本轮差异，不能以旧HEAD覆盖r7成果。

本轮隔离引擎均已退出，临时项目与用户目录入口已清理；日志、迁移候选/逐节点清单及截图保留在工程外证据目录。
