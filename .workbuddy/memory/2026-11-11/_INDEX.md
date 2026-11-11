# 2026-11-11 事务索引

- [1606 远征01十三房心流曲线（设计层）](1606_expedition01_flow_curve_design.md)：`docs/v0.1/design/远征关卡01设计.md` 新增 §12 心流曲线，度量口径 `H=Σn·hp`、`P=D×min(max_alive,N)/N`、`ρ=N/A`。唯一越界是 05 房（P=716，04→05 5.42×）；`requires_clear=true` ⇒ 不封门≠可跳过；10→Boss 墙贴墙无走廊 ⇒ 静默只能靠时间提示。四条待裁定（A1 05 预警 bark / A2 解冻 preplaced / B 10 房提示改挂开门 / D 04 间歇）。**注意**：设计里的 `05 max_alive=16` 等参数是提案，未实现。
- [1613 提交并推送：宝箱聚光灯 + 遭遇准备期/HUD + 远征01 数据](1613_push_batch.md)：`bc5b890a`（62 文件），三条并行事务一并入库。补登 `verify_encounter_preparation_hud_integration` 并加进 `core_scenes`——**该门禁读的是 `run_verification_suite.sh` 的数组，不是 `feature_registry.json`，两处都要**。**账本门禁红 228**：R 列存成 `==LOWER(...)`、S 列数组公式（HEAD 存量）；`--baseline-only` 已坏死（主账本缺《资产主表》表），基线 1445/1447 刷不动。**遗留**：遭遇准备期功能无开发记录。
