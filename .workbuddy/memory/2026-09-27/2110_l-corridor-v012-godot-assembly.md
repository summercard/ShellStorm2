# L 型走廊 v012 Godot 导入与组装

- 将 `common_components/v012` 的 27 个组件逐件导出稳定 GLB，并生成 27 个 PackedScene；运行时房型组件清单总数升至 160，shell component catalog 总数 172。
- 修复 `regroup_room_type_components.py` 对旧包嵌套集合及 Blender `.001/.002` 后缀的兼容：保留集合先挂回场景，再清理旧父集合；27/27 组件包非空。
- `corridor_45x40` 接入 `FloorPlanGenerator`，仅 `room_01` / `room_08` 重放 v012 的 `l_turn` 默认布局；`room_04` 的 `u_turn` 不接默认布局，等待差异实例布局。
- 走廊主层 42 块地砖运行时替换为通用 C01/C02；通用壳体承接门扇。
- 验收：`ROOM_TYPE_COMPONENT_REPLAY_OK checks=4385`；160/160 PackedScene 可加载实例化、615 个色盘材质表面；room_01 / room_08 各 121 实例、42 地砖、49 普通组件、30 结构墙、unresolved=0、2 门。
- 已生成 `f00_room_01` / `f00_room_08` 的 runtime manifest；同步场景分账本 `ENV-EXPEDITION-L01-L-CORRIDOR` 为 v012 / 正式美术已接入、镜像表、无损基线及远征01设计文档。
- 门禁通过：ASSET_REGISTRY_CHECK_OK、LEDGER_SPLIT_VERIFY_OK、EXPEDITION_ASSET_STATUS_OK、documentation contracts issues=[]。
