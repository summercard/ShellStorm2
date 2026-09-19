import os

target = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"

snippet = """
### 破损变种 3 件 + 随机排布（2026-09-19 追加，直段专属）
需求：给直段做 3 种破损变种（崩顶 A / 贯穿 B / 塌脚 C），要能首尾相接，导入后随机排布外墙（约 1/4）。**只动直段，外角件不动。**

| | A 崩顶 | B 贯穿 | C 塌脚 |
|---|---|---|---|
| AssetID | `ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C` | | |
| prefab | `assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_{a,b,c}_5m.tscn` | | |
| GLB | `tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{a,b,c}_top3d.glb` | | |
| visual 节点 | `女儿墙直段破损{A,B,C}_主体` | | |

- 包络与直段**完全相同** 5×1.8×0.5m，`origin_contract=bottom_center`、`forward_axis=+Z`、`runtime_instantiation=batched_multimesh`、`collision_owner=TowerFloorStage3D`。
- **「能接起来」的判据 = 端带（`|x|>=2.05m`）与直段逐比特一致**：源层 `tower_zones/rooftop/source/verify_env_rooftop_parapet_damage_bands.py` 直接比 GLB POSITION 字节；Godot 导入会引入 ≤0.07mm 顶点焊接偏移 → 运行时探针容差 `BAND_MAX_DEVIATION_M=1.0e-4`。损坏只做中段，端带 312 顶点原样保留。
- ⚠️ **单 MultiMesh 只能装一个 mesh** → 变体排布必须「1 完好 MultiMesh + 每变体 1 个 MultiMesh」= 4 个 `MultiMeshInstance3D`（`_outer_visual` + `_outer_damage_visual: Array[MultiMeshInstance3D]`）。
- 拆分逻辑抽成 `TowerFloorStage3D.split_outer_parapet_damage(transforms, seed_value, enabled) -> Dictionary`（static，可在不建 stage 的情况下单测）；`rng.seed=_outer_damage_seed`，判定序「先 `randf()<0.25` 再 `randi_range(0,2)`」。
- 槽位真源 `_outer_straight_slot_transforms`（+`get_outer_straight_slot_transforms()` / `get_outer_damage_slot_kinds()`）——**排布探针读它，不读 MultiMesh**，于是 `probe_rooftop_parapet_alignment` 已能 headless 跑（旧「必须带窗口」坑对新链路消除）。
- 实测 seed=20260919：`slots=61 intact=44 dmg_a=6 dmg_b=3 dmg_c=8 damaged=17 ratio=0.2787`，四边均有破损。
- 门禁：`verify_rooftop_32x32_contract`（+3 变体齐/计数自洽）、`probe_rooftop_parapet_damage_prefabs`、`probe_rooftop_parapet_damage_layout`、`probe_rooftop_parapet_alignment` 四道全绿；已做反向对照证明断言真会红（不是假绿）。
- 台账：AssetID **全新** → `3D-场景通用` **新增 3 行**（不是升行）；资产主表不动、不需 `rescope_asset_sheet()`。
- 坑：GDScript `%` 无 `%e`（用 `%.9f`）；`%.5f` 做 key 会在 1e-5 边界撞号（改用排序点云 + 容差）；新 `.import` 行尾 **LF**（与源 import 一致），`.tscn`/`.gd` 仍 CRLF。
"""

with open(target, "rb") as f:
    old = f.read()
new = old + snippet.replace("\n", "\r\n").encode("utf-8")
with open(target, "wb") as f:
    f.write(new)
print("old", len(old), "new", len(new))
