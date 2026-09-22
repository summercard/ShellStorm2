---
name: vfx-combat-effect-authoring
description: 制作、重做、修复或验收 ShellStorm2 的 3D 战斗特效（VFX）——枪口花火、命中爆点、飞行子弹视觉、近战挥砍弧光、弹壳抛出与落地、受击/治疗飘字、爆炸。用于「做特效 / 重做特效 / 特效不好看 / 要卡通风 / 枪口火光 / 命中爆点 / 子弹要带灯光 / 特效残留 / 特效不跟着枪口走 / 特效留在原地 / 特效没进池 / AssetID 路由 / VfxPool3D / VfxEffectBase3D / 弹壳 / 抛壳 / 弹壳不落地 / 弹壳穿地 / 弹壳太整齐 / 弹壳随机 / 抛壳随机 / 弹壳停留时长 / 弹壳消失太快 / 特效 PBR 材质 / 特效验收 / 特效账本登记 / 14.6」这类问题。不用于场景美术模块、角色/敌人/武器建模与 Blender 导出链路（那些走各自的模型管线 skill）。
agent_created: true
---

# 战斗 3D 特效（VFX）制作与验收

## 0. 五分钟上手

真源三处：规范 `docs/v0.1/14.6_特效系统与制作规范.md`、注册表 `src/vfx/VfxPool3D.gd` 的 `_REGISTRY`、账本「3D-特效」分页。

动特效**之前**必读：14.6 §1-§5，以及 `docs/v0.1/development/2026-09-12_discrepancy_table.md` 的 **E08**（双池迁移未完成 = 已知项，别当新 bug 报）。

## 1. 铁律

1. **Prefab 是特效的唯一出口**（14.6 §1.2）：运行时不得用代码拼几何、不得 `match effect_kind` 分支出表现。一个特效 = 一个独立 `.tscn` + 一个脚本。
2. **AssetID 路由，禁裸字符串**：调用方写 `VfxPool3D.FX01_MUZZLE_FLASH`，不写 `"muzzle"`。裸字符串绕过编译期校验。
3. **特效 Prefab 内禁碰撞体**（纯视觉），验收有断言盯着。
4. **谁借谁还，回收必须灭灯**：灯能量归零 + 不可见，否则池化复借会留长明灯。
5. **会动的表现必须绑 `context.follow`**，且跟随目标选「真正跟着角色动的那个节点」（见 §5）。
6. **验收分两层**：机制层（基类能力）+ 端到端接线层（调用方真的传了）。**两层都要反向对照**。

## 2. 战斗表现的真源表（2026-09-21 实测）

| 表现 | AssetID | Prefab（`assets/art/vfx/combat_3d/`） | 脚本（`src/vfx/`） | 调用方 | 进池 |
|---|---|---|---|---|---|
| 枪口花火 | `VFX-MUZZLE-FLASH-3D` | `vfx_muzzle_flash_root_top3d.tscn` | `VfxMuzzleFlash3D.gd` | `WeaponModel3D._spawn_muzzle_effect()` | ✅ `FX01_MUZZLE_FLASH` |
| 弹壳抛出/落地 | `VFX-SHELL-CASING-3D` | `vfx_shell_casing_root_top3d.tscn` | `VfxShellCasing3D.gd` | `WeaponModel3D._fire_now()` → `_spawn_shell_casing()` | ✅ `FX01_SHELL_CASING` |
| 命中爆点 | `VFX-IMPACT-3D` | `vfx_impact_root_top3d.tscn` | `VfxImpact3D.gd` | `Projectile3D._spawn_effect()`、`Enemy3D` | ✅ `FX01_IMPACT` |
| 飞行子弹视觉 | `VFX-BULLET-VISUAL-3D` | `vfx_bullet_visual_root_top3d.tscn` | `VfxBulletVisual3D.gd` | `Projectile3D`（弹体自身） | **❌ 刻意不进池** |
| 近战挥砍弧光 | `VFX-MELEE-SLASH-3D` | `vfx_melee_slash_root_top3d.tscn` | `VfxMeleeSlash3D.gd` | `PlayerMeleeCombat3D` | ✅ |
| 近战命中 | `VFX-MELEE-IMPACT-3D` | `vfx_melee_impact_root_top3d.tscn` | `VfxMeleeImpact3D.gd` | `PlayerMeleeCombat3D` | ✅ |
| 受击飘字 | `VFX-DAMAGE-NUMBER-3D` | `vfx_damage_number_root_top3d.tscn` | `VfxDamageNumber3D.gd` | `Enemy3D` | ✅ |
| 治疗飘字 | `VFX-HEAL-NUMBER-3D` | `vfx_heal_number_root_top3d.tscn` | `VfxHealNumber3D.gd` | 治疗调用方 | ✅ |
| 爆炸 | `VFX-EXPLOSION-3D` | `vfx_explosion_root_top3d.tscn` | `VfxExplosion3D.gd` | 旧池 `CombatEffectPool3D` | ⚠️ **仍走旧池（E08）** |

**子弹为什么不能进池**：它的生命周期归 `ProjectilePool3D`（弹体复用）。再进 `VfxPool3D` = 双宿主争抢归还，会 double-free 或漏回收。
**旧链兜底**：`WeaponModel3D` / `Projectile3D` 里保留一次性的 `CombatEffectPool3D` 回退分支，旧 kind（如 `"explosion"`）必须抽成具名常量（`LEGACY_EFFECT_EXPLOSION`），别裸字符串。
**弹壳为什么可以进池**：它的生命周期由视觉自己了结（落地静止 → `lifetime` 到点回池），不像子弹那样另有一个 `ProjectilePool3D` 宿主 ⇒ 没有 double-free 风险。

## 3. 制作流程（6 步）

### 步骤 1 — 定契约
- 查 14.6 §2.1 命名表：**AssetID / Prefab 文件名 / 根节点 `class_name` 三者严格对应**。
- **运行资产路径不含 `_vNNN`**（去版本化）：文件名是 `vfx_muzzle_flash_root_top3d.tscn`，版本号只落 Prefab 根 meta `asset_version` + 账本版本列 + `source/**`。
- AssetID 已存在 ⇒ **只升级既有行，禁新增**（否则门禁报 `duplicate_asset_id`）。

### 步骤 2 — 写 Prefab + 脚本
- 根节点必须继承 `src/vfx/VfxEffectBase3D.gd`；Prefab 根加 meta：`metadata/asset_id`、`metadata/asset_version`。
- 所有可变状态（子节点 `scale` / `position` / `material albedo.a` / 灯能量）必须在 `_on_activate` 里**全部复位** —— 池化复借的唯一保障。
- 几何优先复用 `src/vfx/ToonVfxGeometry.gd`（`core_mesh / flame_mesh / petal_mesh / ring_mesh / spark_mesh / spike_mesh / debris_mesh` + `toon_material()`，全部带缓存）。
- **PBR 参数走「单一常量组」**：一件资产的所有材质数值（`metallic` / `roughness` …）收敛成脚本顶部常量（如 `SHELL_METALLIC` / `SHELL_ROUGHNESS`），**件与件之间只允许基色差异**，一律经同一个 `_make_material(color)` 工厂出口。逐件散写数值 = 以后改一处漏两处（本事务初版就是三件各写各的）。
- ⚠️ **术语口径**：「反光度」= `StandardMaterial3D.roughness` 通道（**不是** `metallic`、也不是 `specular`）。`WeaponModel3D._material(color, metallic, roughness)` 的第 3 参数就是它。代码与账本里两栏都要写全（`金属度 metallic=0.8 / 反光度 roughness=0.6`），只写「反光度 0.6」半年后没人知道映射到哪个通道。

卡通风配方（已实测）：

| 想要 | 怎么做 |
|---|---|
| 立体楔形火焰 | `CylinderMesh` + `top_radius = 0.0`（**Godot 4.x 没有 `ConeMesh`**），apex 朝 -Z |
| 交叉尖瓣 | 两片 `PlaneMesh`，第二片绕 forward 轴再转 90° 形成十字 |
| 纯色卡通材质 | `UNSHADED` + `ALPHA` + `depth_draw_always`；`cast_shadow = OFF` |
| 朝向前向 | `global_transform = Transform3D(Basis.looking_at(forward), global_position)` |
| 朝向法线 | `Basis(Quaternion(Vector3.UP, normal))` |
| 飞散火星 | 子节点 `position = dir * dist`，`dist` 与 `scale` 随 t 变化 |
| 脉冲 | `t = clamp(elapsed / lifetime, 0, 1)`，各项按 `(1-t)` 或包络衰减 |

### 步骤 3 — 注册进池
`VfxPool3D._REGISTRY` 加 `FX01_XXX: preload("res://assets/art/vfx/combat_3d/<prefab>.tscn")`，并加同名 `const FX01_XXX := "VFX-XXX"`（供调用方类型化引用）。
**纯视觉附件（弹体拖尾之类）不进注册表。**

### 步骤 4 — 接调用方
```gdscript
var pools := get_tree().get_nodes_in_group("vfx_pool_3d")   # 禁写 /root/VfxPool 硬编码
if not pools.is_empty() and pools[0] is VfxPool3D:
    (pools[0] as VfxPool3D).acquire(
        VfxPool3D.FX01_MUZZLE_FLASH, pos, color, size,
        {"forward": -global_basis.z, "follow": _muzzle}     # 会动就必须绑 follow
    )
```
- ⛔ 禁 `get_node_or_null("/root/VfxPool")`：autoload 常驻会让调用方里的「回退旧池」分支**永不触发** ⇒ 死代码，且弱类型 `call("acquire", "字符串")` 绕过编译期校验。
- 需要每把枪/每种武器不同视觉体积时，在调用方定义具名常量（如 `MUZZLE_FLASH_EFFECT_SIZE := 0.8`），并写清口径注释。

### 步骤 5 — 写验收（§6）
### 步骤 6 — 账本 + 文档 + 门禁（§7）

## 4. 灯光真相（业主「子弹要带灯光」的出处）

- 灯必须是 `OmniLight3D`，节点**具名**（`MuzzleLight` / `ProjectileLight`），`shadow_enabled = false`。
- ⚠️ **属性名是 `light_energy`，不是 `.energy`**（`.energy` 是 `WastelandLight3D` 的自定义属性）。写错在**解析期**直接报 `Parse Error`，不进运行时。
- ⚠️ **能量不随 `effect_size` 缩放，范围才随**：`omni_range = BASE * effect_size`；`light_energy` = 常量 × 衰减包络。
- 能量包络契约：出生为峰值 → 半程仍 > 0 → 寿命结束**必须归零**（`_on_lifetime_expired()` 里显式置 0）。
- 回收/复借：`deactivate()` 灭灯且不可见；`activate()` 重新点亮 + 复色 + 复尺度。

## 5. 跟随契约 `context.follow`（2026-09-21 实机缺陷固化）

**现象**：角色一走动，枪口特效留在开火瞬间的位置（"残留"）。

**根因**：池化特效挂在池（世界空间）下，`activate()` 只设一次世界坐标，之后不再跟随任何东西。

**基类已内建**（`VfxEffectBase3D`）：
- `context.follow`（`Node3D`）+ `context.follow_local_offset`（`Vector3`，挂点**本地空间**偏移）
- `activate()` 里 `_bind_follow()` 并把初位置设为 `follow_position()`；`_process` 每帧同步位置
- 子类可用 `follow_forward()` 拿挂点 local -Z
- 未绑定、挂点已释放（`is_instance_valid`）或已移出树 ⇒ **自动退化为世界锚定，不报错**

**三条硬规则**：
1. **跟随目标选「真正跟着角色动的那个节点」**。枪口必须跟 `muzzle` 挂点，**不能跟武器根**：`WeaponModel3D._process` 每帧按后坐力与换弹位移 `_visual_root`（`_recoil + 0.04 * reload_arch`），跟根节点会在开火瞬间差一截。
2. `_follow` 每次 `activate()` 重置 ⇒ 上次绑定**不泄漏**到下一次复借。
3. 跟随只同步**位置**，**朝向要在子类 `_on_tick` 里按 `follow_forward()` 重算**，否则转身后弧光留在旧方向。

## 5.5 抛出物类特效（弹壳）—— 脱离挂点进入世界空间（2026-09-22 落地）

**与枪口花火正好相反**：枪口花火要**绑** `context.follow`（钉死在挂点上），弹壳必须**不绑任何跟随**，一次性取得初速度后完全由自己积分位置。别顺手给抛壳物也加 `follow` —— 加了它就永远钉在枪上不落地。

契约（`VfxShellCasing3D` 已实现，可直接抄）：

| 项 | 口径 |
|---|---|
| 出生点 | 调用方枪械的 `EjectionSocket`；缺失回落 `TacticalSocket`；程序生成枪用 `Vector3(width*0.62, height*0.20, -length*0.42)`；**近战武器直接 return 不抛壳** |
| 初速度 | 枪械 `global_basis` 基向量：`right` 主抛、`up` 抬升、`forward` 少量前送；**逐发随机**见 §5.5.3 |
| 重力 | `GRAVITY := 9.8`，自积分 `v.y -= g*dt` |
| 落地 | **纯解析式越线**：`next.y - (floor_y + _radius) > 0` 算飞、否则碰撞。**不接物理引擎**（无射线、无碰撞体、无 `RigidBody3D`） |
| 地面真源 | `context.floor_y`（**必传、唯一真源**）—— 见 §5.5.2 |
| 三阶段 | `FLYING → ROLLING → SETTLED`：抛物弹跳 → 贴地指数衰减滚动 `v(t)=v0·e^(−3.4t)` → `smoothstep` 过渡躺平 |
| 弹跳 | `MAX_BOUNCES := 2`；法向速度低于 `REST_SPEED (0.12)` ⇒ 转滚动 |
| 寿命 | `DEFAULT_LIFETIME := 4.7`，到点走基类回池。**它就是「弹壳在地上停留多久」** —— 飞行/弹跳/滚动三段不随寿命变化，见 §5.5.5 |

### 5.5.1 四条实测坑

1. **贴地半径必须取三件里最大的径向半展**：本件 = 底缘 `TorusMesh.outer_radius = 0.058`（壳体只 0.046、底火 0.025）。按壳体取会让底缘整圈**陷进地板 1.3 cm**。优先用 `_measure_radial_half_extent()` 从已挂载 mesh 实测，常量只作契约值与兜底。
2. **`_on_tick(_elapsed, lifetime)` 给的是累计时间不是 dt**：要位移得自己转增量，并夹住卡帧尖峰，否则一次 0.5 s 卡顿会让弹壳瞬移穿过地板：

```gdscript
var dt: float = clampf(delta_elapsed - _last_tick_elapsed, 0.0, 1.0 / 15.0)
_last_tick_elapsed = delta_elapsed
```

3. **缩放只许落子节点，且必须同步缩放它们的偏移**。缩放挂到**根节点** ⇒ 根 basis 非正交 ⇒ 后续旋转赋值报 `must be normalized in order to be casted to a Quaternion`；只缩放三件 `scale` 而漏掉底缘/底火的 `position` ⇒ 三件裂开（0.8 尺寸下肉眼可见断成两块）。
4. **弹壳是「一次性运动」不是「跟随」**：它不进 `context.follow`，因此 §5.2「跟随只同步位置、朝向要在 `_on_tick` 重算」那条规则**不适用**于抛壳物。

### 5.5.2 ⛔ `context.floor_y` 必须给真实地面高度（P0，2026-09-22 实机缺陷「弹壳特效没了」）

**症状**：实机完全看不见弹壳，而 headless 验收与数值探针**全绿**。

**根因**：调用方把 `floor_y` 硬编码成 `0.0`。塔楼楼层**向下**建造（`stage.position.y = -FLOOR_HEIGHT_M(12.0) × floor_index`），98F ≈ **−1176 m** ⇒ 弹壳出生点 y 就已「低于地面」⇒ **第一帧判定触地**、被夹到 `floor_y + 半径 ≈ 0.046` ⇒ 瞬移到世界原点附近、离玩家一公里多。

**规矩**：`floor_y` 取**射击者站立面的世界 y**（玩家原点即脚底行走面）。调用方实现 `WeaponModel3D._resolve_shell_floor_y(shooter)`，射击者失效时回落枪身 y，**绝不以 0 兜底**。

**为什么验收会假绿**：验收场景摆在 y≈0，`floor_y = 0` 恰好正确 —— 这个坑**只在非零楼层暴露**。⇒ 任何「地面高度 / 绝对坐标」类常量，都必须**专造非零高度用例**（本件：把枪与射击者一起搬到 98F 开火，断言弹壳留该层且 `|y| > 100`）。

### 5.5.3 抛壳随机化：**随机数只许活在调用方**

业主口径（2026-09-22）：「方向、高度、初始旋转位置、落地后的范围、旋转等数值都需要做一个随机。不然太整齐了。」

**`VfxShellCasing3D` 必须保持确定性** —— 对同一 `context` 逐位可复现，脚本内**不出现 `randf()`**。它是被**逐帧断言**驱动的对象（验收与视觉探针都手动步进到固定时刻，再断言姿态 / 高度 / 触地次数），把随机埋进 `_on_activate` 会让这些断言全部变成随机红。

⇒ 逐发随机的职责在调用方 `WeaponModel3D._spawn_shell_casing`，全部按**枪械局部基**施加（与枪朝向无关）：

| 量 | 幅度（基准 = 初版固定值，只把「点」摊成「一团」） |
|---|---|
| 右向速度 | `2.1 × r(1−0.35, 1+0.35)` |
| 抬升速度 | `1.55 × r(1−0.45, 1+0.45)` |
| 前送速度 | `0.30 × r(−1, 1)` —— **绝对值**抖动，可为负 |
| 自旋轴 | `(right + up × r(0.1,0.9) + forward × r(−0.4,0.4)).normalized()` |
| 自旋速度 | `20 × r(1−0.5, 1+0.5)` |
| 初始姿态 | 绕**随机单位轴**转 `r(−1,1) × 45°`，经 `context.initial_basis` 传入 |

三条推导：

- **右向抖动有上限 `0.523`**：验收钉着「每发仍从枪械右侧抛出」= 右向速度 `> 1.0 m/s` ⇒ `2.1×(1−s) > 1.0`。取 `0.35` 留余量。
- **前送量基准太小（0.22 m/s）必须用绝对值抖动**：按比例 ±50% 也摇不出可见差别，等于没随机。
- **随机轴取自单位立方体后归一化，别用球坐标**：球坐标的方位角 / 仰角会在两极堆积，姿态只多出两三种，随机感反而更差。

特效侧只需支持一个可选入参 `context.initial_basis`（缺省恒等、写入前 `orthonormalized()`）。`get_presentation_snapshot()` 补 `spin_axis` / `spin_speed` / `spawn_basis` 真值供验收读取。

### 5.5.4 判「弹壳太整齐」不能用「两两最大间距」

业主截图的特征不是「挤在一起」，而是**落点都在同一条线附近**。纯摆头（枪在转、抛壳口径不变）时落点沿一条弧排列：

- 两两最大间距 = `0.4469 m` ← 看着挺大，完全不能说明散开了
- 离「最远两点连线」的最大垂直偏差 = **`0.0114 m`** ← 这才是「一条线」的量化

⇒ 判据用**离最佳拟合线的垂直偏差**，阈值取 `0.10 m`（弧排列是毫米级、随机散开是分米级）。随机化生效后实测 `0.37 ~ 0.45 m`。

复现方式：探针走**真实调用方路径**连发 N 发（每发之间摆头，复刻实机后坐），枪与射击者摆好、`floor_y` 给对，再全部推到静止后量落点。**别在探针里另抄一套随机口径** —— 那只证明「探针会摆散布」，证明不了实机弹壳真散了。

### 5.5.5 弹壳的「停留时长」就是 `DEFAULT_LIFETIME`（2026-09-22 业主追加 +1.5s）

业主口径：「弹壳的停留时长加 1.5 秒。」落点只有一处 —— `VfxShellCasing3D.DEFAULT_LIFETIME: 3.2 → 4.7`。

**为什么「加寿命」就等于「加停留」**：飞行 / 弹跳 / 滚动三段的时长由物理常量（`GRAVITY` / `BOUNCE_RESTITUTION` / `ROLL_DAMPING` …）与初速度决定，**与寿命无关** ⇒ 多出来的 1.5 s 只能落在 `SETTLED`（躺平静止）之后的停留上。实测（按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`（上一版 `2.05 s`）。**别新建「停留参数」** —— 那与寿命语义重复，还会让两处口径打架。

**验收三条互补断言**（`_check_shell_settled_hold()`，期望值全部硬编码在验收侧）：

1. 寿命 == 定档值 `4.7`；
2. 寿命 − 上一版 `3.2` == 增量 `1.5`（**业主诉求本身**）；
3. 实测静止时刻后剩余停留 `≥ 1.5 s`（挡住「有人把初速度调大到飞行段吃掉这 1.5 s」）。

⚠️ 第 3 条是**下限守卫**，不是「+1.5」的钉子：寿命退回 3.2 时它仍成立（`3.20 − 1.15 = 2.05 ≥ 1.5`）。真正咬住 +1.5 的是第 1、2 条 —— 写这类断言时**必须自己说清哪条守什么**，否则下一个人会以为守住了。
⚠️ 三个期望值**各自硬编码，不要写成 `3.2 + 1.5` 的派生式**：派生式会让改坏一处时三处一起跟随（自印证，反例见 §6 第 9 条）。
⚠️ 用例必须用**全新实例**：主用例那枚已被推进到 1.94 s 且早已 `SETTLED`，复用它测到的 `t_settle` 恒为第一个步长，断言直接废掉。任何「求某阶段发生时刻」的用例都要**新实例 + 从 0 步进**。

**成本必须一起算**（`VfxPool3D` 对 active 实例**无上限**）：`max_per_kind = 32` 只管 **inactive 回收桶**（`retire()` 里桶满才 `queue_free`），active 是想借就 `instantiate`。⇒ 拉长寿命 = 抬高同屏存活数：射速 `1.0 ~ 12.0 发/s` × `4.7 s` ⇒ 最坏同屏约 `56` 枚（上一版 `38` 枚），每枚 3 件 / `288` 三角面 ⇒ 约 `16k` 三角面、约 `170` 次绘制，仍很便宜。**下次再加寿命照这个式子复核，别凭感觉。**

## 6. 验收配方

跑法（本机）：
```bash
G="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . res://tests/verification/verify_combat_vfx_toon_v002.tscn > _scratch/vfx_xxx.log 2>&1
grep -nE "_OK|ERROR" _scratch/vfx_xxx.log
```
- 日志落 `_scratch/`；**`--script` 在本仓会假报 `Identifier not found`，一律跑场景**。
- 新增 `class_name` 后先 `--import` 刷 `.godot/global_script_class_cache.cfg`。
- 判据是 `*_OK` 行 + `ERROR` 计数，**不看裸退出码**。
- 现成骨架：`tests/verification/verify_combat_vfx_toon_v002.gd`（三类特效 + 跟随 + 尺寸 + 端到端接线 + 抛壳随机化统计，samples=15）；池契约：`verify_vfx_pool_lifecycle.tscn`。

每个特效 Prefab 必过的断言：

1. AssetID + 版本 meta 正确。
2. **灯真相**：节点名 / 无阴影 / 范围在预期带 / 出生能量为正 / 寿命结束为零。
3. **朝向对齐**（`dot > 0.999`）**并附反向对照**（对垂直轴或非对齐轴 `dot < 0.5`）。
4. **无碰撞体**：递归统计 `CollisionObject3D` / `CollisionShape3D`，必须为 0。
5. **防假绿哨兵**：统计样本数，少于预期直接判失败。
6. **跟随**：生成位置落在挂点偏移上 → 挂点平移后仍贴合 → 挂点转身后前向跟随；**并附对照组**（未绑 `follow` 的实例必须跟不上）。
7. **尺寸线性**（调用方会传 `effect_size` 时）：`size = 1.0` 与 `0.8` 的同一子节点 `scale` 比值 ≈ 1.25（容差 2%），同时校灯范围比值 0.8。
8. **端到端接线**（最容易被漏、最容易假绿）：

```gdscript
var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
add_child(weapon)
var tree := BlueprintRegistry.build_weapon_tree(
    BlueprintRegistry.DEFAULT_STARTING_GUN_ID, "mod_bullet_standard")
weapon.configure_from_tree(tree)
weapon.global_position = Vector3(3.0, 1.0, 5.0)      # 挪开原点，防「位置恰好正确」
weapon.call("_spawn_muzzle_effect", self)
var bucket: Array = pool._active.get(VfxPool3D.FX01_MUZZLE_FLASH, [])
var effect := bucket.back() as VfxEffectBase3D
# 断言：进了池 / 绑了 follow / 落在 muzzle 上 / 用调用方尺寸基准 / 武器平移后仍贴合
```
⚠️ `BlueprintRegistry.create_assembly_node()` 返回 `AssemblyNode`，**不能**直接喂 `configure_from_tree()`（它要 `WeaponAssemblyTree`）⇒ 测试一律用 `build_weapon_tree(gun_id, bullet_id)`。
9. **PBR / 材质真值**（业主指定了具体数值时）：断言必须**读已挂载材质**（`mesh_instance.material_override.metallic`），且期望值**硬编码在验收侧**（`EXPECTED_SHELL_METALLIC := 0.8`），**另加一条** `脚本常量 == EXPECTED_*` 把常量本身也钉住；每件（壳体/底缘/底火）各查一遍。
   ⛔ 反例（本事务初版写法）：`_expect(absf(snap.metallic - VfxShellCasing3D.SHELL_METALLIC) < 0.0001, …)` —— 期望引用被测常量 ⇒ 常量改成 0.5 时期望跟着变 0.5，**断言永远绿**。这个「自印证」模式对任何「期望值由被测代码自己给出」的断言都成立，不止 PBR。
   辅助函数 `_material_float(node, "metallic")` **无材质时返 `-1.0` 哨兵**（返 0.0 会被当成合法值混过断言）。
10. **行为本身带随机时**（见 §5.5.3 / §5.5.4）：① 统计**极差**而不是均值（对称抖动会在求均值时互相抵消）；② 抽 24 发时，均匀分布下极差不足理论值一半的概率 ≈ `2×0.5²⁴ ≈ 1e-7`，不会假红；③ **必须同时断言「显式 `context` 路径逐位确定」**——否则「随机」可能只是快照读取噪声；④ 判「还是不是一条线」用**离最佳拟合线的垂直偏差**，不用两两最大间距（§5.5.4）；⑤ 若随机化的**发起方**是调用方，统计用例要走**真实调用方**路径，并先把枪摆到非原点 + 给偏航角，验证抖动确实施加在**枪械局部基**上而不是世界轴。
11. **寿命 / 停留类观感定档**（业主给了「加 / 减 N 秒」时）：① 期望值**硬编码**，定档值 / 增量 / 下限三条**互不派生**；② 有「上一版值」时必须**显式断言增量**（`lifetime − PREVIOUS == DELTA`）—— 只断言绝对值抓不到「有人顺手把上一版基准也改了」；③ 行为级下限断言要注明它在什么情况下才红，别让它冒充增量钉子；④ 拉长寿命的**同屏成本**要在源码注释里给式子（射速 × 寿命 × 每枚节点数）。见 §5.5.5。

**反向对照纪律**：
- 改坏 → 必须变红 → 还原 → 复绿；还原后 `grep -rn "REVERSE-CONTROL" src/` 必须为空。
- **看红的数值对不对得上**：残留量应精确等于施加的位移模长（实测 `6.0000 m`、`3.9051 m = √(3²+2.5²)`），转向对照 `dot = -0.0000`（90° 正交）。数值自洽 = 断言真在测量；只看到「红了」不算。

## 7. 账本、门禁与文档回写

**账本**：`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`

| 分页 | 用途 |
|---|---|
| 资产主表 | 唯一登记源。`check_asset_registry.py --ledger vfx` 的 `asset_count` **只读这里** |
| 3D-特效 | FX01-xx 条目：功能说明 / 功能脚本 / 标准尺寸 / 原点朝向 / 使用位置 / 状态 / 版本 / 备注 |
| 域变更日志 | 每次改动追加一行：台账版本 / 日期 / 类型 / 范围 / 说明 / 兼容性 / 负责人 |

⚠️ **改「3D-特效」分页不会改变 `--ledger vfx` 的计数**（计数来自资产主表）⇒ 别拿门禁数字当「账本登记了没有」的证据。
⚠️ 用 openpyxl 往返（`load_workbook` → 改 → `save`）会保留 DV 下拉与合并格；**改前 `shutil.copy2` 备份到 `_scratch/`**，改后回读校验。

⚠️ **回写脚本三条硬要求**（2026-09-22 踩坑）：
1. **样式复制必须用 `copy()`**：`cell._style` 是 openpyxl 的 `StyleArray`，**没有 `.copy()` 方法**（写 `x._style.copy()` 直接 `AttributeError` 中断，且中断点在 `save()` 之前 ⇒ 文件没坏但白干）。正确写法 `from copy import copy` → `dst._style = copy(src._style)`，并另拷 `dst.number_format = src.number_format`。
2. **脚本必须幂等**：备注按「是否已含标记串」判重、日志行按「台账版本号列是否已存在」判重；否则重跑一次就多一段文字 / 多一行 `v0.1.4`。
3. **新增行后要一起扩公式范围**：派生查重列（R/S）与总览公式的统计范围从 `$R$6:$R$<旧末行>` 扩到新末行，否则门禁报 `dedupe_result_formula_wrong` / `stale_overview_formula`。

门禁：
```bash
"C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe" scripts/check_asset_registry.py --ledger vfx
```
判据：`asset_count` 不变、`sha_mismatch` 只有既有两条（`VFX-HEALTH-VIGNETTE` / `VFX-VISIBILITY-FIELD-3D`）。**新增任何 mismatch = 你动了被登记的路径**。

文档回写（缺一即「文档承诺未兑现」）：
- `docs/v0.1/14.6_特效系统与制作规范.md`：接口/契约变了 ⇒ 同步 §3.x 代码块 + §10 版本历史
- `docs/v0.1/MODULE_INDEX.md`：`VFX-POOL` 行的验收脚本与现状
- `docs/v0.1/development/2026-09-12_discrepancy_table.md`：动到双池迁移就更新 **E08** 进度
- `assets/registry/ledger_index.json` 的 `vfx` 域 `primary_skill`：**本 skill 已接管**（旧值 `godot-model-asset-import-standard` 降为 `supporting_skills`）
- 项目记忆：`.workbuddy/memory/YYYY-MM-DD/HHMM_<slug>.md` + 当天 `_INDEX.md`

## 8. 行尾与解析期坑（本仓高频翻车点）

- 写回 `.gd/.tscn/.json/.md` **必须 CRLF**（二进制 / `newline=""` 写）。**已是 CRLF 的文件再被转一次 LF→CRLF 会得到 `\r\r\n`** ⇒ Godot 报 `Stray carriage return character`，该脚本解析失败，并让 preload 它的文件报 `Could not resolve script`。
- 判据：孤立 LF `count('\n') - count('\r\n') == 0`；CRCRLF `count('\r\r\n') == 0`。
- 项目**开「警告即错误」**：`var x := clamp(...)` 因 `clamp()` 返 `Variant` 直接编译失败（`Cannot infer the type`）⇒ 一律 `var x: float = clamp(...)`。凡返 `Variant` 的内建同理。
- `var len := ...` 遮蔽内建 `len()` ⇒ 换名（如 `spike_length`）。
- `PhysicsRayQueryParameters3D.create(from, to, mask)` **只有 3 个参数**；想「排除自身」也不能传第 4 个 `[get_rid()]`（本仓 Godot 4.6.3 报 `Function "get_rid()" not found in base self`）。
  ⚠️ **弹壳自 2026-09-22 起已不再用射线**（改纯程序化模拟碰撞，见 §5.5）；这条坑对它不再适用，但本仓其它代码仍可能踩。
- 脚本快照 / `.before.gd` **禁落 `res://` 内**（`class_name` 抢注 + class cache 被旧副本覆盖，本仓已发生两次事故）。

## 9. 常见缺陷速查

| 现象 | 根因 | 修法 |
|---|---|---|
| 角色走动时特效留在原地 | 池化特效只设一次世界坐标 | 绑 `context.follow`（§5） |
| 后坐力/换弹瞬间特效与枪口差一截 | 跟随目标选了武器根（`_visual_root` 逐帧位移） | 改跟 `muzzle` 挂点 |
| 转身后弧光画在玩家背后 | 顶点用 `+cos` 且不消费 `forward` | 消费 `forward` 并在 `_on_tick` 重算朝向 |
| 复借后残留长明灯 | 回收没把灯能量归零 | `_on_lifetime_expired()` 显式 `light_energy = 0` |
| 子弹被回收两次 | 子弹视觉进了池 + 弹体池双宿主 | 子弹纯视觉**不进** `VfxPool3D` |
| 特效白板/不显示 | 材质没走 UNSHADED+ALPHA，或缺 `depth_draw_always` | 用 `ToonVfxGeometry.toon_material()` |
| 改了账本但门禁数字没动 | 改的是「3D-特效」分页 | 门禁只读「资产主表」 |
| 验收绿但游戏里是坏的 | 只测了机制层，没测调用方接线 | 加端到端接线探针（§6.8） |
| 弹壳浮在地面上方不落地 | 贴地半径取了壳体的 0.046，小于真实最大径向半展 | 取三件里最大者：底缘 `outer_radius = 0.058`（§5.5.1） |
| 弹壳整圈陷进地板 1.3 cm | 同上（半径取小 ⇒ 判定贴地高度偏低） | 同上 |
| 验收报「弹跳超过最大次数」 | 首次落地结算被误计成一次弹跳 | 只在真的反弹时 `_bounces += 1`（§5.5） |
| **实机看不见弹壳，但 headless 验收 + 探针全绿** | 调用方把 `floor_y` 兜底成 0，而楼层在 −1176 m | `floor_y` 取**射击者站立面**世界 y，绝不以 0 兜底（§5.5.2） |
| 弹壳落点排成一条整齐弧线 | 抛壳量全是固定常量，`randf` 根本没进过这条链路 | 随机化放**调用方**（§5.5.3）；判据用离拟合线垂直偏差（§5.5.4） |
| 弹壳随机化后验收开始随机变红 | 把 `randf()` 埋进了**被逐帧断言驱动**的特效脚本 | 特效脚本保持确定性，随机化只活在调用方（§5.5.3） |
| 弹壳在地上停留太短 / 消失太快 | 去新建「停留参数」，或以为弹跳次数、滚动阻尼能影响停留 | 停留 = `lifetime − t_settle`，飞行段不随寿命变化 ⇒ **直接加 `DEFAULT_LIFETIME`**（§5.5.5） |
| 拉长弹壳寿命后担心池被占满 | 以为 `max_per_kind` 限制同时存在数 | `max_per_kind` 只管 **inactive 回收桶**，active 无上限；真实成本 = 射速 × 寿命（§5.5.5） |
| 弹壳钉在枪上不飞出去 | 顺手给抛壳物也绑了 `context.follow` | 抛出物**不绑跟随**，一次性初速度 |
| 改了 PBR 常量但验收仍绿 | 期望值引用了被测脚本常量（自印证） | 期望硬编码在验收侧 + 额外钉常量（§6.9） |

## 10. 边界

- 本 skill 只管**战斗/表现类 3D 特效的 Prefab 与代码链路**。场景美术模块、角色/敌人/武器建模走各自的模型管线 skill；Blender 源与 GLB 导出不在这里。
- 场景设施的环境色盘 post_import 规则**不适用**于特效（特效是程序几何 + 材质）。
- 动特效前先读 E08：`explosion` 与部分近战验收仍走旧池 `CombatEffectPool3D`，那是**已知未关闭项**，不是新 bug。
