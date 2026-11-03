# 场景退出存档红字修复

日期：2026-11-03。工程版本：0.1.0。FeatureID：SAVE-PROFILE / WORLD-INTERACTIVE-CLUTTER。
契约：[存档施工](../09_技术施工_存档结算与复活.md)、[基地经济与存档结算设计](../design/基地经济与存档结算设计.md)、[陈设状态设计 r8/r9](../design/场景可交互低模物件设计.md)。本次修复既有保存边界，不更改玩法、数值、存档schema或layout_id。

## 症状与根因

用户运行日志读取时共9,565条 `!is_inside_tree()` / Transform3D错误，1条 `data.tree is null` 和1条 `get_nodes_in_group` 空值脚本错误，调用栈均进入父级 `Dungeon3D._exit_tree` → 注销提供者时补存 → 房间/陈设采集。这是同一处退出时序失配引出的刷屏。父级退出回调执行时子房间已离树，新加的陈设采集无条件查询SceneTree分组，陈设姿态序列化又读取全局变换。

独立复现启用真实Dungeon3D持久化，先保存再移动陈设0.375m，立即移除场景。修复前场景退出1、日志门禁3，并且最终陈设姿态未落盘。原日志仅只读分析；未关闭或重启用户运行中的编辑器/游戏。

## 变更

- `Dungeon3D` 增加无子树的退出边界Node，在其他持久化子树退出前完成最后一次采集与提交并注销提供者；父级退出不再重新采集。运行中新增根节点时摘挂边界Node以保持最新插入顺序，临时摘挂不会触发保存。已结算、已放弃或提供者已被替换时保持既有不回写语义。
- `DungeonRoom3D` 离树时不查询分组，跳过无效/待销毁陈设，detail卸载前补采最新姿态。`Dungeon3D` 不以已离树房间的空组覆盖最近快照。
- `verify_reactive_manor_props` 增加真实场景移除、激活后新增子树、未发状态事件的位置变化、仅提交一次、离树补采不清账、磁盘重载断言。测试在Autoload前隔离APPDATA/LOCALAPPDATA，独立保存路径，不使用正式存档。

Godot的退出实现反向迭代子节点插入表，`move_child`只改变显示索引；因此退出边界采用实际摘挂，而不是仅移动索引。依据：[引擎Node实现](https://github.com/godotengine/godot/blob/master/scene/main/node.cpp)，并以本机4.7.2实际移除场景验证。

## 验证

所有过程产物位于 `ShellStorm2-work/sessions/2026-11-03_checkpoint_teardown/`。采用独立APPDATA启动Godot后手跑 `check_verification_log.py`；未运行整份聚合套件，专项结果不代表全工程通过。

| 项目 | 场景退出码 / 日志门禁 | 结果 |
|---|---|---|
| 修复前退出保存复现 | 1 / 3 | 复现空树访问及最终姿态漏存，`before.log` |
| 退出保存专项 | 0 / 0 | 最终7项断言，含最终姿态、一次提交、离树不清账、磁盘重载；`final_checkpoint.log` |
| `verify_reactive_manor_props` | 0 / 0 | 819项，含新增7项退出断言，`final_reactive.log` |
| `verify_runtime_autosave_flow` | 0 / 0 | 防抖、关键提交、重启与保险恢复，`autosave.log` |
| `verify_pause_game_save_reset_flow` | 0 / 0 | 暂停复位与存档清理，`final_pause.log` |
| 远征03真实场景存档往返，同种子20261103 | 0 / 0 | 门、宝箱、易碎件回灌和场景退出无错误，`final_roundtrip_fixed.log` |
| 修复前远征03同种子对照 | 0 / 3 | 同一组状态断言通过，但退出仍触发空树错误，`baseline_roundtrip_fixed.log` |
| 台灯联动headless回归 | 0 / 3 | 419项断言通过；1条材质空值引擎错误。修复前隔离对照亦0/3、相同错误，`lamp.log` / `baseline_lamp.log` |
| 台灯Compatibility真实渲染回归 | 0 / 3 | 419项通过，仍有4条同类材质空值引擎错误，`lamp_native.log`；不能签为无错误通过 |
| 撤离物品交接补充回归 | 124 / 0 | 180秒超时；没有完成标志或引擎错误，停在返塔布局加载阶段。该项未完成，不算通过；`final_settlement.log` |

首轮未固定种子的远征探针有A1/A2气闸门态断言失败（退出1、日志门禁0）；修复前随机种子对照未复现同一断言，不能据此归因为既有或回归。之后用外置SceneTree入口在场景装入前将LevelSelect种子固定为20261103，再对照同一组资源和改动前/后两份Dungeon脚本，两边全部状态断言通过，仅修复前的退出日志门禁失败。不修改正式探针的门态期望或阈值；随机入口的非确定性仍单列。

无预期故障白名单新增。当前修复链路、819项陈设专项、自动存档、暂停复位与同种子远征存档回归均无非预期脚本/引擎错误；台灯材质空值为本次改动前后均存在的独立问题，未在本次扩展修复。撤离交接补充回归及全量聚合套件未完成。

| 静态检查 | 退出码 | 结果 |
|---|---|---|
| `check_level_decoupling.py` | 0 | 7个通用容器，0违规 |
| `check_asset_runtime_naming.py --quiet` | 0 | 无新增运行资产命名债务 |
| `git diff --check`（本轮路径） | 0 | 无空白错误；3份GDScript无BOM/CRCRLF，原有特殊道具HUD改动保留 |
| `check_documentation_contracts.py` | 1 | 17项既有问题：15条断链、1组4个验收入口未登记、媒体检查缺openpyxl。用本轮改动前文档替身逐项比较，新增0项，`documentation_baseline.json` |
| `check_workspace_hygiene.py` | 1 | 工程内既有outputs、_scratch、Godot三个目录；本轮产物全部写工程外，不处理其他会话目录 |

静态原始输出见同目录`documentation.log`、`level_decoupling.log`、`asset_naming.log`、`workspace_hygiene.log`与`static_checks.json`。修复前场景对照使用工程外小型源副本及资源junction，不曾将运行中的工作区代码反复撤回。临时对照目录的递归清理被自动审批策略拦截，源码副本和测试产物保留。

## 边界与回滚

本次不宣称远征03整关或全局套件通过。正式编辑器现有红字计数不会自动清除，需下一次重新运行游戏加载修复后的脚本，再观察新增错误。

改动前副本位于 `ShellStorm2-backup/2026-11-03_checkpoint_teardown/before_edits/`。`Dungeon3D.gd` 中原有特殊道具HUD改动保留；其他会话的代码、资产和账本不覆盖。回滚须逐补丁核对，不能整份恢复覆盖并发修改。

## 后续灯态回归修复

上轮新增的detail卸载采集会在房间初始DATA_ONLY时提前写入空陈设账，激活旧回灌分支并将基地/安全屋按缺省false关灯；原验收未覆盖默认灯态，819项通过不能证明照明无回归。后续按“只有明确灯态字段才控制灯光”修复，保留主线与手动关灯，见[默认灯态回归修复](2026-11-03_default_lights_regression.md)。
