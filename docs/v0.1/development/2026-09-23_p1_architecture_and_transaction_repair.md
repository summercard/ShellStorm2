# 2026-09-23 P1 架构与事务收口

## 范围与结论

本批在用户明确允许跳过剩余 P0 后，执行《2026-09-22 全项目深度审计》的 P1。本记录不将性能、基地节点预算、塔楼光照/99F支撑面、资产登记表哈希与隐藏旧塔楼综合流程等剩余 P0 标记为完成。

| P1包 | 结果 | 独立验收/证据 |
|---|---|---|
| 模块索引事实 | `MODULE_INDEX` r4 回写 Narrative、Tooling、Reward、Workshop、Settlement 和 Tower 事务现状 | 文档契约门禁 |
| 奖励正式切流 | 搜索、击杀、清房、钥匙、保底备弹、剧情物品均经 `RuntimeRewardCoordinator → RewardService`；删除 `LootModule` 两个旧抽表入口 | `verify_reward_service_flow`、`verify_requested_experience_upgrade_flow`、`verify_finite_ammo_flow`、`verify_narrative_timeline` |
| 工坊原子事务 | 成本迁入 `BlueprintUpgradeService`；`upgrade_blueprint` 一次提交余额、Tier、幂等ID，写盘失败整体回滚 | `verify_workshop_transaction_flow` |
| 结算事务 | 证实现行 `commit_run_settlement` 已为一次原子、可重试、跨重载幂等提交，修正过期索引事实 | `verify_run_settlement_transaction` |
| 塔楼门/卸载/快照 | 到达门与 Boss 隔离门在快照成功后才开；旧段卸载先保存“已卸载”意图，再删节点；恢复消费该索引重放卸载 | `verify_arrival_gate_floor_bundle_flow`已加写盘失败反向断言；但该综合用例存在 P0 旧流程联锁失败，本批不声称整场通过 |
| 主编排器瘦身 | 从 Dungeon 提取奖励调度边界，从 BaseManager/UI 提取蓝图纯规则；为档案只读投影、换装提交和精英档案建立公开命令/查询；Tower 仍保留场景删除编排 | 生产代码不再直接读取/写入`BaseManager.data`或`VfxPool3D._REGISTRY`；完整 Tower Lifecycle Service 仍是后续债务 |
| 跨域写权限 | 精英预约/成长经BaseManager档案事务写入，换装经原子命令提交，基地/靶场只读档案快照，战斗端经VFX公开工厂查询 | 精英、换装、靶场、VFX共6个原有专项全部通过；`check_domain_boundaries.py`并入文档门禁，阻止生产代码恢复已知私有访问 |
| 验证注册治理 | 全部 `verify_*.tscn` 唯一归属 `smoke/core/visual/manual/retired`；新增去重/漏登检查并并入文档门禁 | `VERIFICATION_REGISTRY_OK scenes=154 categories={smoke:6, core:121, visual:26, manual:1, retired:0}` |
| 第一批仓库精简 | 删除 7 份 `_scratch/user_snapshot_*` 用户数据/渲染缓存快照和 14 个根目录一次性日志/临时场景 | 共 790 个 Git 跟踪文件，约 691 MiB；已落在提交 `c425b717`，可从 Git 恢复 |

## 重要契约决策

1. `RewardService` 是规格到奖励实体的唯一解析器。`RuntimeRewardCoordinator` 只有调度、确定性事件ID和过渡桥接权，不写场景/背包/钱包。
2. 怪物规格允许主池与备弹独立命中；运行地面表现仍保持最多一个非货币实体，冲突时备弹优先，以保证精英/Boss的8–16发契约。`count`为真实数量，不再被旧验收错判为“必须为1”。
3. 塔楼的不可逆操作以存档回执为门禁：写盘失败时可保留已生成节点作为重试缓存，但不开门、不删旧段。
4. 本轮不通过放宽性能阈值、批量接受资产哈希或删除用户未实现设计来制造全绿。

## 验收结果

| 入口 | 结果 | 说明 |
|---|---:|---|
| `verify_reward_service_flow` | PASS | 池门禁、可复现、覆盖链、分布、拒绝路径、运行时调度 |
| `verify_requested_experience_upgrade_flow` | PASS | 单地面实体、真实数量、搜索计时和颜色 |
| `verify_finite_ammo_flow` | PASS | 精英统一掉落仍保证备弹 |
| `verify_workshop_transaction_flow` | PASS | 五类失败/幂等/重载 |
| `verify_run_settlement_transaction` | PASS | 成功/死亡结算原子性 |
| `verify_narrative_timeline` | PASS | 新增合法`grant.item`不降级的正向断言；107项检查通过 |
| `verify_tower_runtime_restart_restore` | PASS | 98F世界、房间进度、位置、背包、快捷栏、装备、保险与手电状态均可跨重启恢复 |
| `verify_three_segment_tower_generation_flow` | SKIP（符合当前设计） | 当前最深层为98F，三区段前提不成立；实测计划层索引与生成拒绝结果已记录 |
| `verify_unique_elite_roster_flow` / `verify_first_elite_growth_flow` | PASS | 公开精英档案命令保持预约、成长、迁移、故障回滚与3D绑定 |
| `verify_player3d_head_accessory_flow` / `verify_training_range_3d_flow` | PASS | 换装重启持久化与靶场BaseData隔离保持通过 |
| `verify_vfx_pool_lifecycle` / `verify_combat_vfx_toon_v002` | PASS | 公开VFX查询/后备工厂保持池回收与卡通战斗表现通过 |
| `verify_3d_parity_core` | FAIL（已知P0） | 奖励部分无新错；仍红“相邻房未流送”与节点预算2559/2200 |
| `verify_arrival_gate_floor_bundle_flow` | FAIL（已知P0/隐藏旧流程） | 从98F到达门实体状态开始联锁失败；事务代码通过preflight，但不将综合场景签绿 |
| `verify_base_world_flow` | FAIL（已知P0） | 新公开档案查询已正常编译运行；仍红首片596节点预算与手枪跑步握姿 |
| `verify_base_overhaul_flow` | FAIL（已知P0/旧综合流程） | 本轮换装常量编译回归已修复；仍红旧`float`调用、基地灯光/设施/99F标签及主页面表现断言 |

## 剩余债务

- 奖励发放层仍使用 legacy item 字典；需将 `RewardSink.apply()` 接成场景的唯一发放口。
- 7 个 deprecated 掉落死池仍需业主数据裁决；真渲染地面奖励截图门禁未补。
- Tower/Dungeon/BaseManager 仍是大型编排器；本轮完成奖励、蓝图规则、档案查询/提交、精英档案和VFX注册表边界，并修复塔楼提交语义，但未做高风险整类重写。
- 剩余 P0 见 [2026-09-22 P0记录](2026-09-22_p0_validation_baseline_repair.md)，尤其是性能/节点预算、资产登记表和隐藏旧塔楼套件。
