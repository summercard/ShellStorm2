# 2026-10-31 豌豆手枪数值再调：射速 1.2 发/秒、换弹 1.8 s、弹速 15 m/s

> 业主原话：「换弹改成 1.8 秒，射速改成 1.2 发/秒，弹速改成 15M/S」。
> 对象只有一把枪：出厂枪 `bp_pistol`「豌豆手枪」。伤害、扩散、射程、弹匣、弹体视觉一律不动。

## 1. 落地值

| 字段 | 改前 | 改后 | 说明 |
|---|---:|---:|---|
| `fire_rate` | 3.5 发/秒 | **1.2 发/秒** | 两发间隔 0.286 s → **0.833 s** |
| `reload_time` | 1.5 s | **1.8 s** | `WeaponModel3D` 侧另有 `maxf(0.25, …)` 下限，不触及 |
| `bullet_speed` | 0.7525 倍率（17.31 m/s） | **0.6522 倍率（15 m/s）** | `PISTOL_BULLET_SPEED_MPS / BULLET_SPEED_BASE_MPS = 15 / 23` |
| `damage` | 25 | 25 | 未动 |
| `magazine_size` | 10 | 10 | 未动 |
| `spread` / `range` | 0.03 / 15 m | 0.03 / 15 m | 未动 |

落地位置：`src/base/BlueprintRegistry.gd::_create_gunbody_pistol()`。

节奏后果（给平衡用）：单发 33（枪身 25 + 标准弹 8）⇒ 裸 DPS `33 × 1.2 ≈ 39.6`；
一匣 10 发打空 **8.33 s** + 换弹 **1.8 s** ⇒ 含换弹 DPS `330 ÷ 10.13 ≈ 32.6`。
飞行时间射程内 `15 ÷ 15 = 1.00 s`（射程不变，所以弹速放慢后弹体在空中的时间变长一倍）。

## 2. 为什么弹速不再走《挺进地牢》换算

2026-10-30 的两次口径都错了：先是把 `Marine Sidearm` 的 `Shot Speed 25` 直接当 25 m/s，
业主说偏快；随后发现原作单位不是米（原作玩家 6.5 单位/秒 vs 本作 4.5 m/s ⇒ 1 单位 ≈ 0.6923 m），
换算成 17.31 m/s。2026-10-31 业主按上手手感**直接点名 15 m/s**，于是把"跨作换算"整个从句子里摘出去：

- 删掉 `EGT_UNIT_TO_METER` / `PISTOL_EGT_SHOT_SPEED` 两个常量（已无人使用，留着会让人以为还在换算）。
- 新增 `PISTOL_BULLET_SPEED_MPS := 15.0` 与 `BULLET_SPEED_BASE_MPS := 23.0`，
  枪身倍率写成 `PISTOL_BULLET_SPEED_MPS / BULLET_SPEED_BASE_MPS`（≈0.6522）。
- 换算过程（6.5 / 4.5 / 0.6923 / 17.31）不删，降级为注释与参考页里的沿革，防止下次有人重新推导一遍又踩回 25 m/s。

**结论留档**：跨作数字是档位不是米，但业主点名的手感值优先于任何换算公式。

## 3. 门禁同步（改数值必须一起改，否则下次跑套件直接红）

`tests/verification/verify_starting_weapon_contract.gd`：

- `EXPECTED_FIRE_RATE` 3.5 → **1.2**（`_check_assembly_contract` 用它核枪身）。
- 新增 `EXPECTED_RELOAD_TIME := 1.8`，并在 `_check_pistol_egt_baseline` 里补两条断言：
  装配节点 `reload_time`、`WeaponModel3D.reload_time`（后者是真正驱动换弹计时的字段）。
- `_check_pistol_egt_baseline` 顺带补 `WeaponModel3D.fire_rate` 断言 —— 原来射速只在数据层核过一次。
- 弹速常量改 `PISTOL_BULLET_SPEED_MPS := 15.0`，删掉测试侧的 `EGT_UNIT_TO_METER` / `EGT_MARINE_SHOT_SPEED`，
  三层断言（枪身倍率 / 挂标准弹后的装配树 / `WeaponModel3D.bullet_speed`）判据自动跟着变成 15 m/s。

## 4. 验收

| 用例 | 命令（headless，Godot 4.7.2） | 结果 |
|---|---|---|
| 出厂武器契约 | `verify_starting_weapon_contract.tscn` | `STARTING_WEAPON_CONTRACT_OK`（10 发 / 25 伤害 / 命运槽 8 / 射程 5 项核过） |
| 换弹状态机 | `verify_3d_reload_state_flow.tscn` | `3D_RELOAD_STATE_FLOW_OK`（按 `magazine_size` 与 `reload_time` 动态取值，未写死 1.5） |
| 子弹视觉档位 | `verify_bullet_vfx_profiles.tscn` | `BULLET_VFX_PROFILES_OK`（手枪仍 2.00 档，判定未变） |
| 新档交接 | `verify_new_save_handoff.tscn` | `NEW_SAVE_HANDOFF_OK`（98F 地面枪 / 99F 登出 / 重开拾取均正常） |

本次改动不涉及资产、账本、关卡数据与存档 schema，故未跑账本文档门禁之外的套件。

## 5. 文档同步

- `docs/v0.1/04_技术施工_战斗与局内成长.md` §6.1：逐枪定值改 15 m/s、倍率 0.6522；「弹匣与手感四项」
  写明射速/换弹改判；门禁描述补新断言；「对标依据」补一句"只对齐弹匣与手感定位，其余本作自定"。
- `docs/v0.1/reference/挺进地牢/初始手枪数据.md` §4：表格改为「原始 / 2026-10-30 / 现行」三列，
  新增 §4.2 说明 10-31 改判，并把 17.31 的推导降级为历史。
- `docs/v0.1/design/怪物设计.md` §T2.5 的「两把尺子」段落：玩家枪不再走换算，改为"手感由业主上手判定，
  优先于公式"，避免与敌人弹速口径混淆。

## 6. 未做 / 待确认

- **没有实机手感验证**：1.2 发/秒是否偏慢、0.833 s 间隔在半自动点击下会不会读成"卡枪"，
  只能真机跑一遍才知道；数值门禁只能保证"写进去的是这个数"。
- 换弹动画时长：表现层按 `reload_time` 驱动，1.5 → 1.8 s 后动作会被拉长，未出图确认是否穿模/拖沓。
- 备弹与商人定价未联动：射速砍掉 66% 后这把枪的 DPS 从 115 掉到 39.6，`ItemRegistry` 里 `price 70`、
  掉落权重、合成目录 `SYN-PISTOL` 的熔炼成本都没动 —— 若确认它现在是"弱枪"，需要单独一轮平衡，
  不能靠改这一个函数解决。
