---
name: vfx-combat-effect-authoring
description: 制作、重做、修复或验收 ShellStorm2 的 3D 战斗特效（VFX）——枪口花火、命中爆点、飞行子弹视觉、近战挥砍弧光、受击/治疗飘字、爆炸。用于「做特效 / 重做特效 / 特效不好看 / 要卡通风 / 枪口火光 / 命中爆点 / 子弹要带灯光 / 特效残留 / 特效不跟着枪口走 / 特效留在原地 / 特效没进池 / AssetID 路由 / VfxPool3D / VfxEffectBase3D / 特效验收 / 特效账本登记 / 14.6」这类问题。不用于场景美术模块、角色/敌人/武器建模与 Blender 导出链路（那些走各自的模型管线 skill）。
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
| 命中爆点 | `VFX-IMPACT-3D` | `vfx_impact_root_top3d.tscn` | `VfxImpact3D.gd` | `Projectile3D._spawn_effect()`、`Enemy3D` | ✅ `FX01_IMPACT` |
| 飞行子弹视觉 | `VFX-BULLET-VISUAL-3D` | `vfx_bullet_visual_root_top3d.tscn` | `VfxBulletVisual3D.gd` | `Projectile3D`（弹体自身） | **❌ 刻意不进池** |
| 近战挥砍弧光 | `VFX-MELEE-SLASH-3D` | `vfx_melee_slash_root_top3d.tscn` | `VfxMeleeSlash3D.gd` | `PlayerMeleeCombat3D` | ✅ |
| 近战命中 | `VFX-MELEE-IMPACT-3D` | `vfx_melee_impact_root_top3d.tscn` | `VfxMeleeImpact3D.gd` | `PlayerMeleeCombat3D` | ✅ |
| 受击飘字 | `VFX-DAMAGE-NUMBER-3D` | `vfx_damage_number_root_top3d.tscn` | `VfxDamageNumber3D.gd` | `Enemy3D` | ✅ |
| 治疗飘字 | `VFX-HEAL-NUMBER-3D` | `vfx_heal_number_root_top3d.tscn` | `VfxHealNumber3D.gd` | 治疗调用方 | ✅ |
| 爆炸 | `VFX-EXPLOSION-3D` | `vfx_explosion_root_top3d.tscn` | `VfxExplosion3D.gd` | 旧池 `CombatEffectPool3D` | ⚠️ **仍走旧池（E08）** |

**子弹为什么不能进池**：它的生命周期归 `ProjectilePool3D`（弹体复用）。再进 `VfxPool3D` = 双宿主争抢归还，会 double-free 或漏回收。
**旧链兜底**：`WeaponModel3D` / `Projectile3D` 里保留一次性的 `CombatEffectPool3D` 回退分支，旧 kind（如 `"explosion"`）必须抽成具名常量（`LEGACY_EFFECT_EXPLOSION`），别裸字符串。

## 3. 制作流程（6 步）

### 步骤 1 — 定契约
- 查 14.6 §2.1 命名表：**AssetID / Prefab 文件名 / 根节点 `class_name` 三者严格对应**。
- **运行资产路径不含 `_vNNN`**（去版本化）：文件名是 `vfx_muzzle_flash_root_top3d.tscn`，版本号只落 Prefab 根 meta `asset_version` + 账本版本列 + `source/**`。
- AssetID 已存在 ⇒ **只升级既有行，禁新增**（否则门禁报 `duplicate_asset_id`）。

### 步骤 2 — 写 Prefab + 脚本
- 根节点必须继承 `src/vfx/VfxEffectBase3D.gd`；Prefab 根加 meta：`metadata/asset_id`、`metadata/asset_version`。
- 所有可变状态（子节点 `scale` / `position` / `material albedo.a` / 灯能量）必须在 `_on_activate` 里**全部复位** —— 池化复借的唯一保障。
- 几何优先复用 `src/vfx/ToonVfxGeometry.gd`（`core_mesh / flame_mesh / petal_mesh / ring_mesh / spark_mesh / spike_mesh / debris_mesh` + `toon_material()`，全部带缓存）。

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
- 现成骨架：`tests/verification/verify_combat_vfx_toon_v002.gd`（三类特效 + 跟随 + 尺寸 + 端到端接线，samples=9）；池契约：`verify_vfx_pool_lifecycle.tscn`。

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

## 10. 边界

- 本 skill 只管**战斗/表现类 3D 特效的 Prefab 与代码链路**。场景美术模块、角色/敌人/武器建模走各自的模型管线 skill；Blender 源与 GLB 导出不在这里。
- 场景设施的环境色盘 post_import 规则**不适用**于特效（特效是程序几何 + 材质）。
- 动特效前先读 E08：`explosion` 与部分近战验收仍走旧池 `CombatEffectPool3D`，那是**已知未关闭项**，不是新 bug。
