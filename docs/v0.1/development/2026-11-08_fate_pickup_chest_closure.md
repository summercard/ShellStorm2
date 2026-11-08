# 命运卡专用掉落物与宝箱奖励链收口

日期：2026-11-08；记录ID：2026-11-08_fate_pickup_chest_closure；
功能ID：`FATE-RULES / WORLD-LOOT / REWARD-SERVICE / WORLD-PLAN / PLAYER-INTERACT`；
工程版本：0.1.0；交付状态：专项已通过，整体功能保持 `partial`。

## 1. 当前裁定

命运卡正式获取入口收口为两类：

1. 占卜屋局间预选；
2. `item_fate_card_drop` 命运卡专用世界掉落物的主动交互。

宝箱、普通门、普通容器、普通击杀奖励和角色二级奖励不得直接授予命运卡或直接打开购买界面。宝箱只负责按档位解析奖励、播放开箱表现并把奖励散落到地面；玩家必须主动交互专用掉落物，才进入统一三选一购买事务。

## 2. 本轮完成内容

### 2.1 专用掉落物

- `ItemRegistry` 已登记 `item_fate_card_drop`，但它是非背包世界交互凭据，不是普通可入包物品。
- `FateCardDropPickup3D` 复用地面物的落地/回收基础能力，覆盖为必须主动交互；靠近不会自动拾取，落地动画未完成时拒绝交互。
- 统一交互请求携带唯一 `fate_pickup_id`、来源房间和来源宝箱/生产者信息。
- 失败（距离、模态占用、错误房间、空ID、候选生成失败等）保留原凭据；offer 成功建立后才认领并销毁世界凭据。
- 表现为悬浮、慢速旋转的紫金卡片，并叠加科技扫描流光；生产视觉根使用 `1.45` 倍专用放大，不改碰撞球、交互距离或普通掉落基线。落地稳定后开启无阴影紫色局部光，并发射 12 个、寿命约 `0.95s` 的上升发光方块粒子；成功认领时同步关闭粒子和局部光。表现不拥有候选、报价、扣费或应用效果。

### 2.2 宝箱独立系统

- `ChestRewardService` 负责纯奖励解析和确定性随机流，不消费刷怪主随机数。
- `TreasureChest3D` 负责交互、开箱状态和表现；`Dungeon3D` 负责接入、pending 奖励账、落地、恢复和统一购卡事务。
- 普通宝箱：30% 生成 1 枚命运卡专用凭据，另掉 2—3 件消耗品。
- 高级宝箱：100% 生成 1 枚命运卡专用凭据，另掉 5—8 件非枪物品和 1 把非近战枪。
- 普通箱的 pending 奖励在爆点散落后清账；爆点前切房时恢复一次；拟态箱冻结同一份奖励，击杀后只散落，不直接发卡或弹购买界面。
- 宝箱不进入普通背包，不持有命运卡候选、报价、支付或应用状态。

### 2.3 角色击杀链

正式普通敌人由 `_spawn_enemy_batch()` 生成后，通过 `Enemy3D.take_damage()` → `killed` → `Dungeon3D._on_enemy_killed()` → `MapFateTriggers` → `Player3D.on_fate_kill_recorded()` → `spawn_character_fate_pickups()` 产生专用凭据。

本轮使用正式敌人生成入口作为验证夹具，未手工发射 `kill_recorded` 或伪造最终投递结果；这证明了正式生产信号链，不等同于未经验证干预的完整自然游玩长流程。

## 3. 验证证据

专项结果文件：`F:/wxgame/ShellStorm2-work/verification/fate_pickup_latest/result.json`。

```text
FATE_PICKUP_PROBE_RESULT exit_code=0 failures=0 injected_faults=8 unexecuted=["无"]；本轮在 Forward+ / Windows / RTX 3060 真实窗口下重跑，stderr 为空
```

`verify_fate_pickup_runtime`（外层 runner）退出码 0，证据归属如下：

- **命运卡主动交互专项**：角色命运凭据正常落地、双规则 request ID、`currency_cost` 与投递账；角色投递失败保留、重试、重复请求幂等；JSON 快照往返语义一致；开箱不直接弹购卡、靠近不自动拾取、主动交互进入统一报价；重复交互、距离/房间/模态/候选失败拒绝并保留凭据；支付失败/取消保留规则。
- **宝箱运行链专项**：普通宝箱爆点前切房 pending 补发一次；拟态快照释放后恢复、击杀结算和清账边界。
- **独立解析专项**：普通/高级宝箱奖励解析、确定性和主随机流隔离由 `verify_chest_reward_service` 单独验证，不把纯解析结果冒充角色拾取或完整远征证据。

独立解析结果：

```text
CHEST_REWARD_SERVICE_OK: normal/advanced tiers, filters, fate metadata, deterministic streams and RNG isolation pass
VERIFICATION_SUITE_OK suite=scene count=1
```


专项日志仍包含既有 imported UID warning 与 headless dummy material null 等环境/资源提示；它们没有被本轮当作已根治，也不作为完整工程全绿证据。

## 4. 远征01当前回归边界

`verify_expedition_level01_flow` 本轮实际进入 Godot 后退出 1，共报告 **14 条当前失败**，不能继续写成 11 条，也没有做 A/B 基线，故不把它们全部归因于旧问题：

- 入口与名称契约：缺少两个立体入口；读取界面标题仍为「CloseAI数据库」；怪物掉落表实际 11 行而用例期望 13 行；区块 `display_name` 仍为「CloseAI数据库」。
- 碰撞轮廓：`room_06` east 3 个采样点、`room_07` north/east/west 共 4 个采样点、`room_10` south 1 个采样点无墙碰撞。
- 组件元数据：`north_server_00` 与 `north_broken_core` 的碰撞形状 metadata 写 1、实际为 2。

这些失败与本轮命运卡专用凭据、双档宝箱解析和 pending 恢复专项分开统计；整体远征状态保持 `partial`。

## 5. 账本同步

已通过编辑器保存并回读，随后做了目标单元格的磁盘只读回读：

- `assets/registry/ledgers/ShellStorm2_物品道具账本_v001.xlsx`
  - 实际工作表名为 `非背包与待设计`，新增并回读 `item_fate_card_drop`；
  - 宝箱备注保留专项通过、完整工程仍分列的边界；
  - 修正 `item_fate_card_drop` 调用链记录：`src/world3d/FateCardDropPickup3D.gd` → `src/player3d/PlayerInteractionController3D.gd` → `src/world3d/Dungeon3D.gd#_show_door_fate_choices(pickup, pickup_id)` → `src/rewards/ChestRewardService.gd` / `ItemRegistry.item_fate_card_drop`；它是世界交互凭据，不是普通背包道具。
- `assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx`
  - 资产主表普通/高级宝箱行的合法状态统一为 `正式美术已接入`，优先级补为 `P1`；
  - 已回读资产主表使用范围 `A1:Y49`，两只宝箱行备注保留玩法专项通过与完整工程仍为 partial 的边界；
  - 本轮没有重新逐项验证 `总览` 八个公式与 R/S 派生公式是否按第49行正确落盘；当前门禁仍由 44 行 R/S 派生公式格式问题阻断，不能把“范围已扩展”写成公式门禁已通过。

专用掉落物不登记为普通背包道具，也不把其世界凭据误写入普通可拾取物主表。

## 6. 未完成与不应误报的部分

- `FATE-RULES` 六关完整投放仍不是本轮完成项：01 已接入，02—06 投放、逆位分级、教学保底和新增卡执行器仍按主设计保持待实现/部分实现。
- 完整远征01/03回归、完整真实存档文件往返和真实关卡全部奖励构图仍需单独门禁证据。宝箱奖励的生产落点与轨迹已施工：箱体外 1.75—3.80m 确定性随机环带、真实支撑/净空/箱体外排除、同批与已有掉落最小间距、合法点不足时 pending 保留；视觉从爆点沿约 1.35s、峰值约 2.5m 弧线飞出并慢速翻滚。普通掉落基线未改。命运卡生产视觉已完成 1.45 倍放大、无阴影紫色局部光和 12 个/0.95 秒上升发光方块粒子；真实 Forward+ 已完成专用命运卡展示和宝箱弧线夹具取证，但固定落点、独立摄像机和有限奖励数量不等同于真实关卡全量构图验收。
- 旧角色 pending 迁移协议及 `currency_cost` 与统一报价的最终收费归属仍需单独裁定，不能擅自引入双重收费。
- 当前仓库的全工程门禁仍有独立红项：历史文档断链、验证注册与资产注册/命名债务、远征房间资产覆盖差异等；本轮文档契约复核实际仍有 42 项断链问题，未宣称全仓通过。运行设计投影复核 `files=52 issues=[]`，关卡解耦复核 `violations=0`；本轮 `check_media_asset_domains.py` 已实际执行并通过（213 assets，issues=[]），不能继续记为 `openpyxl` 缺失或未执行。UID/material/physics warning 仍作为资源/运行环境遗留项，不归因于本专项。
- 本轮回读确认：道具账本两只宝箱行的状态枚举为 `正式美术已接入`、优先级为 `P1`、资产主表已用范围为 `A1:Y49`；物品账本 `item_fate_card_drop` 的调用链已恢复为专用掉落物入口。`check_asset_registry.py --scope structure --ledger props` 仍报告全表 44 行 R/S 派生公式格式问题（88 项）。原因已复现为 editor_sdk 保存接口的公式序列化限制：输入合法 `=...` 后落盘为带前导等号的 OOXML `<f>`，S 列同时被写成单格数组公式。未放宽检查器，也未用绕过编辑通道的脚本改写工作簿；该门禁阻断需在编辑器接口或专项迁移工具层修复后再收口。
- 本轮已重跑 Godot 命运卡/宝箱专项：`F:/wxgame/ShellStorm2-work/qa/fate_pickup_visual_20261108/result.json` 记录 `FATE_PICKUP_PROBE_RESULT exit_code=0 failures=0 injected_faults=8 unexecuted=["无"]`；`verify_3d_combat_progression_flow` 输出 `3D_COMBAT_PROGRESSION_FLOW_OK`，两者均为 Forward+ / Windows / RTX 3060 真实窗口运行且 stderr 为空。独立弧线构图夹具输出 `EGT_CHEST_REWARD_ARC_RENDER_OK`，图片位于 `F:/wxgame/ShellStorm2-work/qa/chest_reward_arc_render_20261108_v2/`；该夹具使用真实掉落类和动画，但固定落点，不调用生产随机落点生成，不代表真实关卡全量构图已验收。历史 `F:/wxgame/ShellStorm2-work/verification/fate_pickup_latest/result.json` 仍保留为早期专项证据，不作为本轮新结果。

本记录只声明专项链路已通过，不声明整套工程、六关投放或远征关卡全部完成。
