# 收租人体型/受击盒：设定文档与两份账本同步

功能：ELITE-ROSTER / ENEMY-AI。主人要求「更新相对应的设定文档和账本」。

## 账本改了四处（都在既有行上改口，不新增资产）

**《敌人账本》`assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx`**
- `资产主表` r55（ENM-ELITE-ARMS-TAKER-3D）：N 规格（原「额外体型倍率2.5」→ 17 盒 + `M(L)` 与两级身高）、P 源码依据（补两份开发记录）、V 更新时间 2026-11-09、Y 备注追加 r14/r15。
- `3D-敌人` r11：J 碰撞方式、K 标准尺寸（同样从 2.5 改口）、P 备注追加。
- `域变更日志`：+2 行 v0.1.37（贴地补底柱）、v0.1.38（体型 1.5/4.00m），沿用 r78 的样式。

**内容数据库 `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`**
- `精英怪` r12 O 列（说明列）追加体型公式、两级身高、圆柱半径与门洞余量、受击盒 17。

## openpyxl 写回账本安全（实测，以后可复用）

- roundtrip 后 **50 个 ArrayFormula 全部保留**，「查重键」`==LOWER(...)` 与「查重结果」数组公式逐格不变。
- 六个 sheet 的 `dims / freeze_panes / dataValidation(3 与 3) / conditional_formatting(2 与 2) / merged / column_dimensions` **逐项相同**，只有《域变更日志》行数 78→80。
- 改账本前照既有习惯留 `*.bak_before_arms_taker_scale15_20261109`。

## 账本门禁：331 条既有红项，本次零新增

`check_asset_registry.py` 报 `issues=331`。**用备份文件临时换回跑一遍，同样是 331**，类别完全一致
（`dedupe_key_formula_wrong` 151 / `dedupe_result_formula_wrong` 151 / `sha_mismatch` 17 / `stale_overview_formula` 8 / `invalid_status` 2 / `missing_sha` 2）。
⇒ 判定为既有红项。`check_ledger_refs.py` exit 0 `LEDGER_REFS_OK`；`check_media_asset_domains.py` exit 0 `MEDIA_ASSET_DOMAINS_OK`（该门禁只覆盖 ui/audio/music 三域，不含敌人）。
`check_documentation_contracts.py` 仍 14 条断链，全是既有（06:255、07.3、支线、CHANGELOG 历史行），本次新增链接零断。

## 两个必须记住的发现

**① 真实注入链路以前没人盯**。夹具 `make_enemy()` 从不传 `elite_growth_profile` ⇒ 专项一直测 `Enemy3D` fallback（1.0/0.06）。已加 4 条走真实路径的断言：`EliteRosterService.get_record()` → `apply_archive_to_enemy_config()` → `Enemy3D`，钉住 `body_scale_base` 透传、实例 `scale.y = 0.70×1.5`、运行时快照不钉旧值。

**② 旧档不会锁旧体型**。`EliteRosterService._default_record()` 不含 `growth_profile`，档案 schema 也从不持久化它（全仓 grep 无写入点）⇒ `get_record()` 的 `growth_profile` 永远来自当前内容库。反过来说：**谁以后把 `growth_profile` 写进存档，就会让老玩家永远停留在他存档时的体型**。

## 反向对照（断言有牙齿）

把 `EliteContentCatalog` 临时改回 `1.0 / 0.06` 重跑 `verify_second_elite_state_flow` ⇒ 退出 1，**8 条精准变红**：
1 级系数 1.0、1 级身高 2.450m、12 级 4.067m 越过 4.00 上限、12 级碰撞半径 0.948m 越线、头顶盒 2.004m、真实链路 `body_scale_base` 掉回 1.0、真实链路实例 scale 0.7000、运行时快照钉旧值。恢复后回 `checks=1441` / exit 0。

## 1.5 倍下受击盒重测（契约里旧数字已修正）

| 项 | 1 级 λ=1.5 | 12 级 λ=1.632 |
|---|---|---|
| 世界身高 | 3.675 m | 3.998 m |
| 头顶受击盒顶 | 2.921 m | 3.185 m |
| 补底柱 y | -0.001 ~ 1.983 m | 同比例 |
| y=0.8 处侧缝 | 0.096 / 0.168 m | 0.104 / 0.182 m |

均 < 弹径 0.24 m，最紧余量 **58 mm**；侧缝随 λ 线性增长 ⇒ **临界 λ ≈ 2.15 倍**（远高于 12 级上限 1.632）。抬 `body_scale_base` 或 `body_scale_per_level` 必须重算这条缝。

## 文档落点

契约升 r15（体型公式 + 门洞余量 + 侧缝临界值）、`怪物设计.md`、`01_内容数据库说明.md §5.4` 新增体型派生口径、`MODULE_INDEX.md`、`06_技术施工` 与 `14.6` 契约号、两份开发记录、CHANGELOG。
