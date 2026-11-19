# 命运卡正式入口改按稀有度固定售价

日期：2026-11-20；记录ID：2026-11-20_fate_card_fixed_price；功能ID：FATE-RULES；工程版本：0.1.0。
设计依据与修订：`docs/v0.1/14_技术施工_命运塔罗牌组.md` §7.1.0（现行定价，本轮新增）、§7.1、§2 第 8 条；`docs/v0.1/design/命运卡六关投放设计.md` 2026-11-20 修订。设计修订：FATE-RULES 定价口径 r4。
代码基线：`b7292904`（分支 `0.2` / `origin/0.2`）；交付提交：未提交（本轮按指令只留工作区）。

## 变更与原因

**问题**：正式远征里拾取「命运卡专用掉落物」后打开的三选一，用的是按参考编成收益推导的逐门报价 ——
`FateEconomyService` 用刚清完那间房的收益 × 稀有度份额，再按 `run_seed + offer_id + stable_card_id`
在上/下界之间取一次值，并对 `fate_sun_bounty` 单独封顶 100，最后还有「三张全买不起就把最低价压到当前余额」的保底降价。
结果是同一张卡在不同房间、不同门次、不同种子下价格不同，玩家看到的价和记下来的价都不可预期。

**业主确认的现行口径**：这个入口直接用**本局金币**买、按**稀有度**取**固定售价**，五档
`30 / 60 / 110 / 180 / 270`，同稀有度同价；不叠加房间、参考收益、种子、卡片特判封顶与余额保底降价；
展示报价与实际扣款取同一个值。

**代码变更**

| 位置 | 变更 |
|---|---|
| `src/world3d/Dungeon3D.gd` `_fate_fixed_price()`（新增） | 唯一售价函数：`FATE_PRICE_BY_RARITY[clampi(rarity)]`。正/逆位同价，不看方位。 |
| `src/world3d/Dungeon3D.gd` `_fate_price()` | 改为「本门冻结表优先，否则固定价」。冻结表里存的就是开单时写下的同一组固定价，所以展示行、悬停、存档 `price`、实扣四处恒等。 |
| `src/world3d/Dungeon3D.gd` `_show_door_fate_choices()` | 建单时按 `_fate_fixed_price()` 填 `_fate_door_quote`；不再调用 `frozen_quote_for_card()`。 |
| `src/world3d/Dungeon3D.gd` `_ensure_affordable_fate_choice()` | **整体下线**（删函数与唯一调用点）。余额不足只拒绝，不降价。 |
| `src/world3d/Dungeon3D.gd` `_fate_price_bounds()` | 收窄为 `{min = quote = max = 固定价}`；不再问经济服务。 |
| `src/world3d/Dungeon3D.gd` `_fate_price_door_index()` | **删除**（固定价下无「按门取价」概念）。 |
| `src/world3d/Dungeon3D.gd` `_import_door_fate_snapshot()` | 恢复到正式入口时，**未购**候选按当前固定价重新报价；**已购**位的报价原样保留（属已成交记录，且该位不可再买）。不整体重写存档。 |
| `src/game/FateEconomyService.gd` | 报价查询 `price_for_rarity / frozen_quote_for_card / price_bounds_for_card` 保留签名但**不再被生产代码调用**，且显式注明仅作历史价表解读。快照新增 `pricing_mode = "fixed_by_rarity"`，`budget_formula` 文案改为固定价口径；`schema_version` 不变（3），存档字段与语义未动。 |
| `tests/verification/verify_fate_level01_pool.gd` | 旧的「空钱包保底压价」断言反向钉死：要求该入口不存在、余额归零报价不变、跨 8 个门序号全部同稀有度同价。 |
| `tests/verification/verify_fate_economy_service.gd` | `_check_one_card_per_door()` 替换为 `_check_fixed_price_contract()`：钉住五档数字、`pricing_mode`，并把逐门价表改称「历史快照」只做打印核对；正式阶段改为逐张核对「报价 == 该稀有度固定价」且区间上下界同值。 |
| `tests/verification/verify_expedition01_reward_flow.gd` | 移除「room_02 普通卡报价 40—50」的旧断言，改为「正式入口普通卡固定价 = 30」，并保留历史价表可读性检查。 |

**未改动的部分**（逐项确认）：

- 随机候选：仍按关卡白名单每门无放回抽 3 张（`_gate_expedition_fate_offer`），正/逆位判定不变。
- 稀有度解锁统计：`FateEconomyService.max_unlocked_rarity()` 与阈值照旧，只作统计。
- 购买事务：`_purchase_fate_card()` 的预扣款 → `FateCardGameBridge.apply_card_with_source_selection()` →
  失败原额退款、已购幂等、满槽拒绝、余额不足拒绝、不可逆确认、输入锁与退场，全部未动。
- 其它入口：宝箱掉落（`ChestRewardService` / `TreasureChest3D`）、商人货架、自动贩卖机、占卜屋预选
  （`DivinationMenu`，仍不付款、不装配）、训练场（仍全量免费）均未改。
- 库存/货币口径：仍只动 `GameManager.currency`；`BaseManager.get_extraction_points()` 未触碰。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `godot --headless --path . res://tests/verification/verify_fate_economy_service.tscn -- --pure-only` | 无头；`APPDATA` 指向工程外临时目录 | **通过**（`FATE_ECONOMY_SERVICE_OK checks=115 failures=0`） | `econ3.log` 第 1039—1040 行 |
| `godot --headless --path . res://tests/verification/verify_fate_level01_pool.tscn` | 同上 | **通过**（`FATE_LEVEL01_POOL checks=2259 failures=[]`） | `pool.log` 第 108 行 |
| `godot --headless --path . res://tests/verification/verify_fate_card_purchase_flow.tscn` | 同上 | **通过**（`FATE_CARD_PURCHASE_FLOW_OK`，退出码 0）；实测扣款 `before=220 after=40`、失败退款 `before=150 after=150` | `purchase2.log` 第 81 行、`FATE_SCOPE_ATTEMPT` 两行 |
| `verify_fate_economy_service.tscn`（含正式远征全量段） | 同上 | **未完成**：跑到 `FATE_FORMAL_RESUME same=true` 之后停在测试赏金击杀段，日志 20 分钟无新增（进程仍在跑 CPU），人工终止。**未取证**，不计入通过 | `econ_full.log` 最后一行 `FATE_FORMAL_RESUME` |
| `godot --headless --path . res://tests/verification/verify_expedition01_reward_flow.tscn` | `APPDATA=…/2026-11-11_expedition01_flow/appdata`（该用例自带目录名断言） | **失败 3 项，属既有红**：本关 `spawn_overrides` 实际 21 条（断言仍写 4）、前两房基础拾币 98—106（断言仍写 78—86）、room_02 参考收益 52 不符。这三项**不涉及定价**，源自关卡数据 `floor_00.json` 在 `8cdf53e3`「接入远征01武装平台首领」后的编成变化；本轮新增的固定价断言 `FATE_PLACEMENT_ECONOMY_OK … fixed_normal_price=30` **通过** | `reward2.log` 第 20、21、25、29 行 |
| `godot --headless --path . res://tests/verification/probe_fate_fixed_price_formal.tscn`（聚焦补验：3 个真实种子 × 3 个真实来源房，正式凭据建单） | 无头；`APPDATA` 指向工程外临时目录；每例新建实例 | **通过**（`FATE_FIXED_PRICE_FORMAL_OK checks=25 failures=0`，退出码 0）。r0/r1/r2/r3 跨种子跨来源房分别恒为 30/60/110/180；成交 `quoted=60 deducted=60 slot 0→1`；余额 0 时报价仍 110、不扣款、不发卡、弹层不关 | `probe8.log` 第 152—154、281—283、354—360、476、477、497 行 |
| `python3 scripts/check_documentation_contracts.py` | 本地 | 49 条 issue，**新增 0**：命中文档的 3 条断链全部位于未改动的 `development/CHANGELOG.md`（2467/2480/2492 行） | 脚本 JSON 输出 |

**方法说明**：以上全部是**无头逻辑用例**；没有做真实渲染取证，也没有在真实游戏窗口里手动点击购买。
`verify_fate_card_purchase_flow` 里 `price := Dungeon3D.FATE_PRICE_BY_RARITY[...]` 原本就是按固定价写的，
本轮未改它的价格断言 —— 它现在全绿，说明展示价与实扣价确实同源。

### 证据强度分级：「仅改序号」不等于「跨种子」

这一条必须写在验收结论里，否则容易把弱证据当成强证据：

| 断言类型 | 实际做了什么 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| `verify_fate_level01_pool` 的跨门循环 | **只改 `_fate_door_offer_id` / `_fate_offer_price_index` 两个序号**，同一个远征实例、同一个 `run_seed`、`_fate_door_quote` 已被清空后直接调 `_fate_price()` | 固定价函数**不看门序号** | **不能**证明跨种子、跨来源房同价；也没有走正式建单路径，`_show_door_fate_choices()` 未被触发 |
| `verify_fate_card_purchase_flow` | 单个种子 `515151`、`test_mode` 夹具 | 展示价 == 实扣 == 发卡，退款守恒 | 不覆盖跨种子/跨来源房 |
| `verify_fate_economy_service --pure-only` | 纯服务 | 五档数字与快照口径 | 完全不碰正式入口 |

因此「跨种子 / 跨真实来源房同价」这一条**不能**用上面三行来签；它由下面的聚焦补验单独取证。

### 聚焦补验：正式入口 × 真实种子 × 真实来源房

新增探针 `tests/verification/probe_fate_fixed_price_formal.{gd,tscn}`。每个用例都**新建实例、换 run_seed**，
从**不同的真实来源房**生成 `item_fate_card_drop` 凭据并走 `perform_interaction()` →
`_show_door_fate_choices()` 正式建单，**不预填 `_fate_door_quote`**，报价全部由生产路径自己产生。

结果：**`FATE_FIXED_PRICE_FORMAL_OK checks=25 failures=0`**（退出码 0）。

| 种子 | 真实来源房 | 采样（卡 / 稀有度 / 报价 / 显示） |
|---|---|---|
| 515151 | room_01 | `fate_living_bullet` r1 60「购买 60」；`fate_barrage_copy` r1 60「购买 60」；`fate_sun_scorch` r2 110「购买 110」 |
| 770032 | room_02 | `fate_sun_extra_loot` r2 110；`fate_scale_node` r0 30；`fate_moon_dash` r2 110 |
| 421001 | room_03 | `fate_fuse_fire` r1 60；`fate_bullet_carry_gun` r2 110；`fate_gun_on_gun` r3 180 |

同稀有度跨种子/跨来源房聚合：**r0=30（1 样本）、r1=60（3 样本）、r2=110（4 样本）、r3=180（1 样本）**，
每组内数值完全一致且等于 `FATE_PRICE_BY_RARITY`，显示文本与报价逐字相符。

- **成交**：`TRADE_OK card=fate_living_bullet rarity=1 quoted=60 deducted=60 slot_before=0 slot_after=1`
  —— 显示价、实扣、发卡三者一致，且武器卡确实刻入了命运槽。
- **余额不足**：`SHORTAGE_OK card=fate_moon_dash rarity=2 quoted=110 shown='购买  110' wallet=0 slots=1 active=true`
  —— 钱包清零后报价**仍是 110**（不降价），没有扣款、槽位不变（不发卡）、购卡层保持打开。

**加载开销记录（避免把慢当成卡死）**：本机首帧前约 6 分钟，`load(ExpeditionLevel01_3D.tscn)` 单次约 2.8 分钟，
实例化约 23 秒，均与定价代码无关；同一台机器上并行跑着多个其它 Godot 进程。第一次带 240s 超时的运行因此被误杀，
延长到 900s 后一次跑通。这解释了上一轮 `verify_fate_economy_service` 正式段的「卡住」现象，但**不等于**该用例已通过——
它仍未取到整段结论，见下表。

## 遗留与状态更新

- **未提交、未推送、未合入 Boss 检出**。改动只存在于本任务独立工作树分支 `cindy/fate-card-shop-price`（基线 `b7292904`）。
- **正式远征全量段仍未取证**：`verify_fate_economy_service` 的 `_quote_phase_with_reward_fixture`（赏金击杀 → 实际收入 → 多阶段报价）
  在本机无头环境下长时间无新增日志。该段前半部分（`FATE_FORMAL_OFFER` / `FATE_FORMAL_PURCHASE` / `FATE_FORMAL_RESUME`）已打印且价格等于固定价，
  但整段不能签通过。**该缺口已由聚焦补验覆盖其中与定价相关的部分**（跨种子同价、成交、余额不足），
  仍未覆盖的是「多阶段赏金击杀长链本身」——它与售价口径无关。FATE-RULES 整体状态**不提升**。
- **聚焦补验的边界**：只验了三个种子 × 三个来源房、固定的五档中 r0/r1/r2/r3（r4 禁忌未在本次采样中出现，
  由纯测试 `verify_fate_economy_service --pure-only` 与固定表断言覆盖）。补验不覆盖真实渲染、不覆盖多人/读档中间态。
- **补验脚本的打印**：`probe_fate_fixed_price_formal.gd` 保留 `PROBE_STEP` 分步打印，便于下次遇到慢加载时区分
  「卡在 load / instantiate / add_child」而不是笼统报「卡住」。
- **存档兼容**：`_fate_door_snapshot_to_restore` 路径下，未购位会被重新报价为固定价；已购位保留原报价。
  未做旧的 `fate_run_state.door.quotes` 全量重写。若后续需要「旧档一律洗成固定价」的更强口径，需另行确认。
- **历史价表仍会生成**：`FateEconomyService.get_snapshot()` 仍输出 `door_price_table` / `price_bounds`，
  它们只用于核对与旧记录解读。后续若要彻底删除，应先确认没有外部探针依赖（当前 `probe_fate_door_price_alignment`、
  `probe_fate_surplus_spawn`、`verify_expedition_fate_surplus` 仍读取 `door_price_table`）。
- **文档**：`14_技术施工_命运塔罗牌组.md` 新增 §7.1.0 为现行定价唯一入口，§7.1 加「定价部分已被取代」抬头，
  §7.1 之后的历史经济公式整段标注为历史；`命运卡六关投放设计.md` 追加 2026-11-20 修订，明确第 2/4/5 条的价格部分作废。
- **账本**：内容数据库《命运卡》表**没有价格列**，本轮不新增列，稀有度列即为定价依据，故账本无需改动。
