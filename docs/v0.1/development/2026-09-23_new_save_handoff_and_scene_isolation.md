# 新档 98F/99F 交接与剧情刷枪跨重启修复

日期：2026-09-23；工程版本：`0.1.0`；功能ID：`ENTRY-AVATAR`、`NARRATIVE-TRIGGER`、`WORLD-LOOT`、`SAVE-RUN`；工具链：验收 Runner。基线：`622d6c4a`。

## 症状与根因

| 症状 | 根因 | 排除的错误方向 |
|---|---|---|
| 剧情专项后接开场专项时后者红，单跑 105 项绿 | Runner 只按**套件**隔离 `user://`；前一场景写入 `narrative_history`，后一场景被 `once=run` 档案阻断 | 非开场剧本时序自身失败；未改剧情完成判据或吞掉失败日志 |
| 真新档未捡 98F 地面枪，在 99F 下线后重登丢枪 | 房间 `ground_items[]` 已被保存，但 `scope=base` 快照只用于选择出生点，从不恢复世界/携带物 | 没有另建 `world_drops[]` 平行账本；没有把枪自动装回玩家 |
| 剧本中断再播有复制风险 | `narrative_history` 只在完整收口后写；中断重播会再次执行 `scene.spawn_item` | 不把“演过剧情”冒充“物品是否已创建/拾取”的唯一事实 |

## 实施边界

Runner 每场景改写临时项目的自定义用户目录；该场景预检和正片使用同一目录，导入缓存共用，清理仅针对本套件生成的目录。

新档地面枪继续由剧本 `scene.spawn_item` 决定物品 ID、时点和落位；新增显式 `spawn_key=nar_tower_opening_01_wake:starter_weapon`，`NarrativeAdapter3D` 只转发，`Dungeon3D` 独占刷物键及房间地面实例。普通基地快照需要合法世界 schema 和匹配的 `runtime_map_id` 才恢复世界/携带物，角色固定落 99F，不用旧坐标。带 `successful_extraction_carry` 的远征返航中转仍只按显式标记恢复携带物；无标记空世界中转不能伪装成普通基地快照。拾取动画尚未销毁节点时，房间快照也排除已接受拾取实例。

没有提高工程版本、放宽预期错误、删掉旧测试或改动正式资产。`retry/never` 新语义、其他地面掉落全覆盖及视觉表现不在本次范围。

## 验收证据

| 命令/场景 | 结果 | 口径 |
|---|---|---|
| `bash scripts/run_verification_suite.sh scene verify_new_save_handoff` | 退出码0，`NEW_SAVE_HANDOFF_OK` | 真实塔楼新档98F、未拾枪→99F下线→磁盘重载→同实例重现→拾取→再次重载；重复刷物键不复制、地图隔离 |
| `bash scripts/run_verification_suite.sh batch verify_narrative_timeline verify_opening_script_runtime verify_new_save_handoff` | 退出码0，3/3，开场105项通过 | 反证原先的场景间长期档顺序污染；前一场景保留真实落盘行为 |
| 主线8场景批次初跑 | 退出码1，7/8 | `verify_expedition_extraction_carry_return` 抓到“无标记的空世界中转被误认基地快照”；保留失败事实，未标为通过 |
| `bash scripts/run_verification_suite.sh batch verify_expedition_extraction_carry_return verify_new_save_handoff` | 退出码0，2/2 | 加世界 schema 门槛后，远征显式交接与普通基地世界恢复同时成立 |
| 9场景完整主线批次（剧情、开场、新档、入口、98F、自动存档、塔楼重启、远征交接、结算） | 退出码0，9/9 | 最终代码下的同批顺序和主线交接无新增失败 |
| `bash scripts/run_verification_suite.sh aggregate core` | 退出码1，130场景/15失败 | 相比此前129场景/15失败，新增的新档场景通过；`FAILED_SCENE` 15项与[上次全项目复评](../audits/2026-09-23_full_project_reassessment.md) §6.3 逐项相同，没有扩大红项集合 |
| 主线8场景批次中的其余场景 | 当次单项均通过 | `verify_verification_runner_contract`、`verify_game_entry_flow`、`verify_block00_floor98_assembly`（230项）、`verify_runtime_autosave_flow`、`verify_tower_runtime_restart_restore`、`verify_expedition_level01_flow`、`verify_run_settlement_transaction` |
| 文档/追溯/资产命名/账本结构/脚本语法/`git diff --check` | 均退出码0 | 122份文档、590个本地链接、37功能无问题；资产410项/9账本/0结构问题；命名无新增违规，存量债务仍为文件289/目录13/备份1 |

新档场景在全量后补了一项正式剧情 JSON 的 `spawn_key/item_id/point_room` 等值断言，单跑再验退出码0。预检中仍出现存量 `vfx_base99_dust_particles_root_top3d.tscn` 无效 UID 的警告，Godot 按文本路径回退；本次没有据此宣称视觉验收。真实渲染、设备性能和长测未执行，不以专项或 headless core 代替发布验收。

## 跟进

主设计见[剧情](../08_技术施工_剧情触发.md)与[存档交接](../09_技术施工_存档结算与复活.md)，逐项状态见[关系表](../FEATURE_RELATIONSHIP_MATRIX.md)。一般地面掉落、存档写盘失败时的世界与携带物故障矩阵、开场独立展示相机，以及 `retry/never` 提案继续保留待办；本次只关闭开场枪及场景间测试污染两项具体缺口。
