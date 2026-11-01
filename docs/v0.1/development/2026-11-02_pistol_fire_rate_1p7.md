# 2026-11-02 豌豆手枪射速 1.8 → 1.7 发/秒

> 业主原话：「改成1.7」。承接 2026-11-01 那轮（1.6 → 1.8），本次是从 1.8 **往回退一档**。
> 只动 `bp_pistol` 的 `fire_rate`，其余字段一条没动。

## 1. 落地值

| 字段 | 改前 | 改后 | 说明 |
|---|---:|---:|---|
| `fire_rate` | 1.8 发/秒 | **1.7 发/秒** | 两发间隔 0.556 s → **0.588 s** |
| `damage` | 25 | 25 | 未动（+ 标准弹 8 ⇒ 单发 33） |
| `magazine_size` | 10 | 10 | 未动 |
| `reload_time` | 1.8 s | 1.8 s | 未动 |
| `spread` / `range` | 0.03 / 15 m | 0.03 / 15 m | 未动 |
| `bullet_speed` | 0.6522（15 m/s） | 0.6522（15 m/s） | 未动 |

落地位置：`src/base/BlueprintRegistry.gd::_create_gunbody_pistol()` 一行，
`"fire_rate": 1.8` → `"fire_rate": 1.7`。

节奏后果（沿用前几轮同口径，单发 33）：裸 DPS `33 × 1.7 ≈ **56.1**`（改前 59.4）；
一匣 10 发打空 `0.588 × 10 ≈ **5.88 s**`（改前 5.56 s）+ 换弹 1.8 s ⇒ 单匣周期 **7.68 s**（改前 7.36 s）。

⚠️ **读数陷阱**：`reload_time` 也是 1.8 s，与上一版射速数值相同。读配置或看账本时别把
`reload_time=1.8` 当成射速 —— 11-01 那轮的返工就是因为业主口里的「1.5 发/s」其实是换弹时间的旧值。

## 2. 门禁同步

`tests/verification/verify_starting_weapon_contract.gd`：`EXPECTED_FIRE_RATE` 1.8 → **1.7**，
注释补上本次沿革。这条断言覆盖三层（装配节点 / 装配树 / `WeaponModel3D`），
不改就会在下次套件里直接报红：

```
ERROR: 豌豆手枪的 WeaponModel3D.fire_rate 是 1.70 发/秒，期望 1.80
```

## 3. 账本同步

### 3.1 内容数据库 `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`

- 《武器》`G22`：`fire_rate=1.8` → **`fire_rate=1.7`**，该格其余数值原样
  （`bullet_count=1；damage=25；magazine_size=10；reload_time=1.8；spread=0.03；range=15；
  bullet_speed=0.6522`）。
- 《武器》`N22` 备注：追加 2026-11-02 一段（改判原因、间隔/打空时间、其余字段不动、
  以及「换弹 1.8 与上一版射速同数」的提醒），前三段沿革保持原文。

### 3.2 武器账本 `assets/registry/ledgers/ShellStorm2_武器账本_v001.xlsx`

《域变更日志》追加第 20 行 `v0.1.112 / 2026-11-02 / 数值调整（内容侧）`：

- 记 `fire_rate 1.8 → 1.7`、节奏与 DPS 变化、业主原话、落地函数位置。
- 兼容性列写明：**本账本《资产主表》与《3D-武器》不持玩法数值** —— AssetID、Prefab/GLB 路径与
  SHA-256 全部不变，资产行无需复核；只有运行时 `base_stats` 变，旧存档
  `WeaponInstance.assembly_snapshot` 下次装配按新值重算。

## 4. 验收

| 用例 | 命令（headless，Godot 4.7.2） | 结果 |
|---|---|---|
| 出厂武器契约 | `verify_starting_weapon_contract.tscn` | `STARTING_WEAPON_CONTRACT_OK`（10 发 / 25 伤害 / 射速 1.7 / 换弹 1.8 / 弹速 15 三层核过） |

换弹、弹速、弹体视觉本次均未改动，对应用例（`verify_3d_reload_state_flow` /
`verify_bullet_vfx_profiles`）未复跑。

## 5. 未做

- **实机手感未验**：1.7 与 1.8 只差 0.03（间隔差 32 ms），实际能不能感觉出来要真机连点。
- 价格 / 掉落权重 / 合成成本仍未随射速联动（`price 70` 不变）。
- 未修正 2026-11-01 记录里「1.8 是目标值」的措辞 —— 那是当轮事实，后续改判只在本记录与沿革里追加。
