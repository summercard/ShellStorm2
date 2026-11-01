# 2026-11-01 豌豆手枪射速 1.6 → 1.8 发/秒，并补齐账本两轮欠账

> 业主原话：「豌豆手枪的射速，帮我调快一点，然后更新账本，现在是 1.5 发/s，改成 1.8 发/s」。
> 对象只有一把枪：出厂枪 `bp_pistol`「豌豆手枪」。伤害 / 弹匣 / 换弹 / 扩散 / 射程 / 弹速一律不动。

## 1. 口径校正：改前是 1.6，不是 1.5

业主说的「现在 1.5 发/s」与代码不符 —— 检索全仓后确认：

| 数字 | 实际含义 | 出处 |
|---|---|---|
| **1.6** | 改前 `fire_rate`（2026-10-31 定） | `BlueprintRegistry.gd::_create_gunbody_pistol()` |
| 1.5 | **换弹时间 `reload_time` 的旧值**（10-31 已改成 1.8） | 内容数据库 `G22` 里还留着 `reload_time=1.5` |
| 3.5 | 更早的射速（10-30 之前） | 同上 |

内容数据库《武器》`G22` 一直停在 **2026-10-30** 的口径（`fire_rate=3.5 / reload_time=1.5 /
bullet_speed=0.7525`），10-31 那轮按当时记录「不涉及资产、账本、关卡数据与存档 schema」跳过了账本 ⇒
账本比代码落后两轮。**这很可能就是「1.5」的来源**：打开账本看到的是 `reload_time=1.5` 或整行的旧值。

处理方式：按业主点名的**目标值 1.8** 落地（这是明确指令，不因基线差异改口径），
同时把「1.5 是换弹时间旧值」写进代码注释、验收器注释、账本备注与参考页，避免再次误读。

## 2. 落地值

| 字段 | 改前 | 改后 | 说明 |
|---|---:|---:|---|
| `fire_rate` | 1.6 发/秒 | **1.8 发/秒** | 两发间隔 0.625 s → **0.556 s** |
| `damage` | 25 | 25 | 未动（+ 标准弹 8 ⇒ 单发 33） |
| `magazine_size` | 10 | 10 | 未动 |
| `reload_time` | 1.8 s | 1.8 s | 未动 |
| `spread` / `range` | 0.03 / 15 m | 0.03 / 15 m | 未动 |
| `bullet_speed` | 0.6522（15 m/s） | 0.6522（15 m/s） | 未动 |

落地位置：`src/base/BlueprintRegistry.gd::_create_gunbody_pistol()` 一行，
`"fire_rate": 1.6` → `"fire_rate": 1.8`。

节奏后果（沿用 10-31 记录的同口径算法，单发 33）：裸 DPS `33 × 1.8 ≈ **59.4**`（改前 52.8）；
一匣 10 发打空 `0.556 × 10 ≈ **5.56 s**`（改前 6.25 s）+ 换弹 1.8 s ⇒ 单匣周期 **7.36 s**（改前 8.05 s）。
这把枪仍是「慢节奏、单发重」的定位，1.8 只是把手感从偏钝往可用方向挪一档。

## 3. 账本同步（本轮的重点）

### 3.1 内容数据库 `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`

- 《武器》`G22` 核心数值从 10-30 旧值整行替换为现行值：
  `bullet_count=1；damage=25；fire_rate=1.8；magazine_size=10；reload_time=1.8；spread=0.03；
  range=15；bullet_speed=0.6522（=15÷23，弹速 15 m/s）`
- 《武器》`N22` 备注：把 10-30 那段「射速 3.5 / 换弹 1.5 未动」标注为「已被后续两轮取代」，
  并追加 2026-10-31（1.6 / 换弹 1.8 / 弹速 15）与 2026-11-01（1.8）两段沿革 + 「1.5 是换弹旧值」的提醒。

### 3.2 武器账本 `assets/registry/ledgers/ShellStorm2_武器账本_v001.xlsx`

《域变更日志》追加 `v0.1.111 / 2026-11-01 / 数值调整（内容侧）`：

- 记 `fire_rate 1.6 → 1.8`、其余数值不动、落地函数位置、业主原话与「1.5」的口径校正。
- 兼容性列写明：**本账本《资产主表》与《3D-武器》不持玩法数值** —— AssetID、Prefab/GLB 路径与
  SHA-256 全部不变，资产行无需复核；只有运行时 `base_stats` 变，旧存档
  `WeaponInstance.assembly_snapshot` 下次装配按新值重算。

> 为什么改数值要动美术账本：该账本的《域变更日志》从 v0.1.101 起就承担「内容侧数值调整」的登记
> （10-14 的逐枪伤害/射速调整就记在这里），是这条链路的历史惯例，不是本轮新开的口子。

## 4. 门禁同步与反向自测

`tests/verification/verify_starting_weapon_contract.gd`：

- `EXPECTED_FIRE_RATE` 1.6 → **1.8**（`_check_assembly_contract` 核枪身、`_check_pistol_egt_baseline`
  核 `WeaponModel3D.fire_rate`，两侧共用同一常量）。
- 注释补 11-01 沿革与「1.5 是换弹旧值」的口径提醒；`PISTOL_*` 段落抬头同步。

**反向自测**（证明这条断言真的在核射速，不是空跑）：把 `EXPECTED_FIRE_RATE` 临时改回 1.6 后重跑，
两条断言同时报红 ——

```
ERROR: GunBody_Pistol 的 fire_rate 是 1.80，期望 1.60   ← 装配节点（数据层）
ERROR: 豌豆手枪的 WeaponModel3D.fire_rate 是 1.80 发/秒，期望 1.60  ← 武器模型（真正驱动冷却的字段）
```

恢复 1.8 后 `STARTING_WEAPON_CONTRACT_OK`。

## 5. 验收

| 用例 | 命令（headless，Godot 4.7.2 `~/Applications/Godot.app/Contents/MacOS/Godot`） | 结果 |
|---|---|---|
| 出厂武器契约 | `verify_starting_weapon_contract.tscn` | `STARTING_WEAPON_CONTRACT_OK`（射速 1.8 三层核过） |
| 换弹状态机 | `verify_3d_reload_state_flow.tscn` | `3D_RELOAD_STATE_FLOW_OK`（按 `reload_time` 动态取值） |
| 子弹视觉档位 | `verify_bullet_vfx_profiles.tscn` | `BULLET_VFX_PROFILES_OK`（手枪仍 2.00 档） |
| 战斗成长流程 | `verify_3d_combat_progression_flow.tscn` | `3D_COMBAT_PROGRESSION_FLOW_OK` |
| 文档契约 | `scripts/check_documentation_contracts.py` | 仅剩既有破损链接；本轮新增的 CHANGELOG 链接在记录落盘后消失 |

> 机器注记：Godot 在 **`~/Applications/Godot.app`**（不是 `/Applications`），文档里若写
> `/Applications/Godot.app/...` 会 `no such file or directory`。

## 6. 未做 / 待确认

- **没有实机手感验证**：1.8 发/秒（0.556 s 间隔）到底够不够「快」，只能真机连点才知道；
  数值门禁只保证「写进去的是 1.8」。
- **记账口径没重算**：单匣周期从 8.05 s 缩到 7.36 s、裸 DPS 52.8 → 59.4，但这把枪的 `price 70`、
  掉落权重、`SYN-PISTOL` 熔炼成本仍按 10-30 的子弹口径定，未联动（与 10-31 那次同样的未做项）。
- **没有一并回填的历史欠账**：其它枪身（步枪 / 霰弹 / 机枪 / 狙击 / 榴弹 / 蓄力炮）在内容数据库里
  是否也与代码有漂移，本轮只核了豌豆手枪，未做全表比对。
