# 2026-10-08 命运卡跨进程存档闭环

- FeatureID：`FATE-RULES`、`SAVE-RUN`
- 工程版本：`0.1.0`
- 来源/状态：用户要求；本轮存档恢复闭环已实现并通过专项，FATE 总体仍为 partial。
- Owner：`RunPersistenceService` 负责行动快照；`Player3D`、`Dungeon3D`、`FateCardGameBridge` 分别拥有角色、世界、持卡运行状态。

## 实施范围

`Dungeon3D.build_runtime_save_snapshot()` 在既有 `runtime_player_state_v2` 中增加 `fate_run_state.version=1`，下含 `player`、`world`、`bridge` 三段。既有保存时机、BaseManager 唯一写盘者、地图/布局恢复顺序未改变。

新增接口：

- `Player3D.is_fate_snapshot_number(value, minimum, maximum, integer=false) -> bool`：JSON 边界数值校验。
- `Player3D.read_fate_snapshot_fields(value, defaults, signed_fields=[]) -> Dictionary`：按默认模板读取并拒绝非法类型/范围。
- `Player3D.clear_fate_weapon_cache_for_restore() -> void`：恢复真实装备实例前清理旧运行树缓存。
- `Player3D.export_fate_snapshot() -> Dictionary`：导出角色命运、used flags、计时、愚者计数和已持有装备实例对应的运行枪树热/成长/王后待用状态。
- `Player3D.import_fate_snapshot(value) -> bool`：只按现有装备实例 ID 恢复，不应用卡牌即时效果；非法状态安全拒绝。
- `Dungeon3D.export_world_fate_snapshot() -> Dictionary` / `import_world_fate_snapshot(value) -> bool`：恢复未来世界规则、临时钥匙、房间幂等/计数、地图探索和环境触发器计数；不重 roll 方位，不重复登记。
- `FateCardGameBridge.export_fate_snapshot() -> Dictionary` / `import_fate_snapshot(value) -> bool`：保存稳定卡 ID、方位、效果参数快照、已应用记录和愚者待领取固定奖励；导入从正式预设重建，不调用 apply/roll/扣魂。

成功结算返航在 `TowerDescent3D` 删除 `fate_run_state`，新局仍由既有 `reset_run_state()`、`reset_world_fate_state()` 清空临时命运。

## 验证

环境隔离：`APPDATA`、`LOCALAPPDATA` 均指向 `outputs/fate_completion_20261008/persistence/` 下独立目录，Godot 4.6.3 console，未触碰真实档。

- `res://tests/verification/verify_fate_resume_completion.tscn`：JSON 序列化→新实例恢复→重复恢复幂等，76 checks，退出 0，`roundtrip_third.log`。
- 两进程真实写盘/读档：writer 26 checks、resume 34 checks，均退出 0；日志为 `process_writer.log`、`process_resumer.log`。
- 覆盖 HP/魂不重复、未来世界规则、角色 modifier/祝福计时、used flags/触发计数、愚者待领取、运行枪树热/成长/王后奖励、真实 `weapon_instance_id` 归属、旧快照无版本键安全默认、非法状态拒绝、reset 清理。

## 遗留与门禁

本轮未修改 UI、Engine、Enemy、武器逻辑；Bridge 仅新增导出/导入接口。全局文档/资产门禁仍受既有断链、资产版本化债务和环境缺少 `openpyxl` 影响，不能据本轮专项提升 FATE 或 SAVE 总体状态。
