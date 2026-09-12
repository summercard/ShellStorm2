# E05／E06 行动结算单次事务开发记录

日期：2026-09-12。工程版本：0.1.0。范围：E05成功撤离结算、E06死亡结算。
设计依据：[存档、结算与复活](../09_技术施工_存档结算与复活.md) §5、§7。

## 开发结果

- `BaseManager.commit_run_settlement(request)`成为行动长期结算的统一提交入口。一次内存变更和一次原子写盘共同提交行动统计、击杀、成功撤离魂、待领取战利品或死亡保险中转、幂等事务ID与行动检查点清理。
- `TowerDescent3D`成功返航继续保留当前背包、装备与保险格实例，不复制到`extraction_loot`；只有事务提交成功才发送`run_completed`并返航99F。
- `Dungeon3D`成功或死亡均调用同一事务入口。死亡规则计算后若保存失败，普通背包、快捷栏和保险格恢复到结算前快照，行动档保持可恢复；成功后才清空运行时保险格、停止运行态保存并切换场景。
- 场景在失败重试期间保留同一个事务ID；BaseData的有界`completed_transaction_ids`使重复请求及重载后重放直接返回既有成功，不再次增加统计、魂、战利品或保险物。

## 对应文件

- `src/base/BaseManager.gd`
- `src/world3d/Dungeon3D.gd`
- `src/world3d/TowerDescent3D.gd`
- `tests/verification/verify_run_settlement_transaction.gd`
- `tests/verification/verify_run_settlement_transaction.tscn`
- `scripts/run_verification_suite.sh`
- `tests/README.md`
- `docs/v0.1/09_技术施工_存档结算与复活.md`
- `docs/v0.1/audits/evidence/discrepancy_inventory_20260912.json`
- `docs/v0.1/development/2026-09-12_discrepancy_table.md`

## 验证

- `godot --headless --path . --editor --quit`：脚本解析通过。
- `godot --headless --path . tests/verification/verify_run_settlement_transaction.tscn`：通过。覆盖成功撤离强制写盘失败整体回滚、故障解除后重试、同ID重复请求；覆盖死亡保险中转失败回滚、重试提交及重新加载后的幂等重放。

## 未包含范围

E04工坊组合事务仍未处理。精英与剧情多域统一结算属于E10等后续边界，不在E05／E06本次已冻结的数据字段内。
