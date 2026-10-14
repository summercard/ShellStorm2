# 枪族弹体几何档位（每把枪的子弹大小做出区分）

日期：2026-10-14；记录ID：`2026-10-14_gun_family_bullet_size`；功能ID：`VFX-POOL`（owner `VfxPool3D`，本记录同时挂在 vfx 域与 `WEAPON` 的下发面）；工程版本：`0.1.0`（`project.godot` 未改）。
设计依据与修订：[特效系统与制作规范 §1.2/§3.7/§8/§10](../14.6_特效系统与制作规范.md)（Prefab 是唯一出口、枪族弹体几何档位、特效不得嵌碰撞）、[战斗与局内成长 §6.2](../04_技术施工_战斗与局内成长.md)（子弹模块必填 `visual_id`）；上游制作见 [8 弹种专属弹体纯视觉制作](2026-10-13_bullet_vfx_production.md)。

主人原话：「每把枪的子弹大小要做出区分，散弹枪要从小到大 有个过程动画 榴弹枪要大一点 狙击枪要长，其它可以暂时不变，完成后记录在账本里和设计文档里」。

## 变更与原因

### 为什么是「两层」而不是把尺寸写进 8 个弹种 profile

改动前的链路只认弹种：`Projectile3D._visual_scale_factor()` 返回 `弹种倍率 × 命运倍率`，与枪身无关 ⇒ 同一个穿甲弹装在任何枪上都是同一尺寸。业主要的是**枪**维度的区分，若塞进 `_bullet_profile()` 就会让「弹种 = 唯一视觉源」的正交性破功（同一弹种在不同枪上要返回不同 profile，子类无法表达）。因此新增**第二层**：弹种管「长什么样」，枪族管「多大／多长／有没有生长过程」，两层相乘。

### 档位真源按「族」而非 `gun_id`

`WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG` 的键取枪身 `tags` 里的族标识（`shotgun` / `launcher` / `sniper`）。逐 `gun_id` 硬编码在本仓已有前车之鉴（`_apply_gun_behavior_tags()` 的 `if gun_id == "bp_launcher"`、`_critical_chance` 的 `0.28 if gun_id == "bp_sniper"`），随枪数（已登记 8 把正式枪 + 8 把未来系列）线性腐烂；按族登记后，新增同族枪只要打对 tag 就自动继承。

### 三条档位与取值口径

| 键 | 枪 | scale | axial | grow_from → 1.0 | 观感 |
|---|---|---|---|---|---|
| （中性缺省） | 其余全部枪身 | 1.00 | 1.0 | 1.00（不启用） | 与改动前一致 |
| `shotgun` | 散射喷壶 `bp_shotgun` | 1.00 | 1.0 | 0.42 → 1.0 / 0.30s | 出生 42%，飞行中线性长满 |
| `launcher` | 反胃榴弹筒 `bp_launcher` | 1.55 | 1.0 | 1.00（不启用） | 整体大一圈 |
| `sniper` | 弹弓狙击 `bp_sniper` | 0.95 | 2.0 | 1.00（不启用） | 净长 1.90 倍，细长锐利 |

- **「长」不等于「大」**：`axial` 只沿飞行轴拉伸、不放大横向；狙击档另把横向收到 0.95（净长 = 0.95 × 2.0 = 1.90 倍），避免拉长后显得臃肿。
- **榴弹只放大不拉长**：保持圆钝的重型弹药观感。
- **霰弹基准尺寸不动**：业主本轮口径是「其它可以暂时不变」，霰弹已有一次 5 发散射，只加过程动画、不加整体倍率；如需更小，改 `shotgun.scale` 一格即可。

### 轴向拉伸落「各件局部长轴」，不写父级 scale

弹芯／外壳（capsule，局部 Y 为长轴，节点自身绕 X 转 −90°）与尾迹锥段（局部 Y，转 +90°）各自设 `scale.y = axial`，尾迹段距同步乘 `axial`（基准偏移在 `_build_trail()` 里记入 meta，否则段与段会脱节）。

**为什么不直接写 `_body_root.scale = Vector3(s, s, s·axial)`**：父级非均匀缩放 × 子级旋转 = **剪切变形**，黑洞弹的 `spin` 尾迹旋转会立刻暴露。弹壳 v002.4 踩过同源问题（14.6 §5.5.1 坑 3：缩放只许落子节点且要同步缩放其偏移），此处按同一纪律处理。

### 生长包络必须确定性

`_growth_factor()` 只读累计飞行时间 `_flight_time`，脚本内不出现 `randf()`。与弹壳随机化同一条纪律：**被逐帧断言驱动的视觉对象必须确定**，随机只许活在调用方。

### 复位

`configure()` 每次按 context 重算三项并回落中性缺省；`deactivate()` 显式清零 `_axial_scale / _grow_from / _grow_duration / _flight_time` 并回写几何。池化复借（`ProjectilePool3D`）的下一发不得继承上一发的枪身档位。子投射物（分裂／子母弹）继承母弹档位。

## 落地清单

| 文件 | 变更 |
|---|---|
| `src/vfx/VfxBulletBody3D.gd` | 新增 `_axial_scale / _grow_from / _grow_duration / _flight_time` 四项状态、`_growth_factor()` 与 `_apply_axial_scale()`；`_apply_geometry_scale()` 重写；`configure()` 解析 context；`deactivate()` 复位；`_build_trail()` 三个分支各记 `trail_base_z` meta；`_process()` 推进飞行时间；`get_presentation_snapshot()` 增补 6 个真值键 |
| `src/combat3d/Projectile3D.gd` | 新增 `_gun_bullet_geometry`（`configure` 读取 `config.gun_bullet_geometry`）；`_visual_scale_factor()` 乘入枪身 `scale`；新增 `_bullet_visual_context()`；`activate()` / `_apply_visual_configuration()` 改为下发 context；`_spawn_child_projectile()` 继承档位；`get_orientation_snapshot()` 增补 `visual_base_scale` / `visual_body_scale` / `visual_axial_scale` / `visual_growth_factor` |
| `src/combat3d/WeaponModel3D.gd` | 新增 `BULLET_GEOMETRY_NEUTRAL` 与 `BULLET_GEOMETRY_BY_GUN_TAG` 常量、`bullet_geometry` 字段、`_resolve_bullet_geometry(gun_tags)`；`configure()` / `configure_from_tree()` 解析并存入；清空路径复位；三处开火 config（主枪／散射循环／副枪）下发 `gun_bullet_geometry` |
| `tests/verification/verify_bullet_vfx_profiles.gd` | 新增 `EXPECTED_GUN_GEOMETRY` 常量、`_fire_once(gun_id)` 辅助、`_check_gun_size_differentiation()`、`_check_shotgun_growth_envelope()`；哨兵下限 `30 → 55` |
| `docs/v0.1/14.6_特效系统与制作规范.md` | 新增 §3.7；§10 追加 v003.4 |
| 特效账本 `ShellStorm2_特效账本_v001.xlsx` | 《资产主表》r26–r34 与《3D-特效》FX01-06／FX01-08..15 备注追加尺寸契约；《域变更日志》追加 `v0.1.19` |

## 验收

`verify_bullet_vfx_profiles`（headless，`exit 0`）：

```
BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / gun-size-differentiation / growth-envelope / wiring pass (samples=59)
```

新增用例覆盖：

1. **9 把枪逐把核对**（经真实调用方路径：`WeaponModel3D` + `BlueprintRegistry.build_weapon_tree` + `_fire_now`），逐把断言 `scale` / `axial` / `grow_from` 三项；
2. **三条诉求的相对方向判据**：榴弹 >1.30 倍手枪基准、霰弹基准不变（≈1.00）、狙击横向更细；
3. **轴向的几何真值**：弹芯局部长轴实测 `2.0`，且 `body_scale`（横向）不受影响 —— 防止「只写了个字段、没真拉伸」；
4. **生长包络四时刻步进**：出生 `0.42` → 半程 `≈0.71` → `0.30s` 长满 `1.0` → 再推进 `0.50s` 仍 `1.0`（封顶）；
5. **中性档不启用** + **复借复位**（轴向／生长起点／飞行计时三项清零）。

同时回归：`verify_combat_vfx_toon_v002`（samples=16）、`verify_3d_fate_weapon_flow`、`verify_starting_weapon_contract`、`verify_weapon_instance_contract_matrix`、`verify_player3d_weapon_switch`、`verify_3d_combat_progression_flow` 全部 `exit 0` 且判据行全绿。

### 反向对照（三组，均精准变红后还原复绿）

| # | 施加的退化 | 结果 |
|---|---|---|
| RC1 | `shotgun.grow_from: 0.42 → 1.00` | `BULLET_VFX_PROFILES_FAIL`，`枪身 bp_shotgun：出生生长系数应为 0.42，实测 1.0` |
| RC2 | `sniper.axial: 2.0 → 1.0` | `BULLET_VFX_PROFILES_FAIL`，`枪身 bp_sniper：轴向拉伸应为 2.0，实测 1.0` |
| RC3 | `launcher.scale: 1.55 → 1.00` | `BULLET_VFX_PROFILES_FAIL`，`枪身 bp_launcher：弹体尺寸倍率应为 1.55，实测 1.0` |

还原后文件 `md5` 与改动前一致（`fb22fa74…`），`grep -rn "REVERSE-CONTROL" src/` 为空。

## 账本与门禁

- 域变更日志 `v0.1.19`；《资产主表》r26–r34 与《3D-特效》9 行备注追加同一段契约说明（幂等：按标记串判重，重跑 `changed: []`）。
- 账本改前备份 `_scratch/ledger_backup_20261014/`；改后回读校验标记 9/9 + 9/9，DataValidation 3 组保留。
- `python scripts/check_asset_registry.py --ledger vfx`：`asset_count = 32`（不变）；`issues = {sha_mismatch: 14}`。
  ⚠️ **这 14 条漂移是本事务之前既存的**（r17–r21 与 r26–r34），不是本次引入：本事务未改任何 `.tscn`／`.gd` 登记路径。已用「未改账本 vs 改后账本」对照跑门禁，**两者同为 14 条**。来源指向 2026-10-14 00:55 的一次批量重存（`assets/art/vfx/combat_3d/vfx_bullet_*.tscn` mtime 一致）。**未在本事务接受这批新哈希** —— 按 AGENTS.md「哈希漂移先核对变更来源，不批量接受当前文件掩盖差异」，留待确认来源后单独收口。

## 追加轮次（同日 22:00）：霰弹枪弹体 ×2 + 一处契约修正

主人原话：「散射喷壶 的子弹太小了， 出生和结束都增加2倍 然后现在的子弹的模型面数多少？」

### 改动

| 项 | 前 | 后 |
|---|---|---|
| `BULLET_GEOMETRY_BY_GUN_TAG.shotgun.scale` | `1.00` | `2.00` |
| `grow_from` / `grow_duration` | `0.42` / `0.30` | 不变（`grow_from` 是**比例**） |
| 霰弹枪弹体出生尺寸 | `0.42` | `0.84` |
| 霰弹枪弹体长满尺寸 | `1.00` | `2.00` |

`grow_from` 保持 `0.42` 就等于两端同步翻倍 —— 「出生和结束都增加 2 倍」不需要改两个数，改 `scale` 一个就够（这也是把它定义成**比例**而非绝对值的收益）。

### ⚠️ 同一轮修正：v003.4 的「纯视觉」声明在实现上没兑现

v003.4 的账本备注与 §3.7 都写了「本档位不改碰撞半径」，但 `Projectile3D` 里倍率只有一个出口：

```gdscript
func _visual_scale_factor() -> float:
	var scale_factor := 1.55 if bullet_tags.has("balloon") else 1.0
	scale_factor *= clampf(float(fate_behavior.get("fate_scale", 1.0)), 0.35, 4.0)
	scale_factor *= float(_gun_bullet_geometry.get("scale", 1.0))   # ← 新增的枪身维度
	return scale_factor
```

而 `_apply_visual_configuration()` 又用它算碰撞球半径：

```gdscript
(_collision_shape.shape as SphereShape3D).radius = 0.12 * scale_factor
```

⇒ 枪身族倍率**会**进入碰撞判定。v003.4 的 `launcher` `1.55` / `sniper` `0.95` 幅度小，没暴露；本轮霰弹 `×2` 会把判定半径从 `0.12` 抬到 `0.24`（判定面膨胀 4 倍），对一个 18 发/s 级的散射武器是实打实的强度提升。

**修法**：拆成两个出口，此后不得合并。

| 出口 | 组成 | 用途 |
|---|---|---|
| `_visual_scale_factor()` | 弹种 × 命运 × 枪身族 | 传给 `VfxBulletBody3D.configure(size)` |
| `_collision_scale_factor()` | 弹种 × 命运（无枪身族） | 碰撞球半径 = `0.12 ×` 它 |

保留弹种倍率（气球弹 `1.55`）进碰撞是因为那是**既有**口径，动它等于动既有平衡；枪身族是新增维度，不进碰撞。

### 弹体模型面数（回答主人第二问）

探针 `_scratch/probe_bullet_mesh_stats`（一次性，无 `class_name`）：

| 弹种 | 三角面 | 绘制件数 | 本地尺寸（长 × 径，m） | ×2 后 |
|---|---|---|---|---|
| balloon | 468 | 3 | 0.518 × 0.230 | 1.036 × 0.460 |
| standard | **732** | 3 | 0.560 × 0.150 | 1.120 × 0.300 |
| blackhole | 732 | 5 | 0.758 × 0.192 | 1.516 × 0.384 |
| explosive | 768 | 6 | 0.700 × 0.188 | 1.400 × 0.376 |
| shared（通用弹体） | 792 | 3 | 0.600 × 0.150 | 1.200 × 0.300 |
| piercing | 864 | 4 | 1.140 × 0.088 | 2.280 × 0.176 |
| bounce | 996 | 5 | 0.690 × 0.130 | 1.380 × 0.260 |
| homing | 996 | 5 | 0.660 × 0.160 | 1.320 × 0.320 |
| sticky | 1020 | 6 | 0.771 × 0.160 | 1.542 × 0.320 |

- 八弹种均值 **819 面 / 4.44 件**，极值 468~1020。
- **缩放不改变面数** —— 霰弹 ×2 只是屏幕占比放大，GPU 几何量不变。
- **霰弹枪一次 5 发**（`bp_shotgun.projectile_count`）⇒ 标准弹下 `732 × 5 = 3660` 面 / `15` 次绘制，是弹体视觉里最重的单次开销。
- 面数与「绘制件数」的构成：每弹种固定 2 件（弹芯 + 外壳）+ 尾迹件数（1~4）。尾迹件数是面数差异的主因（`sticky` 的 3 滴珠 = `SphereMesh(radial 8, rings 5)`，是单件最省的面）。

### 验收（追加轮次）

```
BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / gun-size-differentiation / growth-envelope / wiring pass (samples=60)
EXIT=0
```

回归 7 项全绿：`verify_combat_vfx_toon_v002`(16) / `verify_3d_fate_weapon_flow` / `verify_weapon_instance_contract_matrix` / `verify_starting_weapon_contract` / `verify_player3d_weapon_switch`(96) / `verify_vfx_pool_validation`… 见 `_scratch/reg2_*.log`。

**反向对照两组（追加）**：

| # | 施加的退化 | 结果 |
|---|---|---|
| RC4 | `shotgun.scale: 2.0 → 1.0` | `ERROR: 霰弹枪弹体应为手枪基准的 2 倍（应 ≈2.00，实测 1.0）` |
| RC5 | `_collision_scale_factor()` 改为返回 `_visual_scale_factor()` | `ERROR: 枪族档位不得改碰撞半径（应恒为基准球 0.12，实测 0.23999999463558）` |

RC5 的残留量 `0.24 = 0.12 × 2.0` 与施加的倍率精确吻合 ⇒ 断言真在测量。

### ⚠️ 账本并发写冲突（需主人知悉）

本轮写账本时发现《域变更日志》编号被另一会话抢占：

- 本事务写入 `v0.1.20`（霰弹 ×2 + 契约修正）后，另一并发会话于同一轮往账本新增 `VFX-ZOMBIE-GOO-DEATH-3D`（主表 r38），并把它自己的日志行写在同一个行号 26 上 ⇒ **覆盖了本事务的 `v0.1.20` 行**。
- 所幸**备注改动未受影响**（《资产主表》r26–r34 与《3D-特效》9 行的尺寸档描述回读仍为 `9/9`、含 `×2.00`），对方的 r38 新行与本事务备注并存。
- 处置：以 `v0.1.21` 补录本事务内容（附注说明），并在行尾标注该冲突。快照留 `_scratch/ledger_backup_20261014/conflict_snapshot.xlsx`。
- 门禁：`asset_count = 33`（对方新增 1 行）、`issues = {sha_mismatch: 16}`（14 条既存 + 对方新增的 r36 / r38）。
- **教训**：《域变更日志》的「按末行 +1」写法和幂等判据（只看版本号是否已存在）在并发下会静默丢行。多会话并行时，日志行应改为「按内容判重 + 冲突即报错」，或约定独立的版本号段。

## 追加轮次（同日 23:05）：弹体减面到 100 面以内

主人原话：「减面，减到100个面以下先」

### 先实测，再定档（不估算）

用探针 `_scratch/probe_mesh_lod_sweep` 扫出分段 → 面数对应表：

| 图元 | 配置 | 三角面 |
|---|---|---|
| `CapsuleMesh` | rs=4, rings=0 | 24 |
| `CapsuleMesh` | rs=4, rings=1 | 48 |
| `CylinderMesh` | rs=4, rings=0 | **16** |
| `CylinderMesh`（锥） | rs=4, rings=0 | **12** |
| `SphereMesh` | rs=4, rings=1 | 16 |
| `BoxMesh` | — | **12** |

**关键发现**：`CapsuleMesh` 的**圆头来自 `rings`**，`rings=0` 的「胶囊」= 平盖圆柱 + 2 片盖扇 = 24 面，比同轮廓的 `CylinderMesh`（16 面）贵 8 面。而 `rings=1` 要 48 面/件 —— 弹芯 + 外壳两件就 96 面，把预算吃光。**100 面预算下买不起圆头**。

⇒ 决策：弹芯与外壳改用 **4 边棱柱**（`CylinderMesh` rs=4 rings=0）。轮廓与 `rings=0` 的胶囊**完全一致**，只是更省。

### 改了什么

| 件 | 前 | 后 | 面数 |
|---|---|---|---|
| 弹芯 / 外壳 | `CapsuleMesh` rs=10~12, rings=4 | `CylinderMesh` 4 段棱柱 | 16 |
| 尾迹锥 | `CylinderMesh` rs=12 | `CylinderMesh` rs=4 | 12 |
| 滴珠 | `SphereMesh` rs=8 rings=5 | `BoxMesh` | 16 → 12 |
| 球核（黑洞/气球） | `SphereMesh` rs=12 rings=6 | `SphereMesh` rs=4 rings=1 | 16 |

**滴珠为什么可以变方块**：世界尺寸只有 0.011~0.018m（1~2 厘米），球与立方体在实机上不可分辨；省下的 4 面用来保住尾迹锥的规格。

**件数与尾迹构图一律没动** —— 面数只从「每件多少面」里省，不从「有几件」里省。件数是账本《3D-特效》与验收 `EXPECTED_TRAIL_PARTS` 的双边契约，动它会连带改两处文档。

### 结果

| 弹种 | 改前 | 改后 | 降幅 |
|---|---|---|---|
| standard / balloon / shared | 732~792 | **44** | −94% |
| piercing | 864 | **56** | −94% |
| bounce / homing / blackhole | 732~996 | **68** | −93% |
| sticky / explosive | 768~1020 | **80** | −92% |

八弹种均值 `819 → 61.3`，极值 **44~80，全部 < 100**。霰弹枪一次 5 发：`3660 → 220` 面（−94%）。

### 验收

```
BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / gun-size-differentiation / growth-envelope / face-budget / wiring pass (samples=69)
EXIT=0
```

新增 `_check_face_budget()`：**两层判据** —— ① 绝对上限 `100`（业主需求本身）；② 逐弹种实测值硬编码表（钉住分段参数，防回涨）。期望值**硬编码在验收侧**、不引用被测常量（skill §6.9 纪律）。

回归 9 项全 `exit 0`（含 `verify_combat_vfx_toon_v002` / `verify_death_blast_vfx` / `verify_monster_startup_roar` / `verify_vfx_pool_lifecycle`）。

**反向对照三组（本轮新增）**：

| # | 施加的退化 | 结果 |
|---|---|---|
| RC6 | `MESH_SEGMENTS: 4 → 12` | `面数预算 standard：实测 132 面，超出上限 100` + 逐条精确值失配 |
| RC7 | `SPHERE_RINGS: 1 → 6` | `面数预算 blackhole：实测 148 面，超出上限 100` |
| RC8 | 通用弹体 `_SEGMENTS: 4 → 12` | `面数预算 shared：实测 132 面，超出上限 100` |

还原后两个文件 `md5` 与改前一致。

### 视觉代价（如实记录）

4 边棱柱在世界里读作**方形长条**，不是圆柱；弹体端面是**平的**（圆头已被预算排除）。子弹在屏幕上停留时间很短、体积又小，所以这是可接受的近似 —— 但如果实机看着太"棱"，往上调一档的代价是明确的：

| 目标观感 | 弹芯/外壳分段 | 面数（单锥弹 / 三锥弹） | 是否守 <100 |
|---|---|---|---|
| 现状（方形长条） | rs=4 | 44 / 68 | ✅ |
| 略圆 | rs=6 | 44+24 / 68+24 | ✅（92 上限） |
| 明显圆 | rs=8 | 44+40 / 68+40 = 108 | ❌ 三锥弹破线 |

⇒ **升到 rs=5 或 6 仍可守住 100 面**（需同步改 `EXPECTED_TRIS` 表）。圆头（`rings≥1`）无论怎么调都超预算，属于"必须放松上限"才谈得上的选项。

## 遗留与未做

- 只落地业主要求的三把枪（霰弹／榴弹／狙击）；其余枪持平中性档。未来系列的霰弹/狙击/榴弹枪只要打对 tag 即自动继承。
- 榴弹与狙击**未加**过程动画（业主只对霰弹提出了「有个过程动画」）。若要扩展，只需在对应档位补 `grow_from` / `grow_duration`。
- 弹壳（`VFX-SHELL-CASING-3D`）、枪口花火（`FX01-01`）等其它战斗表现本轮未动；它们已有独立的尺寸契约。
- 门禁的既存 `sha_mismatch` 待确认来源（见上）；另有若干条来自并发会话的本次写入（r36 / r38 / r39 / r40）。
- 霰弹枪弹体现居八档之最（`2.00` > 榴弹 `1.55`）。若主人希望恢复「榴弹最大」的次序，需回调 `shotgun.scale` 或把 `launcher.scale` 提到 `> 2.00` —— 本轮未擅自调整，因为主人只说霰弹要 ×2。
