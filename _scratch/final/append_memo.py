import io, os

target = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-19.md"

snippet = """

---

## 23:50 女儿墙破损变种（3 件）+ 随机排布接入（Blender→GLB→Prefab→运行时全链路）

主人需求：「墙壁再 blender 里制作 3 个破损变种，不同三种破损，但要能接起来；导入变新预制体后重新随机排列外墙。」
范围锁定：**只做 100F 天台女儿墙直段 5×1.8×0.5m**（外角件不动）。三种破损：崩顶(A)、贯穿(B)、塌脚(C)。比例：**约 1/4 随机**。

### 资产侧（新增 3 件）
| | A 崩顶 | B 贯穿 | C 塌脚 |
|---|---|---|---|
| AssetID | `ENV-ROOFTOP-REF-PARAPET-DMG-A` | `-DMG-B` | `-DMG-C` |
| GLB | `tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_{a,b,c}_top3d.glb` | 同 | 同 |
| prefab | `assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_{a,b,c}_5m.tscn` | | |
| visual 节点 | `女儿墙直段破损{A,B,C}_主体` | | |

- 三件包络与直段**完全一致** 5×1.8×0.5m、原点 `bottom_center`、`forward_axis=+Z`、`layout_role=rooftop_parapet_straight_run`、`runtime_instantiation=batched_multimesh`、`collision_owner=TowerFloorStage3D`、`preserve_authored_palette=true`。
- **「能接起来」= 端带（|x|≥2.05m）必须与直段逐比特一致**：GLB 源层用 `verify_env_rooftop_parapet_damage_bands.py` 逐字节证明端带 POSITION 完全相同；Godot 导入引入 ≤0.07mm 顶点焊接偏移（实测 `end_band_pointcloud_max_nn=0.0000707m`），故探针容差 `BAND_MAX_DEVIATION_M=1.0e-4`。
- 损坏只发生在**中段**，端带 312 顶点/件原样保留 → 任意两件首尾相接都不会露缝。

### 运行时接入（`src/world3d/TowerFloorStage3D.gd`）
- **单 MultiMesh 只能装一个 mesh** → 方案：**1 个完好 MultiMesh（`_outer_visual`）+ 3 个每变体 MultiMesh（`_outer_damage_visual: Array[MultiMeshInstance3D]`）= 共 4 个 MultiMeshInstance3D**。
- 拆分逻辑抽成 `static func split_outer_parapet_damage(transforms, seed_value, enabled) -> Dictionary`（不建 stage 也能单测）；确定性 RNG：`rng.seed = _outer_damage_seed`；判定序：先 `rng.randf() < ROOFTOP_PARAPET_DAMAGE_CHANCE (0.25)` 决定是否破损，再 `rng.randi_range(0,2)` 抽变体。
- 槽位真源：`_outer_straight_slot_transforms: Array[Transform3D]`（`_build_outer_shell` 里落盘）+ 暴露 `get_outer_straight_slot_transforms()` / `get_outer_damage_slot_kinds()`；`get_snapshot()` 增 `outer_damage` 计数。
- **实测（seed=20260919）**：`slots=61 intact=44 dmg_a=6 dmg_b=3 dmg_c=8 damaged=17 ratio=0.2787`，4 条边都有破损。

### 门禁（4 道全绿，均 exit 0 / 0 ERROR）
| 场景 | 结果 |
|---|---|
| `verify_rooftop_32x32_contract` | `ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`（64 段契约保留 + 破损计数自洽 + 3 变体齐） |
| `probe_rooftop_parapet_damage_prefabs` | `PROBE_DMG_DONE seamless_band=true envelope_match=true palette_bound=true contract_ok=true` |
| `probe_rooftop_parapet_damage_layout` | `PROBE_DMG_LAYOUT_DONE scattered=true variants_all_used=true slots_match=true` |
| `probe_rooftop_parapet_alignment` | `PROBE_ALIGN_DONE all_edges_seamless=true corners_seated=true` |

- **反向对照已做**（改坏 3 处断言 → 变红 → 源文件逐字节还原）：证明新断言真会红，不是假绿。
- `probe_rooftop_parapet_alignment` 改为读**槽位真源**而非 MultiMesh → **现在可 headless 跑**（原先「必须带窗口」那条坑对这条新链路已消除）。

### 台账
- `3D-场景通用` 分页新增 3 行（`ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C`），**AssetID 全新 → 新增行**（区别于直段/外角那种「已存在 → 升行」）；`资产主表` 未增删 → 跨度不动。前后对照：+3 资产、无新 issue 种类。

### 坑（本轮新增）
1. **单 MultiMesh 只能一个 mesh** —— 变体排布必须「每变体一个 MultiMeshInstance3D」，别想在一个 MultiMesh 里混 mesh。
2. **GDScript `%` 支持 `%f` 但 `%e` 会炸** → 打印用 `%.9f`。
3. **`%.5f` 做 key 会在 1e-5 边界撞号**（-2.47101 vs -2.47100）→ 端带比对改用「排序点云 + 容差」，别用字符串 key。
4. headless 下 MultiMesh `get_instance_transform()` 读出单位阵（老坑）→ 排布探针读**槽位真源**而非 MultiMesh。
5. `.import` 行尾为 **LF**（与源 import 一致）；`.tscn`/`.gd` 仍 CRLF。

### 环境
- 收尾时命中一次 **429 频率限制**（Godot 连跑被限流），重启后 4 道门禁一次跑通。
- 回归批量 12 道：3 道红（`verify_verification_runner_contract` / `verify_3d_performance_budget` / `verify_base_world_flow`）经 grep 确认**不引用女儿墙/TowerFloorStage3D**，属既有基线，与本次无关。
"""

with io.open(target, "ab") as f:
    f.write(snippet.replace("\n", "\r\n").encode("utf-8"))

print("appended bytes:", os.path.getsize(target))
