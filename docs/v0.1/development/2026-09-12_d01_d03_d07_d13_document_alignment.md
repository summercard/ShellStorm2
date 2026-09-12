# D01、D03–D07、D13内容文档对齐工程

日期：2026-09-12；记录ID：CONTENT-DOC-ALIGN-20260912；工程版本：0.1.0。
设计依据：用户要求将修改方向为“文档对齐工程”的未处理项目一并完成。本次只修改Markdown、内容数据库和差异台账，不修改运行时代码。

## 变更

- D01：`掉落物品!B18`由“弹药包”改为运行名称“通用弹药”；堆叠上限差异仍由D02单独跟踪。
- D03、D04：大型电池和电芯包改用正式ID `item_battery_l`、`item_cell_pack`，并按`ItemRegistry`同步名称、堆叠、使用动作、掉落权重和已实装状态。
- D05–D07：三档手电模块改用正式物品ID `item_flashlight_basic / advanced / efficient`，保留内部`module_id=basic / advanced / efficient`，同步运行类型、子类、解锁来源和已实装状态。
- D13：`基地商店!A2`改为正式99F购买进入当前I键背包；独立主基地使用待装载集合，不再写“购买进入保险柜”。
- `03_技术施工_玩家与操作.md`同步正式ID、名称、数值、来源与已验收状态。

## 对应文件

- `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`
- `docs/v0.1/03_技术施工_玩家与操作.md`
- `src/base/ItemRegistry.gd`（只读事实源）
- `src/game/ItemUseHandler.gd`（只读事实源）
- `src/player3d/PlayerFlashlight3D.gd`（只读事实源）
- `src/base/BaseManager.gd`（只读事实源）
- `tests/verification/verify_3d_flashlight_charge_flow.gd`（既有验收入口）

## 验证

- 内容数据库导出、公式错误扫描与变更区域渲染检查通过。
- 差异台账中D01、D03–D07、D13均改为“是否已处理=是、判定=已一致”。
- `python3 scripts/check_documentation_contracts.py`与`git diff --check`通过。

## 遗留

D02弹药堆叠上限仍需先冻结设计；D08–D11的价格和字段语义也未由本次修改带过。内容表中其他设计项与运行项继续按各自编号处理。
