# 远征03 宝箱免钥匙直开 + 命运卡购买 + 钥匙经济退役

日期：2026-11-05；记录ID：2026-11-05_expedition03_chest_keyless；功能ID：WORLD-PLAN / REWARD-SERVICE / WORLD-LOOT / FATE-CARD；
工程版本：0.1.0（`project.godot` 未改）。
设计依据与修订：`design/远征关卡03设计.md` §2.1 / §B.4 / §11.2 D2 由「待裁决」改为「已裁决」；
`design/怪物设计.md` §T8.3 / §T8.5 / §T9 / §T12 按新口径改写。代码基线：工作区（提交前标记工作区）。

## 1. 业主口径与改了什么

> 业主原话：「宝箱开启方式是直接开启，开启的同时会弹出命运卡购买界面，同时也会掉出掉在地上那个物品。
> 不需要使用钥匙，远征03 的这个钥匙掉落可以全部去掉，不需要钥匙掉落。」
>
> 追问确认（同日）：**只弹购买界面，不再自动发 1 张命运卡。**

| 项 | 改前 | 改后 |
|---|---|---|
| 宝箱开箱 | 需要 1 把房间钥匙 | **直接开启，不消耗任何钥匙** |
| 开箱产出 | 2 件物资落地 + 自动发 1 张命运卡 | 2 件物资落地 + **弹出三选一命运卡购买界面**（本局金币），**不自动发卡** |
| 宝箱拟态 | 钥匙照扣，击杀掉 2 件 + 1 张卡 | **不扣钥匙**，击杀掉 2 件、**不发卡**；**不弹购买界面**（战斗不能被模态卡住） |
| 钥匙小子 `egt_keybullet_kin` | 必掉 1 把钥匙 | 与其他普通怪同口径（只掉铸币） |
| 清房 20% 拾取物池 | 含「普通钥匙」权重 24.36 | 删该行，剩余 3 项按相对权重重新归一 |
| 清房钥匙掉落 | 门策略无 key ⇒ 本关本就不产 | 另加能力闸兜底 |
| 开局初始钥匙 | 1 把 | 本关 0 把 |
| 命运卡「太阳钥印」 | 可能出现在本关报价里 | 不进本关报价池 |

## 2. 代码与数据变更

| 文件 | 改动 |
|---|---|
| `art_source/design/whitebox/tower_zones/expedition_03/v001/data/level_plan.json` | **设计源**：`treasure_chests` 删 `requires_key`、`fate_card_per_open` 1→0；`monster_drop_table.rows` 删钥匙小子行；`clear_rewards.pickup.pool` 删钥匙行；三处 `note` 重写记录裁定 |
| `data/level_plans/expedition_03/level_plan.json` | 由 `scripts/sync_runtime_design_data.py` 重新投影（逐字节一致），手工改这个文件会被下一次投影覆盖 |
| `src/world3d/TreasureChest3D.gd` | 删除 `requires_key` 字段 / 配置读取 / 提示文案分支 / 快照字段；类注释改写 |
| `src/world3d/Dungeon3D.gd` | `_on_chest_open_requested()` 改为「收口形态 → 掉落落地 → `call_deferred` 弹购买界面」；`_show_door_fate_choices(source)` 加来源参数（门后 / 宝箱共用同一套弹窗与购买事务）；新增 `_room_key_economy_enabled()` 能力判据（默认 true）与 `_card_grants_room_key()`；三处清房文案不再无条件写「钥匙已掉落」；拟态日志 / 注释去掉钥匙语义 |
| `src/world3d/TowerDescent3D.gd` | 覆写 `_room_key_economy_enabled() → not _flow_rules_active`；flow 关卡把 `_room_key_count` 清零（读档会按快照覆盖，不吞携带钥匙） |
| `src/world3d/DungeonRoom3D.gd` | `chest_placements` 契约注释同步（`requires_key` 退役） |
| `src/map/FloorPlanGenerator.gd` | `_chest_placements_for()` 不再向放置层抄 `requires_key` |
| `tools/_egt_chest_probe.gd` | 按新契约重写：开局 0 把钥匙 / 直接开箱 / 掉落 = `drop_count` / 弹窗出现且为三选一 / **不自动发卡** / 不重复开 / 退弹窗后不残留输入锁 |
| `tools/_egt_drop_probe.gd` | 钥匙小子从「招牌掉落豁免」名单移除并反向断言 0% 掉物；清房池断言「有血瓶、无钥匙」；清房率期望改为**从配置推导**（弹药也是池内选项，删钥匙后期望由 19.2% 变 18.8%） |
| `tools/_egt_mimic_chest_probe.gd` | 断言改为「不扣钥匙」+「击杀不自动发卡」 |
| `assets/registry/ledgers/ShellStorm2_物品道具账本_v001.xlsx` | `掉落归属导航` 删两行钥匙（怪物掉落 / 清房池）并把后续下标前移；`物品道具` 的 `item_room_key` 审查备注补本关退役说明。备份 `*.bak_before_chest_keyless_20261105` |

**为什么用「能力」而不是关卡 ID**：`_room_key_economy_enabled()` 默认 `true`，只有 flow 关卡覆写为
`false`。`check_level_decoupling.py` 扫描的 7 个通用机制容器里没有出现 `"expedition_03"` 字面量
（实测 violations = 0）。

**兼容性**：`_room_key_count` 的存档字段、`item_room_key` 物品定义、`_consume_room_key()` 全部保留 ——
远征01 / 塔楼 / 99F 的钥匙经济逐字不变，只是本关不再有任何产生与消耗入口。

## 3. 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `godot --headless --path . --scene res://tools/_egt_chest_probe.tscn` | `test_mode = true`（不读写开发者档案） | **通过**：2 间宝箱房各 1 箱；`fate=0`；开箱掉落 +2；`_door_fate_active=true` 且三选一；免费卡 +0；重复开箱无新增；退弹窗后状态复位；**40 轮报价里 0 张「获得房间钥匙」卡** | `EGT_CHEST_PROBE_OK` |
| `godot --headless --path . --scene res://tools/_egt_mimic_chest_probe.tscn` | 同上 | **通过**：品质/拟态分布 62.3/25.9/10.0/1.9/19.7% 对 62/26/10/2/20；`chest_placements` 已无 `requires_key`；开箱不扣钥匙、不掉物；击杀掉回 ≥2 件、**0 张卡**；不算清房 | `EGT_MIMIC_CHEST_PROBE_OK` |
| `godot --headless --path . --scene res://tools/_egt_drop_probe.tscn` | 同上 | **通过**：33 只怪「钥匙小子 0% 掉物品」；清房拾取物构成 `{血瓶 86.4%, 货币 13.6%}`、无钥匙；拾取物率 16.7%（配置期望 18.8%）、弹药率 7.7%（期望 7.2%）；对照组（未配表关卡）仍走旧公式 | `EGT_DROP_PROBE_OK` / `EGT_CLEAR_REWARDS_PROBE_OK` / `EGT_LEGACY_FALLBACK_OK` |
| `python scripts/sync_runtime_design_data.py --check` | 工程外投影比对 | **通过**（42 文件 0 issue） | stdout `{"files": 42, "issues": []}` |
| `python scripts/check_level_decoupling.py` | — | **通过**：`violations = 0` | stdout |
| `python scripts/check_documentation_contracts.py` | — | 执行完成，**红项为既有**：旧 CHANGELOG 断链（2270/2282 行）、4 个未登记验证券、`openpyxl` 缺失导致媒体域检查未执行；本次新增文档未引入新红项 | stdout |
| `./scripts/run_verification_suite.sh batch probe_expedition03_playable probe_expedition03_save_roundtrip verify_fate_card_purchase_flow verify_expedition_level01_flow` | runner 独立项目壳 | **未执行**：预检 `check_expedition03_room_layouts.py` 返回 1（27 项既有的「TSCN 文件名门位指纹 ≠ metadata/portal_fingerprint」漂移，与本改动无关；该脚本只读 `room_templates/flows/door_catalog/corridor_catalog`，不读 `level_plan.json`），套件在第一步中止。**没有**因此放宽任何门禁 | 预检输出 27 条 `门位指纹不一致` |
| `python scripts/check_expedition03_room_layouts.py` | 直接运行 | 同上 27 项红（既有）；本次改动未触碰任何 TSCN / 房间模板 | stdout `ok: false, issues: 27` |

未执行项：`verify_fate_card_purchase_flow`（门后购卡，用于确认新增 `source` 形参未破坏旧入口）、
`probe_expedition03_playable`（`key_locked=0` 断言）、`probe_expedition03_save_roundtrip`（宝箱存档往返）。
三者都被同一预检红阻断；改动面已在 `_egt_chest_probe` 的正式场景里覆盖同一条代码路径，
但**门后入口的回归仍需在有绿预检的工作区补跑**。

## 4. 遗留与状态更新

- **预检红是仓库当前状态，不是本次引入**：`check_expedition03_room_layouts.py` 的 27 项
  门位指纹漂移需要单独修（重新烘焙 runtime_rooms 或回填 metadata），修完请补跑上表三条场景。
- **账本脚本与账本内容存在既有缺口**：`scripts/sync_inventory_item_ledger.py` 目前只从
  `expedition_01/level_plan.json` 与掉落 CSV 生成《掉落归属导航》，**不会**重建旧账本里已有的
  8 行远征03导航。直接 `--write` 会把远征03整段导航抹掉（本轮实测确认，已回滚改用手工精确更新）。
  今后改远征03掉落时：**不要再跑 `--write`**，按本次方式改指定行；或先补脚本的 03 分支。
- 未实现（有意）：拟态箱击杀后不弹购买界面。若业主希望「拟态也算一次购买机会」，
  应在击杀结算处补一次延迟弹窗，而不是在开箱那一帧弹（会卡住战斗）。
- 索引状态：`MODULE_INDEX` / `development/CHANGELOG.md` 已追加本条；`远征关卡03设计.md` 的
  D2 待裁决项已关闭。

---

# 追加：开箱前置 / 后置过渡（同日第二轮）

**日期**：2026-11-05
**起因**：业主「打开宝箱需要有前置动画，比如说点击之后宝箱会抖两下，然后箱子砰的一下打开，
然后上面才会弹出那个命运卡的界面。整个过程中需要有前置和后置，不要突然打开完全没有过渡。」

## 5. 时间轴与实现

| 时刻（秒） | 段 | 实现在哪 |
|---|---|---|
| 0.00 | 认领 + 抽奖 + 状态栏「宝箱开启中…」 | `TreasureChest3D.commit_opened()` / `Dungeon3D._on_chest_open_requested()` |
| 0.00–0.42 | 抖动两整周期（±3.8°） | `_play_open_sequence()` 的 `seq` tween |
| 0.42–0.47 | 回正 | 同上（`SHAKE_RECENTER_SECONDS`） |
| 0.47–0.59 | 蓄力：`scale.y 0.94`、盖子反压 +3° | `_begin_charge()`（`EASE_OUT`，见下） |
| 0.59 | 砰：盖子 −122° 过冲→−104°、箱体上跳 5.5cm、光 3.2→7.0、音效 −1.0dB、镜头冲击 0.14s；**掉落在此落地** | `_fire_burst()` / `Dungeon3D` 的 await |
| 0.59–0.95 | 余韵：回落、光降回 3.2、箱体压暗 | `_fire_burst()` 的第二段 tween + `_finish_open_sequence()` |
| 0.89–1.07 | 购买界面整体 `modulate.a` 0→1 | `Dungeon3D._build_door_fate_overlay()` 末尾的 intro tween |

新增对外契约：`OpenPhase` 枚举、`get_open_burst_delay()`、`get_open_phase()`、
`is_open_animation_done()`、`burst` 与 `open_animation_finished` 两个信号，
以及快照里的 `open_phase / open_phase_name / open_animation_done / burst_delay_seconds`。

## 6. 本轮踩到并修掉的四个坑（都是"看起来能用、其实错"）

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 掉落比「砰」早 0.05s，肉眼能看出"东西先出来、盖子后开" | `OPEN_BURST_DELAY_SECONDS` 只算 `抖动+蓄力`，漏了序列里那个写死的 `0.05` 回正 | 把回正提成 `SHAKE_RECENTER_SECONDS` 常量并计入总延迟 |
| 2 | 「砰」那一帧盖子只动了 2.5°，接着才慢慢转过去 | 蓄力 tween 还在跑，与弹盖 tween 抢 `rotation:x` / `scale`（谁后 process 谁赢） | `_fire_burst()` 先 `kill()` 蓄力 tween；引用存进 `_charge_tween` |
| 3 | 蓄力段几乎看不见（40% 进度才沉 0.6%） | `EASE_IN` 让 0.12s 的前半段接近静止 | 改 `EASE_OUT`，压扁量 0.965→0.94 |
| 4 | 出图第 4 格起盖子被裁出画面；采样点还整体后移 0.14s | ① 取景按**关着**的箱子算，开盖后顶端到 y≈1.55m；② 在 `_process` 里累加 delta，而 `get_image()` 同步阻塞 | ① 按开盖后包围盒定 `size=2.75`；② 改协程 + `Time.get_ticks_msec()` 绝对时钟 |

## 7. 顺带修的既有缺陷

`PlayerCameraFeedback3D` 的震动包络写死 `pow(remaining / SHAKE_DURATION, 2.0)`。
新增的「砰」需要**短震动**（0.14s），用固定 0.5 作分母会让包络恒 ≤0.078 ⇒ 振幅被压掉 92%，
等于没震。改为按本次震动的 `_shake_duration` 计算；`request_environment_impact()`
新增 `duration` 形参（缺省仍是 `SHAKE_DURATION`），既有调用方 `ReactiveProp3D` 逐字不变。

## 8. 本轮验证

| 命令/场景 | 结果 |
|---|---|
| `godot --headless --path . --scene res://tools/_egt_chest_probe.tscn` | **通过**（含第 ⑧ 条真实交互链路：`perform_interaction()` 开第二只箱，本房掉落 2 件 + 弹窗出现）。四时刻断言：T+0 已认领/阶段 SHAKING/掉落 0/未弹窗；T+爆点−0.06 仍无掉落且阶段为 SHAKING\|CHARGING；T+爆点+0.12 掉落 = 2 且未弹窗；T+0.40 弹窗出现、三选一、免费卡 0。收尾断言 `is_open_animation_done()` |
| 变异测试（把 `_play_open_sequence()` 直接跳终态，模拟"没有前置动画"） | **按预期报红 2 条**：`按下 E 的当帧箱子就已经开完了`、`「砰」之前动画阶段是 OPENED，期望 SHAKING / CHARGING`。证明这批断言不是空转 |
| `godot --headless --path . --scene res://tools/_egt_mimic_chest_probe.tscn` | **通过**（拟态不走普通序列，阶段直接落 OPENED） |
| `godot --headless --path . --scene res://tools/_egt_drop_probe.tscn` | **通过**（三条令牌全绿，未受影响） |
| `godot --path . --scene res://tools/_egt_chest_open_sequence_render.tscn`（**真实渲染**） | **通过**，出图 `outputs/verification/egt_chest_open_sequence.png` + 6 张单帧。每格实测变换：0.09s `rot_z=+3.78°` / 0.20s `rot_z=−3.80°` / 0.52s `scale_y=0.963, lid=+1.8°` / 0.64s `lid=−120.2°, pos_y=+0.048` / 0.82s `lid=−102.3°` / 1.20s `lid=−104°, phase=OPENED` |

未执行项：`verify_fate_card_purchase_flow`、`probe_expedition03_playable`、
`probe_expedition03_save_roundtrip` 仍被同一个既有预检红阻断（见 §3）；本轮新增的
弹窗淡入（`FATE_OVERLAY_INTRO_DURATION`）没有被门后购卡用例覆盖，
需在预检转绿后补跑 —— 淡入 tween 与退场 tween 抢 `modulate:a` 的那条已在
`_animate_fate_overlay_exit()` 里显式 kill，但那一条只有真实门后流程能验到。

## 9. 本轮查出的**既有 P0**：远征里按 E 开箱从来没生效过

走真实交互链路补断言时，第一次跑就红了，而且不是动画的问题：

```
room.chest_open_requested 的监听者数量：start=1，reward_01=0，reward_02=0，……其余房间全 0
按下 E 后：chest.is_opened() == false，phase == CLOSED，地上 0 件物品，不报任何错
```

**根因**：`Dungeon3D._prepare_layout_rooms()` 的连接表里有 `chest_open_requested`，
但**远征房间不走那条循环** —— `TowerDescent3D._append_plan_room_record()` 自己建房间，
它连了 `player_entered / prop_searched / service_activated / light_toggled / clutter_broken`，
**漏了 `chest_open_requested`**。信号从 `chest.open_requested` 到房间层是通的，房间再往上就断了。

后果：`perform_interaction()` 照常返回 true、箱子照常抖、音效照常响，
然后**什么都不发生** —— 不掉落、不弹窗、箱子永远停在可交互状态。没有一条日志。

**为什么之前一直全绿**：`_egt_chest_probe` 前几轮全部是 `tower._on_chest_open_requested(room, chest)`
**直接调处理函数**，正好绕过那两个信号。2026-10-29 的宝箱验收、2026-10-30 的拟态验收、
以及今天上午的免钥匙改造，全部继承了这个盲区 —— 数据链、掉落、拟态都对，
唯一的断点在被测路径之外。

**修法**：`TowerDescent3D._append_plan_room_record()` 补 `chest_open_requested` 连接，
与相邻 `clutter_broken` 同款 `is_connected` 守卫（那条注释里已经写过一次同类教训：
「漏这一行就等于远征里砸罐子永远不掉币，而且不打任何日志」——同一个坑，换了个信号）。

**防回归**：探针第 ⑧ 条改为用 `perform_interaction()` 开第二只箱子，断言本房掉落 = `drop_count`
且弹窗出现。**这条断言在修好之前是红的，修好后是绿的**，不是补一条永远为真的检查。

> 教训记在这里：**凡是「信号 → 处理函数」的链路，验收里必须至少有一条走信号的断言。**
> 直接调处理函数测的是处理函数，不是这条链路。

## 10. 遗留

- 拟态箱**不走**这套序列（它有自己的抖动 → 咬开 → 消失），本轮的阶段枚举对它只体现终态。
  这是有意的：两条动画的语义相反（"开箱得奖" vs "箱子是假的"），共用一套曲线会两边都不像。
- 开箱期间玩家**可以移动**（不为动画锁输入）。若业主希望"开箱时角色定住"，
  应在 `_on_chest_open_requested()` 起手处锁输入、在 `open_animation_finished` 处解锁 ——
  但要注意与 `PlayerInteractionController3D` 的既有输入锁互斥，不要嵌套。
- 镜头冲击强度 0.62（≈2.2cm 位移）是估的，没有实机手感回归。太弱会读不出"砰"，
  太强会像挨打（挨打是 11~19cm）。需要业主实机确认后定档。
- 其它走 `TowerDescent3D` 私有建房间循环的信号，**已做一次全量核对**（`DungeonRoom3D` 共 6 个信号）：
  `player_entered / prop_searched / service_activated / light_toggled / clutter_broken` 两条创建路径都已连，
  **只有 `chest_open_requested` 漏了**，本次补齐。两条路径现在对 6 个信号全覆盖。
  后续新增房间级信号时，**必须同时改两处**（`Dungeon3D._prepare_layout_rooms()` 与
  `TowerDescent3D._append_plan_room_record()`），否则就是这次这个形状的静默失败。
