# 17:0x 提交 f48abbb7 / 00f8b54c（特殊道具 r4–r6 + 契约漂移修复）

工作区已清空，**2 个提交待推送**（业主本次只说「提交」，未推送）。
判据：`git status -uall` 无输出，`rev-list --count origin/0.1.2..HEAD` = 2。

## 两个提交

| 提交 | 内容 |
|---|---|
| `f48abbb7` | 特殊道具 r4–r6：火焰统一 + 伤害翻倍并伤玩家 + 范围伤害纳入陈设 + 末段渐隐；顺手修 molotov 契约 radius 漂移 |
| `00f8b54c` | r4–r6 落到 5 本账本 + 内容库 + 设计正文（r3 → r6）+ 今日记忆 |

## 数值终态（回读 `data/special_items/catalog.json`，别信旧 commit message）

| 道具 | 半径 | 伤害 | 其他 |
|---|---|---|---|
| 手雷 | 3.0 m | 90 一次 | 冷却 1.2 s，**不伤玩家**（范围契约未改） |
| 燃烧瓶 | 1.25 m | **12 / 0.5 s = 24 dmg/s** | 5 s；0.12 s 后起火；**伤玩家含施放者** |
| 汽油瓶 | 0.58 m | **16 / 0.5 s = 32 dmg/s** | 每片 5 s；干油 45 s；**伤玩家含施放者** |

r4 起汽油油片也走 `VFX-FATE-FIRE-3D`（1 簇），瓶火/灯火 5 簇，
单簇 `FLAME_SIZE` 固定 **1.25**（不随范围缩）。`VFX-SPECIAL-FIRE-3D`
保留为既有资产但本系统已不再引用它做地面燃烧。

## ⚠ 踩到并修掉的：asset_contract.json 与 catalog.json 漂移

`art_source/items_weapons/props/special_molotov/asset_contract.json` 的
`radius` 停在 **2.4**，而运行时 catalog 与账本早就是 **1.25**（r3 改的）。

**成因**：契约由 `scripts/blender/build_special_items.py::record_contracts()`
**从 catalog 复制生成**（`contract = dict(definition)`），r3 只改了数值、
没重跑该脚本 ⇒ 契约停在旧值，且**没有任何门禁盯着**：
- `verify_special_item_sources` 只校验 GLB/源 blend 的 sha256，**不读契约数值**
- `check_special_item_delivery` / `check_asset_registry` 也不比这层

**已手工对齐**，并用一次性脚本逐字段比对三件道具 contract vs catalog ⇒ `ALL_OK`。

**待补**：给 `record_contracts` 加一条「契约 == catalog」的一致性断言，
或让交付门禁读契约数值。否则下次改 catalog 又会分叉，而且静默。

## r6 修的一个真缺口（值得记）

范围伤害（手雷爆炸、火焰 tick）原来**只遍历 `enemy_3d`** ⇒ 打不到易碎物和家具。
现在 `_damage_targets()` 覆盖 `enemy_3d` / `reactive_prop_3d` /
`breakable_clutter_3d` / `interaction_provider_3d`（+可选 `player_3d`），
按节点去重，只收有 `take_damage` / `take_projectile_damage` 的。

陈设判距用**可见网格世界包围盒的最近表面**（`MeshInstance3D.is_visible_in_tree()`
+ `global_transform * get_aabb()` 合并），配 `GROUND_MASK=1` 遮挡射线并
**排除目标自身碰撞体** ⇒ 不穿墙、不跨楼层。

## 本机未做的验证（如实记录）

未复跑 `verify_special_items_*`、未跑原生渲染。「85 核心 / 19 接线 / 10 专项
通过」来自并发会话日志，我未独立验证。本机独立跑通的只有：
`verify_ledger_split`（assets=1433 ledgers=9 failure_count=0）与
`check_level_decoupling`（violations 0）。
