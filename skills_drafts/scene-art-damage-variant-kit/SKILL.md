---
name: scene-art-damage-variant-kit
description: 把已有模块化构件（女儿墙直段、墙、地板等按网格重复摆放的件）派生 N 个「破损变种」，做成新 GLB + 新 prefab，再在运行时按确定性随机把一部分实例换成变种。核心两点：把「接缝端带」锁成与原件逐比特一致；用「每变体一个 MultiMesh」绕开单 MultiMesh 只能装一个 mesh 的限制。用于破损 / 风化 / 残破变种、随机排布外墙、模块接口保真；不用于新建资产、不用于角色 / 武器 / 道具、不用于非模块化单体。
agent_created: true
---

# 模块化构件破损变种（派生 + 随机排布）

## 适用边界

- **适用**：一个已经按网格重复摆放的模块化构件（直段墙、女儿墙、地砖、栏杆段……），主人要「做几个不同破损的变种，要能接起来，然后随机排布」。
- **不适用**：从零新建/重制资产本身（→ `blender-game-prop-standard` / `godot-model-asset-import-standard`）；角色 / 武器 / 可拾取道具（→ 对应 pipeline skill）；双面装饰（→ `scene-art-double-sided-component`）；装饰并库（→ `scene-art-merge-into-shared-component`）。
- **先锁三件事再动手**（本先例主人逐条给过答案，缺一条就会返工）：
  1. **范围**：只做哪一件、包络多少（本先例「只做 100F 天台女儿墙直段 5×1.8×0.5m，外角件不动」）；
  2. **几种破损 / 各是什么**（本先例「崩顶 / 贯穿 / 塌脚」3 种）；
  3. **比例**（本先例「约 1/4 随机」）。
  > 主人只给了「3 个变种 + 能接起来 + 随机排列」，第 2、3 点是用一次 `AskUserQuestion` 问清的 —— 这类**范围/比例**决策必须问，不要替他拍板。

## 第 0 步：把「能接起来」翻译成可验证的红线

「接起来不露缝」在数学上就是：**两件首尾相接处的端带必须逐比特相同**。

- 定一个**端带判据**：本先例是 `|x| >= 2.05m`（段长 5m，两端各留 0.45m 以上做接口区）。**破损只允许发生在中段，端带一个顶点都不许动。**
- 端带顶点数先量出来当基线（本先例每件 **312 个**），variant 与原件必须一样多。
- 原点和朝向口径沿用原件（本先例 `origin_contract=bottom_center`、`forward_axis=+Z`）——变种是**同接口的兄弟件**，不是新角色。

## 第 1 步：Blender 派生 —— 用「同接口、异中段」的布尔雕蚀

- 沿用原件的导出脚本，派生一个 `author_*_damage_v001.py`；对每个变体**只在中段**用不同形态的雕蚀（本先例：崩顶 / 贯穿 / 塌脚）。
- 或直接从既有源复制 + 局部编辑，但**必须重新跑一遍导出脚本**产出 GLB，别手改 GLB。
- 导出后**立刻做源层端带校验**（见第 2 步），不要等进了 Godot 才发现端带被动过。

## 第 2 步：端带在「源层」做逐字节证明

写一个独立只读脚本（本先例 `assets/art/environments/tower_zones/rooftop/source/verify_env_rooftop_parapet_damage_bands.py`）：

- 直接解析 GLB 的 chunk，取 POSITION accessor，把 `|x| >= 2.04`（比运行时阈值略松一点，避免边界漏点）的顶点按 (x,y,z) 排序后**逐字节比对**变种 vs 原件。
- 同时断言包络等于原件（本先例 `((-2.5,-0.25,0.0),(2.5,0.25,1.8))`）。
- 判据 `DAMAGE_BANDS_OK` —— 源层过了，才有资格进 Godot。
- > 源层**逐字节相同**是本红线能成立的前提。别跳过这步直接在 Godot 里比 —— 见下一个坑，Godot 导入会引入微小偏移。

## 第 3 步：Godot prefab + `.import`

每个变体一套（本先例 3 套）：

| 文件 | 做法 |
|---|---|
| `assets/art/props/**/prp_<件>_dmg_{a,b,c}_5m.tscn` | 照抄原件 tscn，改成新 `metadata/asset_id`、新 `visual_node_name`、新 ExtResource 路径；**`[gd_scene load_steps=N format=3]` 头一行不能漏**（漏了报解析错），`layout_role` / `runtime_instantiation=batched_multimesh` / `collision_owner` / `preserve_authored_palette` 全沿用 |
| `<glb>.import` | 复制原件的 import 文件，改 `uid://`（用合法字母表 `bcdfghjklmnpqrstvwxz2456789` 生成 13 字符）+ `md5`。⚠️ **必须保留 `import_script/path=res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`**，否则白板且不触发门禁 |

- **行尾**：`.tscn` / `.gd` 用 **CRLF**；`.import` 用 **LF**（跟源 import 一致）。用 Python 落盘保证，别靠工具默认。
- 写完跑 `--headless --path . --import`，退出码 0 即可。

## 第 4 步：运行时随机排布 —— 「1 完好 + 每变体 1」个 MultiMesh

**核心限制：一个 MultiMeshInstance3D 只能装一个 mesh。** 所以别想在一个 MultiMesh 里混完好件和变种。方案：

1. **完好件 1 个 MultiMesh**（沿用原 `_outer_visual`）；
2. **每个变体 1 个 MultiMesh**（`var _outer_damage_visual: Array[MultiMeshInstance3D]`），空变体不建节点。
3. **把拆分逻辑抽成 `static` 函数**（本先例 `TowerFloorStage3D.split_outer_parapet_damage(transforms, seed_value, enabled) -> Dictionary`），返回 `{"intact": [...], "variants": [[],[],[]], "counts": {...}}` —— 这样**不建 stage 也能单测**。
4. **确定性 RNG**：`rng.seed = <固定 seed>`（本先例 `_outer_damage_seed`）。判定序固定：**先** `randf() < CHANCE` 决定是否破损，**再** `randi_range(0, n-1)` 抽变体。顺序写反会让分布不可复现。
5. **暴露「槽位真源」**：把每个槽位的 `Transform3D` 记进 `_outer_straight_slot_transforms`，并提供 `get_outer_straight_slot_transforms()` / `get_outer_damage_slot_kinds(): Array[String]` 与 `get_snapshot()` 里的计数。**这是给探针用的**（见下）。
6. 比例常量命名清楚（本先例 `ROOFTOP_PARAPET_DAMAGE_CHANCE = 0.25`）。

本先例实测（seed=20260919）：`slots=64 intact=46 dmg_a=7 dmg_b=3 dmg_c=8 damaged=18 ratio=0.2813`。
（注：**同一 seed 下槽位一变、分布就整体重排** —— 早期西侧围栏缺口未封时是 `slots=61 intact=44 damaged=17 ratio=0.2787`。所以**别把某一次的实测数字写成断言**。）

## 第 5 步：探针与门禁 —— 三个必须做对的地方

1. **端带比对要在 Godot 侧复验，但要容差**：Godot 导入会做顶点焊接，端带点位相对源层有 **≤0.07mm** 偏移（本先例实测 `end_band_pointcloud_max_nn = 0.0000707 m`）。所以：
   - 判据用 `BAND_MAX_DEVIATION_M = 1.0e-4`（远小于 0.45m 的接口区，又大于焊接偏移）；
   - 比对方法用**排序点云 + 最近邻最大偏差**，**不要用 `%.5f` 字符串 key** —— 1e-5 边界会让 key 撞号（本先例 `-2.47101` vs `-2.47100`）造成假红。
2. **排布探针读「槽位真源」，不读 MultiMesh**：headless 下 `MultiMesh.get_instance_transform()` 一律回读成单位阵（老坑）→ 排布探针必须读 `get_outer_damage_slot_kinds()` 这类由 stage 落盘的真值。**顺带好处**：原来「alignment 探针必须带窗口跑」的坑对新链路消除，改读槽位真源后可 headless。
3. **必做反向对照**：把新断言逐条改坏 → 必须变红 → 再逐字节还原源文件。证明不是假绿。
4. ⚠️ **期望值必须由几何/常量推出，禁止硬编码数字**：排布探针里「槽位总数 = ?」一度写死（`SLOT_COUNT_EXPECTED := 61`）。本先例后来封闭西侧围栏缺口 → 直段 61→64，探针**误红**（`failures=1`，而实际排布完全正常）。正确做法：由 `rect` + 转角臂 + 模块长算出期望（本先例 = `2×((90-5)/5) + 2×((80-5)/5)` = 64），再**与 stage 快照对账**（`outer_straight_slot_count`、`outer_doorway_wall_count`），三者一致才算过。任何「件数 / 槽位 / 段数」类断言都适用这条纪律。

本先例四道门禁全绿：`verify_*_contract`（契约保留 + 计数自洽 + 变体齐）、`probe_*_damage_prefabs`（seamless_band / envelope_match / palette_bound）、`probe_*_damage_layout`（scattered / variants_all_used / slots_match）、`probe_*_alignment`。

## 第 6 步：台账

- **变种是新 AssetID**（本先例 `ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C`）⇒ **新增行**，不是升既有行。
  （对照：若是给**已有** AssetID 升版才是「升级既有行」——两种口径别搞混，用错会 `duplicate_asset_id`。）
- 登记到与原件相同的分页（本先例 `3D-场景通用`）。⚠️ `check_asset_registry` **只查《资产主表》，不查 `3D-*` 分页** → 分页新增不产生 issue，别把「没报」当「没登记」。
- 前后对照要报：**资产数增量**、**有无新 issue 种类**。

## 坑清单（都真踩过）

1. **单 MultiMesh 只能一个 mesh** —— 变体排布 = 「完好 1 + 每变体 1」个 MultiMeshInstance3D。
2. **GDScript `%` 无 `%e`** —— `"%.3e" % x` 直接报错，打印用 `%.9f`。
3. **`%.5f` 做 key 会在 1e-5 边界撞号** —— 端带比对改「排序点云 + 容差」。
4. **headless 下 MultiMesh 实例变换读回单位阵** —— 排布/对齐探针读槽位真源。
5. **新 `.import` 必须手工绑共享色盘 import_script**，否则白板且不触发门禁。
6. **`.import` 是 LF**，`.tscn` / `.gd` 是 CRLF —— 混了会让行尾纯度检查炸。
7. 生成的 `.tscn` 别漏 `[gd_scene ...]` 头。

## 收尾清单

- [ ] 第 0 步三件事（范围 / 几种 / 比例）已和主人对齐
- [ ] 端带判据与基线顶点数已定，破损只在中段
- [ ] 源层端带逐字节证明 `DAMAGE_BANDS_OK`
- [ ] 每个变体一套 tscn + import（新 AssetID / 绑色盘 / 行尾对）
- [ ] `--headless --import` 退出码 0
- [ ] `static` 拆分函数 + 确定性 seed + 槽位真源出口
- [ ] 「1 + 每变体 1」个 MultiMesh 节点
- [ ] 端带 Godot 侧复验（容差 1e-4 / 排序点云）+ 排布探针读槽位真源
- [ ] 反向对照（改坏 → 变红 → 还原）
- [ ] 契约门禁含「变体齐 + 计数自洽」
- [ ] 台账新增行 + 前后对照
- [ ] 记忆：硬约定进 `MEMORY.md`、细则进 `MEMORY-playbooks.md`、逐日进 `YYYY-MM-DD.md`
- [ ] `skill-mirror-sync` 同步四副本
