# -*- coding: utf-8 -*-
"""把 B3 执行记录写入计划文档，并同步状态行与批次表 B3 行。全程按 bytes 处理以保 CRLF。"""
import io
from pathlib import Path

DOC = Path(r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\development\2026-09-17_godot_asset_deversioning_plan.md")

raw = DOC.read_bytes()
text = raw.decode("utf-8")
assert raw.count(b"\r\n") == raw.count(b"\n"), "文档不是纯 CRLF，先人工确认"
lines = text.split("\r\n")

RECORD = """### B3 执行记录（2026-09-17，已完成）

**范围**：`assets/art/environments/base_facility_3d`（99F 基地，回归面最广）。门禁口径欠账 **443**（152 `.glb` + 139 `.tscn`，各带 sidecar）全部清零；执行后 B3 根内 **0 带版本文件、0 带版本目录**。

**改名 / 删除明细**（暂存区实测：**266 改名 + 180 删除 = 446 条目**，全部落在 B3 根内，越界为 0）

| 类别 | 改名 | 删除 | 备注 |
|---|---|---|---|
| `.glb` | 92 | 60 | 92 个逐字节改名（R100，内容不变）；60 个为被取代的冗余代 |
| `.glb.import` | 92 | 60 | 改名后由 `godot --import` 重新生成（`source_file=` / `dest_files=` 重写） |
| `.tscn` | 82 | 57 | 81 个仅内部 `ext_resource` 改写；1 个逐字节相同 |
| `.json` | 0 | 3 | `env_base99_floor_details` / `floor_full_replacement` 三代的 `*_runtime_manifest_v*.json`，随被取代代退役 |
| **合计** | **266** | **180** | 暂存区 R100 仅 92（即 92 个 `.glb`）；其余 174 为低相似度的内部改写型 rename |

**三级目录布局（B3 特有）**：`components/env_base99_<批次>_v021/<slug>/…` 的**中间批次分组层**一并去版本 —— `env_base99_structural_v021` → `env_base99_structural`、`env_base99_wall_contents_v021` → `env_base99_wall_contents`、`env_base99_remaining_facilities_v021` → `env_base99_remaining_facilities`、`env_base99_floor_visuals_v021` → `env_base99_floor_visuals`；`runtime/` 侧同构。

**两处同名冲突的裁决（执行前已取证）**

1. **`corner_l_5m` 跨代「规范名」冲突**：`*_root_top3d_v005.tscn`（美术壳）与 `*_root_top3d_v004.tscn`（碰撞壳）剥后缀后同名。**v005 保留规范名** → `env_base99_corner_l_5m_root_top3d.tscn`；**v004 改名** → `env_base99_corner_l_5m_collision_top3d.tscn`。落地同时改写 `tools/asset_pipeline/validate_base99_corner_wrapper.gd` 的 `VISUAL_WRAPPER` / `COLLISION_WRAPPER` 两条常量。
2. **`floor_visuals` 四代并存**（v017/v020/v021 两目录 + v021 内两代）：保留最高代 **v004 → `env_base99_floor_visuals/env_base99_floor_visuals_root_top3d.tscn`**，v001/v002/v003 三代删除。`loft_floor_finish` 因父目录不同（`env_base99_floor_visuals/loft_floor_finish/` 与 `env_base99_loft_floor_finish/`）不构成冲突，两代均保留。

**引用改写（`preload` 是编译期解析，必须与本批同批完成）**：**22 个文件 / 45 处路径**

| 位置 | 文件 | 处数 |
|---|---|---|
| `src/world3d/` | `DungeonRoom3D.gd`、`TowerDescent3D.gd`、`TowerFloorStage3D.gd` | 8（与预备调研一致） |
| `tests/verification/` | `verify_base99_*.gd` 10 + `audit_base99_v022_lighting.gd` 1 + 其余 5（`verify_base_facility_interaction_zones` / `verify_base_overhaul_flow` / `verify_common_floor_tile_components_v004` / `verify_rollup_reimport` / `verify_scene_facility_shared_palette`） | 26 |
| `assets/art/` | `environments/tower_zones/base/runtime/zone_base.tscn`(9)、`props/dungeon_3d/qa/probe_door_leaf_reference.gd`(2) | 11 |
| `tools/asset_pipeline/` | `validate_base99_corner_wrapper.gd` | 2 |

基建同批：`tools/asset_pipeline/deversion_batch.py` 新增 `b3` 批定义（+127/−17，含两级/三级两条规则与上述两处冲突策略）；`_scratch/scan_batch_debt.py` 精简（+4/−28）。

**新增护栏（后续每批都应跑）**：`_scratch/b3_staged_closure.py` —— 直接读**暂存索引 blob**（`git ls-files --cached` + `git show :<path>`），把 B3 根内 195 个暂存文本文件的 `res://` 引用逐个解析到规范化路径（含 `..` 解析），断言目标存在于索引。**结果：悬空引用 0**（生成物 `.godot/`、源资产 `source/`、`.blend` 按契约豁免）。同族：`_scratch/b3_ref_keep_check.py`（保留代与存活引用所指代一致：333 处引用 0 冲突）、`_scratch/b3_closure_check.py`（删除闭包内 0 引用指向待删版本）。

**台账（`assets/registry`，外科式 XML 补丁，就地写）**：共 **77 格 = 75 + 2**。
- 只改**运行路径列**：`3D-场景通用` C/D **34** 格、`3D-设施` C/D **14** 格、`资产主表` O 列 **27** 格（含 `corner_l_5m` 冲突解到 `_collision_top3d.tscn`）。
- 收尾 2 格：`资产主表` D65/D66 的「目录（18 个 GLB）」`inlineStr` 形式 —— 去目录层 `_vNNN`、保留全角括号说明。
- **历史列一律不动**：逐格复验定位，剩余 63 个非 `source` 的 B3 带版本单元格**全部**落在他处 —— `3D-设施!P` 6 格、`资产主表!P` 11 格、`资产主表!Y` 46 格；**路径列（C/D/E/O）残留 = 0**。
- 保真：zip 29 条目集合不变，仅 `sheet2` / `sheet10` / `sheet11` 三个成员变化；dimension / mergeCell / dataValidation / row / c 计数不变；写前 `shutil.copy2` 备份 `.bak_b3_deversion` + `.bak_b3_deversion_followup`。
- `assets/art/asset_import_manifest_v001.json` **零改动**（该文件登记的是**源版本事实**，属契约豁免 —— 不去版本）。

⚠️ **一次事故与回滚（重要教训）**：初版台账补丁脚本做了**整文件无差别子串替换**，误改了台账 P/Y 历史列与 `asset_import_manifest_v001.json` 的版本事实列（违反「版本号只允许存在于 `source/` / manifest / 台账 O 列 / Prefab `metadata/asset_version`」契约）。复验残留 token 时发现（台账 17 + manifest 13），**立即按备份逐字节还原（sha 与备份逐字节一致），零损失**；重写为「只改运行路径列」范式后才落盘。→ **结论：台账补丁必须白名单化（sheet + 列 + 期望旧值），禁止全文替换。**

⚠️ **B2 缺陷 1 在本批复现并被兜住**：本批 92 个 `.glb.import` 由 Godot 重建后属**未暂存改动**，而暂存区里它们仍保留 `git mv` 时的旧内容（`source_file=` 指向**已被删除**的 `_vNNN.glb`）—— 与 B2 完全同形。提交前用 `git diff --name-only` 逐项核对并 `git add`，已将 92 个 `.import` 的暂存 blob 对齐为去版本后的 `source_file` / `dest_files`。**`git status` 在本仓仍会漏报（B2 结论继续有效）。**

**欠账快照缩表**：文件 **1058 → 615**（还清 B3 的 443）、目录 13、备份 1、gd 引用 **50 → 42**、tscn 引用 **635 → 242**；`check_asset_runtime_naming.py` exit 0（0 新增违规）。

**验收**

- 专属探针：`probe_safe_room_v007_integration` → `SAFE_ROOM_V007_INTEGRATION_OK`（经 `run_verification_suite.sh scene`，非 headless）；`probe_tower_palette_visible` → `TOWER_PALETTE_VISIBLE_OK`（`--headless --script res://assets/art/props/dungeon_3d/qa/probe_tower_palette_visible.gd`）。
- `run_verification_suite.sh aggregate core` → `count=68 failed=6`，6 项**全部 ⊆ 2026-09-12 审计 §5 基线**（该基线实测 **61 场景 / 12 非零**）：`verify_3d_enemy_behavior_flow`(1)、`verify_3d_melee_feedback_flow`(1)、`verify_base_fixture_glow`(143，断言后无法退出 → 180s 超时)、`verify_base_world_flow`(1)、`verify_3d_performance_budget`(1)、`verify_graphics_settings_ui_flow`(1)。**非本批引入。**
- **4 个基线红项转绿**（本批净收益）：`BASE99_STRUCTURAL_ASSET_INTEGRATION_OK`、`BASE99_WALL_CONTENT_V021_OK`、`BASE99_REMAINING_FACILITIES_V021_OK`、`SCENE_FACILITY_SHARED_PALETTE_OK`（`glbs=104 materials=849 shared_texture=1 lossless_no_mipmap=1 legacy_exempt=2`）。
- 门禁：`check_asset_runtime_naming.py` exit 0；`check_asset_registry.py --scope structure` = **38**（等于基线，无新增）；`check_documentation_contracts.py` issues `[]`；`_scratch/b3_staged_closure.py` 悬空 **0**。

**残留**：B3 根内门禁口径 **0 欠账**；`source/` 侧 3 个 `*.png.import<digits>.tmp` 备份残留按预备约定留 **B9**。台账剩余 63 个历史列 token 为**有意保留**（P=关联文件清单、Y=变更日志，是记录不是路径）。
"""

# 1) 状态行
old_status = "原子批 B1（`tower_zones/battle`）、B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）已完成；B3…B9 未开始**。"
new_status = "原子批 B1（`tower_zones/battle`）、B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）、B3（`environments/base_facility_3d`，443 欠账 / 体量最大）已完成；B4…B9 未开始**。"
hits = [i for i, l in enumerate(lines) if old_status in l]
assert len(hits) == 1, f"状态行匹配 {len(hits)} 处"
lines[hits[0]] = lines[hits[0]].replace(old_status, new_status)

# 2) 批次表 B3 行
old_row = "| **B3** | `environments/base_facility_3d` | **443（体量最大）** | 8 | 99F 基地，回归面最广；与其他批无引用重叠 |"
new_row = ("| **B3** ✅ **已完成（2026-09-17）** | `environments/base_facility_3d` | **443（体量最大）** → 改名 266 / 删除 180 / 改参照 22 文件·45 处 | "
           "8（另 12 处散在 tests/assets/tools，同批改） → 已清零 | 99F 基地，回归面最广。三级批次目录一并去版本；两处同名冲突已裁决；详见下「B3 执行记录」 |")
hits = [i for i, l in enumerate(lines) if l.strip() == old_row.strip()]
assert len(hits) == 1, f"批次表 B3 行匹配 {len(hits)} 处"
lines[hits[0]] = new_row

# 3) 在执行记录插入点前追加 B3 执行记录（插在 B3 预备段落之后、P4 执行记录之前）
anchor = "### P4 执行记录（2026-09-17，已完成）"
hits = [i for i, l in enumerate(lines) if l.strip() == anchor]
assert len(hits) == 1, f"锚点匹配 {len(hits)} 处"
idx = hits[0]
# 回退掉锚点前的空行
insert_at = idx
while insert_at > 0 and lines[insert_at - 1].strip() == "":
    insert_at -= 1
block = RECORD.rstrip("\n").split("\n")
lines[insert_at:insert_at] = block + [""]

out = "\r\n".join(lines)
DOC.write_bytes(out.encode("utf-8"))
print("OK 已写入")
print("新行数:", len(lines))
