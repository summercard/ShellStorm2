# 2026-11-03 远征贩卖机与交互页面

功能ID：`RUN-MERCHANT`、`UI-HUD`。工程版本：`0.1.0`。设计依据：[局内商人r4](../04.1_玩法系统_局内商人.md)、[基地经济与存档结算](../design/基地经济与存档结算设计.md)。

用户反馈：远征03贩卖机与99F界面不一致，交互页无法使用。

## 原因与处理

- 远征调用旧`MerchantUI`，其普通Control不绘制panel样式，内部VBox没有铺满，商品自然宽度只有约59px，并显示`[icon]`。99F已使用`BaseVendingMenu`双侧货架/背包界面，两条路径没有同步。
- 原截图局内余额39，六件商品价格均高于余额；旧页没有明确购买按钮与页内拒绝原因。原生基线中直接点击商品、关闭和改造台能响应，因此未认定为“全部输入系统失效”。
- 将`MerchantUI`收敛为适配器，直接实例化同一个`BaseVendingMenu`，复用商品3D图标、布局、按钮和背包棋盘。局内只提供行动背包与购买；基地保留无限货架、背包/仓库与出售。
- 局内仍用`GameManager.currency`和`RunMerchantService`原有报价/武器实例/持久化货架，页面不另写交易规则；失败中文原因和成功结果显示在页内。购买后保留焦点入口，关闭会话并解除玩家输入锁。
- 修改既有`UI-SCREEN-MERCHANT`、`UI-SCREEN-BASE-VENDING`两行，更新版本/稳定路径/哈希和对应基线指纹；不新增资产或修改其他域行。

## 验证

所有Godot进程在Autoload前设置隔离APPDATA；日志和截图位于工程外`ShellStorm2-work/sessions/2026-11-03_expedition_interaction/`。

| 验收 | 退出码 | 结果 |
|---|---|---|
| `verify_expedition_interaction_ui`，原生Vulkan窗口 | 0 | 正式远征03、余额不足禁用与原因、真实鼠标购买/关闭、焦点确认购买、输入锁、720p/1080p、改造台页签/取消、背包与大地图关闭通过；截图亲眼检查 |
| `verify_run_merchant_transaction` | 0 | 持久货架、会话、实例、余额、容量、回滚、重试和重复请求通过 |
| `verify_run_merchant_integration` | 0 | 首开/成交写盘失败回滚、重开、读档、无效/旧档通过；坏货架warning为预期故障注入 |
| `verify_base_shop_save_flow` | 0 | 基地十件货架、买卖幂等/回滚/重启恢复、实际背包和3D图标通过；1条`stale_writer_attempt`为预期拒写 |
| `verify_gamepad_input_flow` | 0 | 输入设置、绑定、焦点入口、导航及确认专项通过；未接实体手柄 |
| 改前/改后页面容量对照探针 | 0 | 同一个12格背包和两件物品，原脚本与现脚本均为`背包 2/12 格`；共用页面未改变基地容量计算 |
| `verify_tower_facility_inventory_binding` | 1 | 旧专项的`BaseStorageSlot`计数和`2 / 12`硬编码两项失败；同一InventoryModule绑定检查未失败。当前仓储为GridInventoryBoard，`verify_base_shop_save_flow`按当前24格/两件物品投影检查通过；未为全绿放宽旧断言 |
| `verify_unified_player_interaction_flow` | 超时 | 150秒仍在加载塔3大型场景，未取得完成标记，不能算通过 |
| 媒体域、UI账本结构、账本拆分无损、关卡解耦、运行资源命名 | 0 | 本次两个UI登记与对应指纹一致；未增加运行版本路径 |
| UI账本完整检查 | 1 | HUD/Vault/Pause/FateSource四项既有哈希漂移，相关行与改前备份逐格不变；本次两行无漂移 |
| 文档契约/验收注册 | 1 | 15条既有坏链接、5个其他未登记专项；本次新专项已登记visual且链接有效 |
| 工作区卫生 | 1 | 工程原有`outputs`、`_scratch`、`Godot`目录；本次全部过程产物写工程外，不清理其他会话目录 |

最终原生交互、两个局内商人专项与手柄专项均无非预期脚本错误。基地买卖专项唯一ERROR为上述预期拒写；另有既有GLB色盘UID回退及改造台非等值锚点warning，未改动其资产和布局。

未执行：全量core/full、实体手柄、全关卡所有服务页。`verify_pause_game_save_reset_flow`未单独运行，本轮输入回归由`verify_gamepad_input_flow`和正式远征原生GUI专项覆盖。不能据本轮四类页面通过宣称全游戏每个交互页均已验收。
