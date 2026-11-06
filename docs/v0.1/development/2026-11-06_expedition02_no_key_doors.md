# 远征02 开门免钥匙 + 钥匙经济退役（与远征01 同一套门方案）

日期：2026-11-06；记录ID：2026-11-06_expedition02_no_key_doors；
功能ID：WORLD-PLAN / WORLD-GATE / WORLD-LOOT；
工程版本：0.1.0（`project.godot` 未改）。
设计依据与修订：`design/远征关卡02设计.md` 页首新增「2026-11-06 裁定（门与钥匙）」块、
§4.7 补门的开启条件、§13 新增 L02-13（已落地）与 L02-14（待裁决）；
`关卡接入规范.md` §3.1.2 增「当前使用情况」表。代码基线：工作区（提交前标记工作区）。

## 1. 业主口径与改了什么

> 业主原话：「远征02的关卡的方案也改成这种，以后不掉落那种大钥匙，开门逻辑不需要身上有钥匙，
> 只要本房间怪物清理后即可。更新设计文档。」

| 项 | 改前 | 改后 |
|---|---|---|
| 开门要钥匙 | `requires_key = true`（`_door_policy_for_edge` 缺省） | **全部边 `false`** |
| 开门弹命运卡 | `triggers_fate = true` | **`false`**（与 01 同口径） |
| 清房门槛 | `true` | **保留 `true`** —— 清完怪门就是可开启状态 |
| 清房掉钥匙 | 每间产钥匙房掉 1 把 `item_room_key` | **不掉** |
| 开局初始钥匙 | 1 把 | **0 把** |
| 清房掉落（宝箱） | — | **本轮不加**，理由见 §4 |

## 2. 只改数据，没改代码

这两项都是 2026-11-06 上午为远征01 建好的**能力段**，02 只是在自己的计划里写上同样的字：

| 文件 | 改动 |
|---|---|
| `data/level_plans/expedition_02/level_plan.json` | 新增 `door_policy`（`requires_clear=true` / `requires_key=false` / `triggers_fate=false`）与 `economy.room_keys_enabled=false` 两段，含裁定原文与边界说明 |
| `scripts/build_expedition02_level_plan.py` | 生成器同步写这两段 —— **不写进生成器 = 下次重跑就被抹掉**，而运行时对缺段是**静默**回退到「要钥匙 + 弹卡」，不报错、不打日志 |
| `tests/verification/verify_expedition02_door_policy.gd` `.tscn`（新增） | 真场景跑 35 条边 + 清房/开门/不掉钥匙断言 |
| `src/…` | **零改动**。`TowerDescent3D._door_policy_for_edge()` / `_room_key_economy_enabled()` 早已按「计划有没有写这一段」分支 |

**为什么能零代码**：`_plan_door_policy` 在 `_build_expedition_records()` 里从不认识的 `plan` 字典读取，
优先级在固定交通接口之后、flow 默认之前。02 与 01 走同一条 bootstrap，因此数据一写即生效。
`check_level_decoupling.py` 依然 0 违规（通用层无 `"expedition_02"` 字面量）。

## 3. 两个容易踩的边界（已写进设计页与探针）

1. **和平区在改动前就全放行。** `room_02`（长廊）、`room_13`（T字横廊）、`room_14/15`（两条支廊）
   与 4 间无编成事件房是 `authored_layout_peaceful`，`_door_policies_for_record()` 早就给它们三项全 false
   （§13 L02-12 的「丙」实施结果：走廊不摆刷怪盒）。所以本轮**真正被改掉的是 20 间客房 + 前厅那批门**，
   不是走廊门。探针按房型分别断言，就是为了不让「走廊本来就不用钥匙」被当成本轮的功劳。
2. **入口交通门两侧都免费。** `_expedition_entry_gate_edges` 用的是无序 `_edge_key`，
   命中 `start↔room_01` 整条边 ⇒ 回程也不查清房。探针首版按「来源房不是 start 就要清房」写，
   因此把 `room_01→start` 判红了一次，改按「入口门两侧都免」后复绿 —— 这条口径本身是既定设计，不是缺陷。

## 4. 为什么本轮不给 02 加宝箱（重要）

01 那套改动里，「清房掉钥匙」被换成了「45% 掉宝箱 / Boss 保底一只」。02 **不能照搬**：

- 02 的 `level_plan.json` **没有** `monster_rules` / `monster_drop_table`
  ⇒ `RuntimeRewardCoordinator` 的 `_level_currency_rules` 为空 ⇒ `currency_spec_for()` 直接返回 `{}`
  ⇒ **击杀不产金币**；
- 而宝箱一开就弹命运卡购买界面（`_show_door_fate_choices("chest")`），本关钱包恒为 0
  ⇒ `_ensure_affordable_fate_choice()` 会把最低价那张压到 **0 元** ⇒ **白送卡**；
- 本关也还没有 BOSS 房与 EXTRACTION 房（`floors/floor_00.json` 只有 26 间 COMMON/SAFE，见 §13 L02-10/L02-9），
  `clear_drops.boss` 段会直接落空。

所以本轮**只做业主明确要求的两项**，宝箱与命运卡入口一起挂到设计页 §13 **L02-14** 等货币口径。
补法有两条，等主人选：① 先照 01 给 02 写 `monster_rules.currency`（per_kind 基础值 + per_floor × 层号），再上宝箱；
② 本关不上宝箱，客房清房只掉物资。

## 5. 验收

**执行方式**：正式工程目录、临时把用户目录切到 `ShellStorm2TmpExp02` 跑单场景，跑完已还原 `project.godot`。

| 项 | 结果 |
|---|---|
| `verify_expedition02_door_policy` 首版 | 退出码 1，`edges=35`，**1 条失败**：`room_01→start` 清房门槛与预期不符 —— 探针自己的期望写错（入口交通门两侧都免），非实现缺陷 |
| `verify_expedition02_door_policy` 修正后（改名前叫 `probe_…`） | **退出码 0，`EXPEDITION02_DOOR_POLICY_OK edges=35`**（35 条边全部免钥匙、全部不弹卡；清房门槛按和平区/入口门逐边对齐；开局 0 钥匙；清房不掉钥匙；清房后免钥匙开门成功且不弹卡） |
| 未受影响而**未重跑** | `probe_expedition02_assembly` / `_camera_profiles` / `_door_coverage` / `_light_diagnostic` / `_live_view` —— 本轮只动门策略与钥匙开关，不碰几何、相机、门扇装配与光照；但这几条**没有在本轮重新验证** |
| **变异测试（反向验证）** | 临时删掉 `level_plan.json` 的 `door_policy` + `economy` 两段 ⇒ **退出码 1**，红项精准命中：`钥匙经济应已退役（仍为 true）`、`开局仍发了初始钥匙：1`、`room_01→room_02 仍要求房间钥匙／开门仍会弹命运卡: {requires_clear:true, requires_key:true, triggers_fate:true}` 等。还原后复跑退出码 0 ⇒ 断言不是恒真 |
| `python scripts/check_level_decoupling.py` | 退出码 0，violations 0 |
| `python scripts/check_documentation_contracts.py` | 退出码 0；issues 全为既有项（见远征01 同日记录） |

## 5.1 为什么最后把它登记进 core 套件

首版按 `probe_` 命名，`check_documentation_contracts.py` **立刻报错**：
`Feature traceability invalid: WORLD-GATE: verification scene is not registered`。
该门禁只认 `verify_*` 且在 `run_verification_suite.sh` 里登记过的场景 —— 这条约束正好是本功能需要的：
**「计划里的两段数据」是唯一的真源，而它一旦被抹掉，运行时静默回退到老口径。**
所以改成 `verify_expedition02_door_policy` 并登记进 `core_scenes`（列表末尾，带一行原因说明）。
代价是该场景要吃一次远征02 整层装配（约 100 s）。

## 6. 生成器漂移（既有问题，本轮未修）

`scripts/build_expedition02_level_plan.py` 的当前输出与仓库里的数据**不一致**：它会把
`level_plan.json` 的 `hotel_wall_height_m` 从 **4.0 改回 3.0**，并从 `floors/floor_00.json` 删掉 27 行。
即仓库数据在生成器最后一次运行之后被手工更新过（4.0 是 2026-10-13「墙顶补到顶盖底」那一轮的口径）。

本轮的处理：**不重跑生成器**（会把既有工作冲掉），只把手写的两段补进生成器源码，
让「将来真的重新生成」时不再丢掉门策略。那 27 行与墙高 3.0/4.0 的漂移**保持原样**，
单独记为待处理项 —— 谁去修它，得先把 `hotel_wall_height_m` 的权威值定下来。
