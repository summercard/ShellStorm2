# 数据库房 v014 导出拼装收尾

- 数据库房 `db_room` 已由 v002 返工源整理为 v014 组件库：35 个唯一组件、86 个布局实例。
- 已完成 35 个独立 GLB、35 个稳定 PackedScene、运行时注册表接入，并将 `db_70x50` 注册到 `FloorPlanGenerator`。
- `room_02`、`room_06`、`room_10` 均通过组件重放验收：86 实例、42 块通用 C01/C02 主层地砖、44 个普通房型组件、unresolved=0、2 扇通用门，最终 `ROOM_TYPE_COMPONENT_REPLAY_OK checks=2838`。
- 共享色盘 post-import 已重导并通过材质验收；数据库房门扇由通用房间壳体保留可见。
- 已生成三个房间的 `room_runtime_manifest.json` 与验收证据。
- 已同步场景分账本 `ENV-EXPEDITION-L01-ROOM-DB-70X50` 为 v014、正式美术已接入，并更新 SHA、源路径、运行时说明及无损基线。
- 已同步远征关卡设计文档，明确 `room_06` 当前暂用 db_01 默认布局，db_02 缺角变体仍待另行制作。
- 门禁通过：`ASSET_REGISTRY_CHECK_OK`、`LEDGER_SPLIT_VERIFY_OK`、`EXPEDITION_ASSET_STATUS_OK`、文档契约检查通过。
- 已提交 Git：`3e4e4a05`，提交信息为“数据库房v014导出拼装并同步账本文档”；提交包含 173 个文件变更，提交后工作区无剩余状态输出。
