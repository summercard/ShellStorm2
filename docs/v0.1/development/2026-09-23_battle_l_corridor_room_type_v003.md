# 战斗区 L 型走廊房间种类美术源 v003

- 功能定位：`ASSET-PIPELINE`；按用户修订把 [v002](2026-09-23_battle_l_corridor_room_type_v002.md) 从 10m 改为 15m 宽。仍为 `battle / scene_art` Blender 房间种类源，不修改关卡生成、门状态机或 Godot 运行场景。
- 平面：5m 网格，两段均为横向三砖宽；长臂 `45×15m`，向南的支臂再延伸 `15×25m`，总包络 `45×40m`。地砖从 28 块增加到 42 块，每块独立成包、每排三块。
- 通用组件：42 块地砖的可见表层引用 Battle 通用组件库 v003 的两种 5m 地砖网格，保留 5×5×0.3m 承重砖和附着细节；完整高度的边界实墙使用同库 `ENV-BATTLE-COMMON-WALL-STANDARD-5M` 的原生 5×0.3×11.9m 网格，不拉伸。共享墙体仅在本房间美术源里重新映射深蓝色盘，保持原走廊的色彩关系。
- 门位：西端中间 5m 槽、南端中间 5m 槽，以及原参考图后墙两处 5m 槽均空出。走廊源不制作门墙或门，manifest 显式指向 `ENV-BATTLE-COMMON-WALL-DOOR-5M` 和 `ENV-BATTLE-COMMON-DOOR-5M`，后续实例布局按连接方向放入。标准门净空采用 2.2×2.5m，最终连接关系仍待白模/关卡计划核定。
- 设施：长臂服务器窗、终端、推车、花槽、机柜、线缆等整体沿新北墙移动 5m；支臂西侧界面移至 `x=30m`，转角支臂的推车、终端、机柜、花槽分别贴近东西墙，中间一砖保持通行净空。7m 高管线随北墙延伸，并补足东墙新增一跨。
- 交付：`assets/art/environments/tower_zones/battle/source/room_types/l_corridor/v003/` 保存独立 `.blend`、增量构建脚本、121 个独立包 manifest/catalog、房间 manifest、参考图、全景/俯视/近景及 QA 报告。v001/v002 保留。
- 专项验收：Blender 4.2 后台打开与真实 Cycles 渲染退出 0；121 包、42 地砖、1609 输出网格、48387/48387 面有效 PaletteUV、四种共享材质、四处门位无实墙占据，42 个地砖导引与布局一致。设备中心距相邻边界不超过 2.8m，脚本错误 0。
- 未执行：无白模可核对最终门连接；未装入通用门墙/门，也未导出此房间实例 GLB、生成碰撞/PackedScene 或接入 Godot。门与运行时资产状态不能据此标记验收。
- 工程门禁：`python3 scripts/check_documentation_contracts.py` 退出 0（116 份文档、545 个本地链接、0 问题）；`python3 scripts/check_asset_runtime_naming.py` 退出 0（没有新增违规运行资产路径，旧债快照仍为文件 289/目录 13/备份 1）。无故障注入，Godot 运行验收未执行（尚无运行时接入）。
