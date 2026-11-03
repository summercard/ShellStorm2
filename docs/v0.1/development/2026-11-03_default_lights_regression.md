# 默认灯态回归修复

日期：2026-11-03。工程版本：0.1.0。FeatureID：SAVE-PROFILE / WORLD-INTERACTIVE-CLUTTER，关联NARRATIVE-TRIGGER的回归验证。
依据：[存档施工](../09_技术施工_存档结算与复活.md)、[主线剧情剧本2.5/03](../design/主线剧情剧本.md)、[上轮退出红字修复](2026-11-03_checkpoint_teardown.md)。用户明确基地和安全屋默认开灯，且不能改主线任务逻辑。

## 回归与根因

上轮新增`_unload_runtime_detail`采集会在房间`_ready → DATA_ONLY`时执行。虽然尚无陈设实例，也会把`reactive_props={}`写进原本为空的房间账。随后detail生成时，`_apply_pending_detail_runtime_state`不再早退，并把没有`room_light_on`的账按`authored_room_light_on=false`回灌，覆盖FACILITY/STAIR_LOBBY/BOSS实际构建出的默认亮灯。上轮819项专项没有默认灯态断言，未能发现这条回归。

同时核对到旧档缺灯态字段在`Dungeon3D._restore_room_runtime_state`中会被主动补为false，同样与“缺席不覆盖”的合并契约冲突。

## 修复范围

- 无实例、无历史的陈设采集不创建空账；已有陈设历史继续保存。
- detail回灌只在明确存在`room_light_on`时写灯态。陈设、容器局部恢复保留Prefab/房型默认或当前开关状态。
- Dungeon回灌旧档时不为缺失灯态字段补false。明确保存的false/true继续生效。
- 不修改主线JSON、触发条件、NarrativeDirector/Adapter、`apply_narrative_light_state`、开关行为或房型默认。对房间的主线灯光接口、开关、内容构建及事件绑定函数与本轮前副本逐函数字节比对一致。
- 正式存档未改写。已有档中的明确关灯记录继续按原语义恢复，不能仅凭false推断它来自本次回归，并重置玩家手动或剧情关灯。

## 验证

过程与隔离用户目录：`ShellStorm2-work/sessions/2026-11-03_default_lights_regression/`。Godot4.7.2；启动Autoload前隔离APPDATA/LOCALAPPDATA，退出码与`check_verification_log.py`门禁分别记录。没有新增错误白名单。

| 验证 | 场景退出码 / 日志门禁 | 结果 |
|---|---|---|
| 修复前55项灯态专项 | 1 / 3 | 11项失败，复现基地/安全屋/Boss默认灯灭、旧档缺灯态被关灯；`before.log` |
| 修复后55项灯态专项 | 0 / 0 | 五类房间：默认态、空陈设账、旧档缺字段、当前手动态、明确保存开关、流送重建、主线关灯与房间快照恢复；`after.log` |
| 完整`verify_reactive_manor_props` | 0 / 0 | 874项，包含原家具/盆栽/退出存档与新增55项灯态，`full_reactive.log` |
| 基地常驻顶灯与双侧开关 | 0 / 0 | 默认亮灯、手动开关、DATA_ONLY常驻、重建连续、并联互锁及启动序列通过；`facility_persistent.log` |
| 真实主线2.5→03完整关灯链 | 0 / 0 | 10项：默认亮、门外转暗且不锁输入、03起播仍暗、全程无回亮、03收口后仍暗等玩家开灯；`narrative_blackout_complete.log` |
| 主线首轮并发加载尝试 | 124 / 0 | 180秒超时，已走到03起播，无引擎ERROR；后改为单独跑并放宽外部进程时限，97.11秒完整通过，不修改剧情时长或断言 |

所有最终专项日志无非预期脚本/引擎ERROR。真实主线场景沿用原JSON、触发条件、时序与验收期望，未修改主线逻辑。完整874项中包含退出保存断言，上轮防空树修复保留有效。本轮未执行全量聚合套件或原生渲染截图，不提升整关/视觉验收状态。

| 静态验证 | 退出码 | 结果 |
|---|---|---|
| `check_level_decoupling.py` | 0 | 7个通用容器、0违规 |
| `git diff --check` | 0 | 本轮路径无空白错误；GDScript无BOM/CRCRLF |
| 主线范围核对 | 0 | `src/narrative`与`data/narrative`无工作区diff；主线灯光命令、开关及内容构建函数与本轮前副本字节一致，`scope_proof.json` |
| `check_documentation_contracts.py` | 1 | 16项既有问题（15条断链及一组5个验收入口未登记）；与本轮前文档替身比较新增0项，`documentation_baseline.json` |

机器结果汇总见同过程目录`result.json`，仅本轮代码/测试补丁见`fix.diff`。

## 回滚

改前副本：`ShellStorm2-backup/2026-11-03_default_lights_regression/before_edits/`。仅逐补丁回滚，不覆盖其他会话的商人UI、特殊道具HUD、敌人资产及账本修改。默认灯态修复保留上轮退出保存防空树处理。
