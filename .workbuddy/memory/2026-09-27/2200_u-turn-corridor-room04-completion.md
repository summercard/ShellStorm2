# 22:00 凹型走廊 room_04/u_turn 完成

- 完成 `room_04 / corridor_45x40 / u_turn` 具体房间差异布局，真源为 `assets/art/environments/tower_zones/expedition/source/room_instances/f00_room_04/v001/room_layout.json`。
- 仅复用 `common_components/v012` 的既有 27 个组件；123 个实例：60 floor_tile、46 solid_wall、17 room_type_component；房间专用组件 0。
- 运行时接入具体房间布局优先选择，保持蓝图 `u_turn`，门槽 footprint 前置校验避免静默回退为 `l_turn`。
- 生成 `runtime/room_instances/f00_room_04/room_runtime_manifest.json` 与 acceptance 证据，记录 `ROOM_TYPE_COMPONENT_REPLAY_OK checks=4539`、160/160 PackedScene 可加载与实例化、unresolved=0。
- 账本备注列第 25 列摘要已同步到 `ledger_split_baseline.json`；校验仍报告 486 条既有公式形状问题，missing/extra 均为 0，非本次布局引入。
