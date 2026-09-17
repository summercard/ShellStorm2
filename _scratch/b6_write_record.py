# -*- coding: utf-8 -*-
"""B6 执行记录写入计划文档（字节级、保 CRLF）。

三处改动：
  1) 状态行（第 3 行）追加 B6 已完成
  2) 批次表 B6 行（第 77 行）标 ✅ 已完成 + 明细
  3) 在「### P4 执行记录」前插入「### B6 执行记录」
"""
from pathlib import Path

DOC = Path("docs/v0.1/development/2026-09-17_godot_asset_deversioning_plan.md")

OLD_STATUS = (
    "状态：**执行中 —— P1 / P2 / P4 已完成，原子批 B1（`tower_zones/battle`）、"
    "B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）、"
    "B3（`environments/base_facility_3d`，443 欠账 / 体量最大）已完成；B4…B9 未开始**。"
)
NEW_STATUS = (
    "状态：**执行中 —— P1 / P2 / P4 已完成，原子批 B1（`tower_zones/battle`）、"
    "B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）、"
    "B3（`environments/base_facility_3d`，443 欠账 / 体量最大）、"
    "B6（`vfx/{combat,environment,visibility}_3d` + `ui/{inventory,pause}_3d` + "
    "`environments/training_range_3d`，14 场景 / 纯改名批）已完成；"
    "B4 / B5 / B7 / B8 未开始，B9 为收尾清理批**。"
)

OLD_B6_ROW = (
    "| **B6** | `vfx/combat_3d` + `vfx/environment_3d` + `vfx/visibility_3d` + "
    "`ui/inventory_3d` + `ui/pause_3d` + `environments/training_range_3d` | 14 | 18 | "
    "`VfxPool3D.gd`(7)、`CombatEffectPool3D`、`Projectile3D`、`Enemy3D`、"
    "`PlayerMeleeCombat3D`、`ui/*`(5) |"
)
NEW_B6_ROW = (
    "| **B6** ✅ **已完成（2026-09-17）** | `vfx/combat_3d` + `vfx/environment_3d` + "
    "`vfx/visibility_3d` + `ui/inventory_3d` + `ui/pause_3d` + "
    "`environments/training_range_3d` | 14 → **纯改名批**：改名 14（13 R100 + 1 R095）/ 删除 0 | "
    "18 → 已清零（另散在 tests / 资产侧场景，同批改） | **唯一版本批**：六套件内无 `.glb`、"
    "无版本目录，故 0 删除。`VfxPool3D.gd`(7)、`CombatEffectPool3D`、`Projectile3D`、"
    "`Enemy3D`、`PlayerMeleeCombat3D`、`ui/*`(5)；顺带修 dust 场景陈旧 UID；"
    "详见下「B6 执行记录」 |"
)

ANCHOR = "### P4 执行记录（2026-09-17，已完成）"

RECORD = """### B6 执行记录（2026-09-17，已完成）

**范围**：`assets/art/vfx/combat_3d` + `vfx/environment_3d` + `vfx/visibility_3d` + `ui/inventory_3d` + `ui/pause_3d` + `environments/training_range_3d`。与 B1–B3 共用 `src/world3d/DungeonRoom3D.gd`，按 §4.1 串行约束紧随 B3 执行。

**形状与 B1–B3 完全不同 —— 本批是「纯改名批」**

- 欠账 14 个，**全部是 `.tscn`，没有一个 `.glb`**；六套件内**无版本目录**、无冗余代次。
- 14 个场景全部是「唯一版本」（仅 `_v001`）→ **0 删除**。
- 目录布局属命名规范 L153 承认的「**非标准三件套布局**」：资产直接放在套件根，不在 `components/` + `runtime/` 下。
- 门禁口径内的运行资产后缀只有 `.glb` / `.tscn`（`RUN_ASSET_SUFFIX`）；`.png`/`.jpg`/`.tres`/`.json` 上的 `_vNNN` **全仓系统性存在 646 个**（B4 rooftop、B5 weapons 各有整代预览图）—— 这是项目**刻意的口径收窄**。故 B6 **不碰 `.png`**（2 个 `*_v001.png` 预览图保留）。若要去掉需先改命名契约，属独立决策。

**改名（步骤②）**：`tools/asset_pipeline/deversion_batch.py` 新增 `b6` 批次定义，`b6 --plan` 通过 `check()`（源存在 / 目标不冲突 / 全部被 git 跟踪），`b6 --apply-renames` 执行。

- 13 个 `R100`（逐字节纯改名）+ 1 个 `R095`（dust 场景，因同时修了 UID）。
- 明细：`vfx/combat_3d` × 8（`vfx_combat_kit` / `damage_number` / `explosion` / `heal_number` / `impact` / `melee_impact` / `melee_slash` / `muzzle_flash`）、`vfx/environment_3d` × 2（`base99_dust_particles` / `hazard_field`）、`vfx/visibility_3d` × 1（`player_flashlight`）、`ui/inventory_3d` × 1（`ui_item_model_icon_root`）、`ui/pause_3d` × 1（`ui_pause_overlay_screen`）、`environments/training_range_3d` × 1（`env_training_range_kit_top3d`）。
- 改名工具报告 **0 处内部 `ext_resource` 改写** —— 符合预期，这些场景的 `ext_resource` 都指向 `src/**/*.gd`，不指向 B6 资产自身。

**顺带修复：陈旧 external UID**

`vfx_base99_dust_particles_root_top3d.tscn` 引用的调色板 uid 为 `uid://c6amwgnoml5yf`，而全仓唯一 `assets/art/vfx/textures/glow_32.png` 的真实 uid 是 `uid://duehsq4qikpex`；旧 uid 仅被此一处引用 → 判为陈旧错 uid。按 bytes 就地改写（CRLF 保真、长度不变）后 Godot 不再回退文本路径。

**引用改写（步骤③④）**：`b6 --fix-code-refs` → **21 文件 / 28 处**，与独立清点的引用面完全吻合。

- `src/**/*.gd` × 12、`tests/verification/*.gd` × 4、`scenes/*.tscn` × 4、`assets/art/environments/base_facility_3d/**/*.tscn` × 1。
- 含串行耦合点 `src/world3d/DungeonRoom3D.gd`。
- 计划文档原列「`.gd` 引用 18」漏了 `src/combat3d/WeaponModel3D.gd:14`（它引用 `vfx_combat_kit_root_top3d_v001.tscn`），实扫时补齐。
- `.py` 侧 4 处带版本引用为**设计内残留**（工具与门禁都刻意排除 `.py` 历史导入脚本）。

**步骤⑤ Godot `--import`**：0 ERROR。**未触发调色板陷阱** —— `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` 的 `detect_3d/compress_to` 仍为 **0**、文件零改动（B6 无 `.glb`，故无 `.import` 重建，无 B2 缺陷 1 的 `.import` 陈旧问题）。

**步骤⑥ 验收**

- `run_verification_suite.sh aggregate core` → `count=68 failed=6`，6 项与 B3 完全同一组、**全部 ⊆ 2026-09-12 审计 §5 基线**：`verify_3d_enemy_behavior_flow`(1)、`verify_3d_melee_feedback_flow`(1)、`verify_base_fixture_glow`(143)、`verify_base_world_flow`(1)、`verify_3d_performance_budget`(1)、`verify_graphics_settings_ui_flow`(1)。**非本批引入。**
- B6 主题覆盖已确认：`verify_vfx_pool_lifecycle`、`verify_3d_melee_combat_flow`、`verify_training_range_3d_flow`、`verify_3d_inventory_weapon_flow`、`verify_weapon_attachment_inventory_flow`、`verify_tactical_inventory_minimap_flow`、`verify_pause_game_save_reset_flow`、`verify_3d_flashlight_charge_flow`、`verify_monster_ai_light_effects` 均在 68 集合内。
- 日志 `Cannot open file` / `Failed loading resource` / `No loader found` = **0**；提及六套件的行只有场景标题，无错误。
- 本批改过的 4 个 verifier 中，`verify_graphics_settings_ui_flow`、`verify_pause_game_save_reset_flow` 在集合内；`verify_base99_dust_vfx`、`verify_base99_updates_v022` 属**既有 6 个「无 `.tscn` 场景」孤儿 verifier**（本批之前即如此，非本批造成），已逐路径核验其 6 个 `res://` 资源全部存在（`load()` 为运行时解析，无编译期风险）。

**步骤⑦ 台账回填 + 缩表**

- 台账 xlsx 经 `_scratch/patch_ledger_b6_deversion.py` 外科式白名单补丁落盘：**3 个成员 / 17 格**（`3D-场景通用!C` 1 + `3D-特效!D` 10 + `资产主表!O` 6）。
- 保真：zip 条目 **29 → 29**（集合不变）；内容变化仅 `sheet2`（资产主表）/ `sheet10`（3D-场景通用）/ `sheet17`（3D-特效）三个目标成员；`sharedStrings.xml` 零改动。
- 路径列（C/D/O）带版本残留 **0**；剩余 7 个带版本 token 全在 `3D-特效!Q`（「已实装；Prefab=… + 脚本=…」实现说明散文列）+ 1 个在 `资产主表!Y145`（变更日志）——**记录列按白名单有意保留，同 B3 对 P/Y 的处置**。
- `check_asset_runtime_naming.py --update-debt` 缩表：文件 **615 → 601**（−14）、目录 13、备份 1、gd 引用 **42 → 24**、tscn 引用 **242 → 236**（−6，= 4 个 scenes + 1 个 B3 资产场景 + 1 处）；门禁 exit 0。

**步骤⑧ 提交**：单独原子提交（详见提交信息）。

**基础设施修正**

- `tools/asset_pipeline/deversion_batch.py`：新增 `b6` 批次定义。
- `scripts/check_asset_runtime_naming.py`：**文档串与实现不一致** —— 实现扫的是整个 `assets/art/**`（仅 `source/` 豁免），原文只写 `components/`、`runtime/`。B6 的「非标准三件套布局」正是暴露此不一致的批，已修正文档串。
- `_scratch/index_refs_scan.py`：由 B3 专用（单一 `B3_ROOT`）**泛化为全部已去版本化批次根**（B1/B2/B3/B6 共 15 个根），逐根给出悬空归属。

**验收门禁**：`check_asset_runtime_naming.py` exit 0；`check_asset_registry.py --scope structure` = **38**（等于基线）；`check_documentation_contracts.py` issues `[]`；`_scratch/index_refs_scan.py` → B6 根悬空 **0**。

**与 B3 的差异要点**：B3 是「改名 + 删除 + 三级目录」的重批（443）；B6 是**纯改名批**（14），无删除、无目录动作、无 `.glb`/`.import` 重建 —— 因此 B2 缺陷 1（`.import` 暂存陈旧）在本批**不会出现**，暂存完整性只需核对 14 R + 23 M + A。

"""


def main() -> int:
    raw = DOC.read_bytes()
    txt = raw.decode("utf-8")
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    print(f"before: bytes={len(raw)} CRLF={crlf} lone_LF={lone_lf}")

    assert txt.count(OLD_STATUS) == 1, "状态行匹配数 != 1"
    txt = txt.replace(OLD_STATUS, NEW_STATUS)

    assert txt.count(OLD_B6_ROW) == 1, "B6 行匹配数 != 1"
    txt = txt.replace(OLD_B6_ROW, NEW_B6_ROW)

    assert txt.count(ANCHOR) == 1, "锚点匹配数 != 1"
    record_lf = RECORD.replace("\n", "\r\n")
    txt = txt.replace(ANCHOR, record_lf + ANCHOR)

    out = txt.encode("utf-8")
    DOC.write_bytes(out)
    print(f"after : bytes={len(out)} CRLF={out.count(b'\\r\\n')} lone_LF={out.count(b'\\n') - out.count(b'\\r\\n')}")
    print(f"lines: {raw.decode('utf-8').count(chr(10))} -> {txt.count(chr(10))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
