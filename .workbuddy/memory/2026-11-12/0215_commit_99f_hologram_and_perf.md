# 0215 提交：99F 全息入场 + 出发保存失败修复 + 帧时间预热

## 业主口述

> 「提交」（只提交，未推送）

## 提交

`0ed6eee8` — **60 文件 / +4003 −1468**。三条并行事务，第二条是真缺陷修复。

| # | 事务 | 关键落点 |
|---|---|---|
| ① | 99F 远征入场全息仪式（扫描/凝实两模式） | `ExpeditionEntryPresentation3D`（新）、`VfxHologramEntry3D`（新）、2 个 vfx tscn、2 个叙事 json、`verify_expedition_entry_hologram_ceremonies`（manual） |
| ② | 基地出发恒报「保存失败」 | `BaseManager.has_runtime_checkpoint_provider()`、`ExpeditionDepartureService` 判据拆分 |
| ③ | 远征01/02 帧时间 | `Dungeon3D` 点位/几何复用、`BaseManager._read_validated_profile`、`AudioManager.warm_expedition_event_sounds()`、`VfxPool3D` 补 `FX01_TELEPORT_IN`、`ProjectilePool3D._create_projectile()`、`chest_spotlight_pool.gdshader`（新）、读条期首帧实绘闭合箱 |

## 这轮学到 / 需记住的

1. **`verify_ledger_split` 的 `failures` 只输出前 40 条**（`failures[:40]`），但
   `failure_count` 是全量。⇒ 只看 JSON 会误判「全在 enemies」。
   拿全量的办法：`sed 's/failures\[:40\]/failures/'` 复制一份到 `tmp` 跑，
   并设 `PYTHONPATH=tools/asset_pipeline`（否则 `ModuleNotFoundError: split_asset_ledger`）。
2. **账本失败从 228 降到 109 是真修**：特效账本顺手把 R 列 `==LOWER(...)`、S 列数组公式
   改回 `=LOWER(...)` / `=IF(COUNTIF(...))`，区间 6:61 → 6:64。既有 57 行内容列零改动。
3. **剩下 109 条拆解**：enemies 106（本轮未改，存量）、props 2（宝箱未进基线）、
   props/weapons 各 1 张 sheet 指纹、vfx 1 条（`VFX-ELITE-RENT-TRANSFER-TRAIL-3D`
   HEAD 与工作区指纹都等于 `77b17b1e…`，基线里是 `1bafa7b4…` ⇒ **基线侧陈旧**）。
   ⇒ 判「这条是不是我弄坏的」的正确姿势：分别算 HEAD 版与工作区版的行指纹，
   跟基线比——两边相同就是基线锅。
4. **`--baseline-only` 至今不可用**（主账本无《资产主表》表）。谁要刷基线得先修写入端。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306**（core 245 / visual 42 / smoke 6 / manual 13） |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `check_documentation_contracts` | 11 条断链，全是既有，新增 0 |
| `verify_ledger_split` | 红 **109**（上提交 228） |

## 未提交

`_probe_loop.txt`、`override.cfg.disabled_20261109`、`verify_main_story_boss_gate.report.json`
—— 三个产物垃圾，仍未跟踪、仍不在 `.gitignore`。
