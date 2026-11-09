# 2026-11-09 晚 豌豆手枪改判：弹匣 10 发、备弹无限

> 业主原话：「豌豆手枪应该是弹夹保持 10 发，打完后备弹无限。」
>
> 这是同日早先那版「弹匣无限（开火不扣弹）」的**改判**。早先那版作废，字段也改名 ——
> 详见 §3 的对照。

## 1. 落地值

| 字段 | 早先那版（已作废） | **现行** | 说明 |
|---|---:|---:|---|
| `magazine_size` | 12 | **10** | 回到 2026-10-30 的值 |
| `infinite_ammo` | `true` | **字段删除** | 语义已改，改名重写 |
| `infinite_reserve_ammo` | — | **`true`** | 新增 |
| `fire_rate` | 2.3 | 2.3 | 未动 |
| `reload_time` | 1.4 s | 1.4 s | 未动 |
| `damage` | 25 | 25 | 未动（+ 标准弹 8 ⇒ 33） |
| `spread` / `range` | 0.03 / 15 m | 0.03 / 15 m | 未动 |
| `bullet_speed` | 0.6522（15 m/s） | 0.6522（15 m/s） | 未动 |

落地位置：`src/base/BlueprintRegistry.gd::_create_gunbody_pistol()`。

## 2. 行为语义（这是本条唯一要记住的东西）

```
照常：开火扣 1 发 → 弹匣 10 发打空 → 需要换弹 → 1.4 s 后满匣
不变：开火冷却 1/2.3 = 0.435 s；换弹动作 / 换弹音效 / nth_after_reload 全部保留
变的是：换弹**不向备弹提供者扣数** ⇒ 背包里 0 发备弹也能一直换，每轮白拿满匣
```

| 做 | 不做 | 为什么 |
|---|---|---|
| 弹匣照常消耗 | ~~开火不扣弹~~ | 不扣弹会让「10 发弹匣 + 1.4 s 换弹」这套节奏失去全部意义 |
| 换弹照常 1.4 s | ~~跳过换弹~~ | 跳过会废掉换弹动作剪辑、换弹音效、`nth_after_reload` 首发强化、命运卡换弹构筑 |
| 只在换弹出口豁免备弹 | ~~给背包塞 999 发~~ | 塞备弹会让背包 UI、存档、堆叠口径全部被污染，而且切到别的枪时数字会突然变化 |

代码只有三处开关（开火路径**零改动**）：

1. `WeaponModel3D.request_reload()` —— 跳过「备弹余量 ≤ 0 就拒绝」那条检查；
2. `WeaponModel3D._finish_reload()` —— 不调 `_reload_ammo_provider`，`loaded` 直接取缺口；
3. HUD —— 备弹段显示 `∞`（`HUDPresenter3D` 下发 `ammo_reserve_infinite`，`Dungeon3D` 拼串）。

**HUD 分工**：当前弹数显示**真实值**（10 → 9 → … → 0），只有备弹段是 `∞`。
早先那版把当前弹数显示成 `∞`，改判后必须纠正 —— 弹匣真的会空，显示 `∞` 就是骗玩家。

## 3. 节奏与 DPS

```
两发间隔   1 / 2.3 = 0.435 s
一匣打空   0.435 × 10 = 4.35 s
单匣周期   4.35 + 1.4 = 5.75 s
换弹占比   1.4 / 5.75 = 24.3%   ← 长期 DPS 的唯一上限，不再是弹药总量
裸 DPS     33 × 2.3 = 75.9
持续 DPS   33 × 10 / 5.75 = 57.4
```

对比早先那版（弹匣 12 且开火不扣弹）：那版实际上**没有换弹这件事**，等于无限持续开火，
不过 `fire_rate` 仍是 2.3，所以 DPS 数字相同 —— 差别全在**手感**：那版手指只需扣一次扳机，
这版每 4.35 s 逼玩家经历一次 1.4 s 的换弹停顿。这也是业主要「弹夹保持 10 发」的实际效果。

## 4. 验收

| 用例 | 结果 |
|---|---|
| `verify_starting_weapon_contract` | `STARTING_WEAPON_CONTRACT_OK`，exit 0 —— **10 发弹匣** / 25 伤害 / 命运槽 8 |
| `verify_guaranteed_loadout_ammo_flow` | `GUARANTEED_LOADOUT_AMMO_OK`，exit 0 —— 见下 |
| `verify_finite_ammo_flow` | `FINITE_AMMO_FLOW_OK`，exit 0（字段名同步；样本枪仍是步枪） |
| `verify_3d_reload_state_flow` | `3D_RELOAD_STATE_FLOW_OK`，exit 0 |
| `verify_hud_presenter_3d` | `HUD_PRESENTER_3D_OK`，exit 0 |
| `verify_opening_script_runtime` | `verify_opening_script_runtime_OK checks=126`，exit 0 |

`verify_guaranteed_loadout_ammo_flow` 本轮重写的四组判据（都是**反向**的，专门挡回退）：

- B：`infinite_reserve_ammo == true` 且 `magazine_size == 10`（不是 12）；
- C：**开火照常扣 1**（若有人改回「不扣弹」，这条直接红）；空匣开火被拒**且自动起换弹**；
- D：无备弹时换弹成功、补满、**不产生备弹**；连打**两轮**空匣，证明不是只白送一次；
- HUD：当前弹数前缀是真实数字、串里含 `∞备弹`。

**未执行**：真机手感、真渲染、跨枪切换时的 HUD 观感、完整套件。

## 5. 同步

- `src/base/BlueprintRegistry.gd`：枪身 `magazine_size` 12 → 10、`infinite_ammo` → `infinite_reserve_ammo`、沿革注释重写；
- `src/combat3d/WeaponModel3D.gd`：字段改名 + 语义注释、开火路径恢复扣弹（删两处豁免）、`request_reload` / `_finish_reload` 保留豁免、snapshot 字段同步；
- `src/ui/HUDPresenter3D.gd`：`ammo_infinite` → `ammo_reserve_infinite`；
- `src/world3d/Dungeon3D.gd`：HUD 当前弹数恢复真实值、备弹段按新字段显示 `∞`；
- `tests/verification/verify_starting_weapon_contract.gd`：`EXPECTED_MAGAZINE` 12 → **10**；
- `tests/verification/verify_guaranteed_loadout_ammo_flow.gd`：B/C/D/HUD 四组按新语义重写；
- `tests/verification/verify_finite_ammo_flow.gd`：字段名同步；
- 内容数据库《武器》`G22`：`magazine_size=10` + 新增 `infinite_reserve_ammo=true`，`N22` 追加晚场改判记录；
- 武器账本《域变更日志》第 22 行 `v0.1.114`；
- `docs/v0.1/04_技术施工_战斗与局内成长.md` §6.1（现行值表 + 弹匣四项 + 新增「备弹无限」条 + 门禁段）、§6.6；
- `.codex/skills/…` 与 `skills_drafts/…` 的出厂枪说明。

### 5.1 账本补登（2026-11-09 22:00 追加）

第一轮只写了内容库与武器账本，**漏了两处、错了一处**，本次补齐：

- **《物品道具账本》→《掉落归属导航》新增 2 行**（原 21 行 → 23 行）。远征01 那组宝箱保底此前
  **完全没有登记**：`clear_drops.room_guarantees[0].weapon_choices`（蓝品霰弹/步枪二选一，归属武器账本，
  引用《背包物品调用索引》`A6 / A7`）与 `…items[0]`（`item_ammo_pack` ×100，归属物品道具账本，
  引用《物品道具》`A20`）。该表第 2 行的说明同步补上「远征01 宝箱保底指向 `clear_drops.room_guarantees[n]`」
  —— 原说明只承认远征01 走 CSV、远征03 走 level_plan，与实际不符。
- **《物品道具》`A20`（`item_ammo_pack`）第 8 列**补一行来源：
  `data/level_plans/expedition_01/level_plan.json#clear_drops.room_guarantees[0].items[0] / 宝箱保底 100 发`。
- **内容库《总览》第 6 行第 8 列口径错误**：原写「初始步枪 `bp_starter_rifle` 为出厂白送枪，命运槽 4」，
  这是 2026-10-30 之前的旧事实。改为「2026-10-30 起出厂白送枪为豌豆手枪 `bp_pistol`（命运槽 8、
  2026-11-09 起备弹无限）」，初始步枪改述为普通内容。
- **主账本《版本记录》新增 `v0.2.4`**（2026-11-09，「玩法数值 / 掉落登记（跨域）」），记录本轮三项。
  此前 10-14 的武器数值调整只记在武器账本，但本轮跨了武器 / 物品道具 / 关卡配置三层且改了登记结构，
  按「跨域才进主账本」的约定应当留一行。

> ⚠ **openpyxl 保存会清空公式缓存值**（实测：内容库 129/129、武器账本 88/88 全部变成 `None`）。
> 仓库里没有任何脚本用 `data_only=True` 读账本，`check_asset_registry.py` 走的是公式文本，因此不影响门禁；
> 但 Excel/WPS 打开时若处于「手动重算」会看到空白。已给三本账本加 `fullCalcOnLoad = True` 强制重算。
> 物品道具账本本来 0 公式，无此问题。

校验：`ASSET_REGISTRY` 问题数改动前后**逐项相同**（331 条全为既有：enemies R/S 双等号与数组公式、
vfx 总览 8 格、props 缺 SHA、scenes 哈希漂移），`LEDGER_REFS_OK`、`MEDIA_ASSET_DOMAINS_OK`。

## 6. 风险 / 未做

- **手感未验**：每 4.35 s 一次 1.4 s 停顿是明显节奏，真人上手才知道是不是太碎。若嫌碎，调的是
  `magazine_size` 或 `reload_time`，**不是**把 `infinite_reserve_ammo` 关掉。
- **弹药经济**：手枪彻底不吃弹药后，`item_ammo_pack` 对它变成纯装饰。玩家若一直只用手枪，
  关卡保底那 100 发会一直堆在背包里 —— 这是预期，但它让「远征01 必掉 100 发」对纯手枪流玩家价值下降。
- **拟态箱 / 换弹构筑**：`nth_after_reload`（换弹后首发强化）在无限备弹下触发频率不变（仍靠换弹），
  这条是好消息；但「备弹越多越强」类构筑（若有）对这把手枪失效。
