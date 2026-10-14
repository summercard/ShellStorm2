# 命中特效分流 + 两件僵尸死亡表现定型（FX01-20 / FX01-21 / FX01-17 v002）

时间：2026-10-14 23:40 ｜ 负责人：摩斯拉 ｜ 账本版本：v0.1.22

## 业主口径（三轮，逐步收敛）

**第一轮**：

> 对击中特效进行区分，使用爆炸粒子 ×12 的这个特效，**作为一个独立特效**，作为打中小僵尸，警察僵尸，
> 胖子僵尸的受到枪击的特效，原来那个特效缩小 60%，作为击中其它物体的特效，然后更新账本和设计文档。
> 重新制作胖子僵尸的自爆特效，**把小僵尸的死亡特效，放大 2 倍**，然后带有一个绿色冲击波的效果，
> 同样去掉胖子僵尸的倒地动画播放。

**第二轮**（我问了两个读数，业主把「缩小 60%」整条改掉）：

> **重新制作一个**吧，通过一个打击到金属的粒子反馈的特效，用白色方块粒子和 2 根长条的金色火星一样
> 飞溅去替代，这个不要用太多粒子，**4-5 颗 + 2 根金色火星**即可。
> 〔胖子自爆方向〕**橙红方块 + 绿色冲击波**
> 〔近战是否复用〕**枪击 + 近战都用**

**第三轮**（纠正了我对「放大 2 倍」的归属理解）：

> **完全撤回**，然后小僵尸死亡是**没有冲击波**的，**只有胖子僵尸死亡有冲击波**，小僵尸和警察僵尸死亡
> 依然保持上个版本的特效（就是刚才加的那个）。然后受击的特效也**不要太大**，我看到有点太大了，小一点。

⚠️ **最容易搞错的一处**：第二轮那句「把小僵尸的死亡特效放大 2 倍」不是改小僵尸，而是**拿小僵尸那套
表现去做胖子僵尸**。我在第二轮把它实现成了 FX01-19 的改版（×2 + 冲击波），第三轮被业主撤回并更正。
最终归属：

| 表现 | 尺寸 | 绿色冲击波 | 用在哪 |
|---|---|---|---|
| FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D` | 1.0 | **无** | 小僵尸 / 警察僵尸死亡（**未改版**） |
| FX01-17 `VFX-DEATH-BLAST-3D` | **2.0** | **有 3 层** | 胖子僵尸死亡 |
| FX01-20 `VFX-GOO-HIT-3D` | 0.50 | — | 命中僵尸三兄弟（枪击 + 近战） |
| FX01-21 `VFX-METAL-SPARK-HIT-3D` | 0.34 | — | 命中其余一切 |

## 怪种名单（本轮唯一的推断处）

`Enemy3D.ZOMBIE_KINDS = ["melee_chaser", "ranged_caster", "fat_zombie03"]` —— **一个名单挂三条口径**
（命中分流判据 / 死亡是否留尸体 / 死亡表现走哪支），避免拆成三份会各自漂移的别名。

| 业主叫法 | 逻辑 ID | 依据 |
|---|---|---|
| 小僵尸 | `melee_chaser` | `MonsterInjector.BASE_ENEMY_TYPES` 与 `Enemy3D` 的名字归一化 |
| 警察僵尸 | `ranged_caster` | `box_bridge_center.json` 注释 + `level_plan.json` 掉落备注 |
| 胖子僵尸 | `fat_zombie03` | 同上，且它是 FX01-17 那条路 |

## 路由（两条攻击方式、一个判据）

```
Projectile3D._spawn_hit_effect(collider, goo_size, metal_size, ctx, pos?)   ← 命中/吸收/反弹/落地/链电 五处
PlayerMeleeCombat3D._spawn_hit_feedback(target, result)                     ← 近战命中
        └── 共用判据：Enemy3D.uses_goo_hit_burst()  ← ZOMBIE_KINDS
                是 → FX01-20 绿方块爆开
                否 → 枪击走 FX01-21 金属火星 / 近战走 FX01-05（保留，非僵尸的肉不读作「金属」）
```

- `VFX-IMPACT-3D`（FX01-02）**命中路径已不再借它**，保留给「非僵尸怪种死亡爆点 / 护盾弹开」（静态门禁：
  `Projectile3D` 里不得再出现 `FX01_IMPACT`）。
- 近战非僵尸**刻意不换成金属火星**：那是「打墙」的读法，用在肉身上不对，且换了会让 FX01-05 变孤儿。

## 结构：两个共享件

| 件 | 作用 | 为什么 |
|---|---|---|
| `src/vfx/VfxGooDeathBase3D.gd` | 两条僵尸死亡链路的**共享身体**（FX01-19 / FX01-17 只覆盖 `_asset_id()` / `_asset_version()` / `_shockwave_enabled()`；尺寸由调用方给） | 两件本来就是同一套表现，只差两个旋钮；各抄 400 行会让节奏/配色/落地数学立刻漂移 |
| `src/vfx/ToonVfxBurst.gd` | 方块爆开 / 冲击波的**共享运动学**（纯静态函数：方向 / 尺寸比 / 尺度包络 / 外推包络 / 翻滚 / 冲击波生长 + 时间窗） | 三件（FX01-17/19/20）共用一支笔；确定性、无 `randf` |

⚠️ **共享身体是 v001 的逐字副本**（含抬高式俯仰、各处内联公式）——业主说「不要改变」，所以抽公共件时
既有观感零漂移。新件 FX01-20 走 `ToonVfxBurst`，用 `pitch_center = 0.15` 复刻同一形状。

## 几处非显然的坑（都踩过）

1. **`fmod` 循环相位让冲击波永不收尾** —— 相位是 `fmod(elapsed/period + i/n, 1)` 的循环，任何时刻至少
   有一层处在低相位（高 alpha）。不外加**时间窗**（`shockwave_window`），「到点收干净」永远不成立
   （实测 0.66s 仍亮，验收直接红）。
2. **量「生长」不能取「所有层里的最大 scale」** —— 三层相位错开，t=0 就已经有一层很大（实测 1.068），
   会把「起始」读成峰值、判据恒假。必须量**单层自己的** scale（快照给 `shockwave0_scale_x`）。
3. **抬高式俯仰让三维方向和的模长天然 ≈2.7** —— 「全向对称」判据必须只看**水平分量**，否则会把
   「一圈炸开 + 略微抬高」这个有意设计误判成缺陷。
4. **真渲染才发现的三处**：① 首版预览共用一台相机 + 一堵固定墙，墙卡在镜头与特效之间 ⇒ 四组里三组
   只剩一堵黑墙（机位改为逐组给）；② 金属火星张角 0.34 rad、长 0.22→0.78 ⇒ 两根几乎重叠、读成
   「一根小凸起」；③ 白方块切向占比 0.35~0.8、外推 0.30m ⇒ 5 颗挤成一坨。三处都只在实拍里现形。
5. **`streak_mesh` 长轴是本地 Z** ⇒ 朝向必须用 `Basis.looking_at`（对 -Z），写 `Quaternion(UP, dir)`
   会把火星转到天上；而 `scale.z` 就直接是米数（mesh 基准长 1.0）。

## 验收

| 测试 | 结果 |
|---|---|
| `verify_hit_routing_vfx`（新增） | ✅ `samples=26` |
| `verify_death_blast_vfx`（改按新设计） | ✅ `samples=12` |
| `verify_zombie_goo_death_vfx`（回 v001 + 开关两侧断言） | ✅ `samples=16` |
| `verify_fat_zombie03_death_visibility`（去倒地 / 无尸体） | ✅ |
| `verify_melee_zombie_death_visibility` | ✅ |

**开关的两侧证据**（最小探针实跑，同一共享基类、两个子类）：

```
PROBE vfx_death_blast_root_top3d.tscn      enabled=true  shockwave_count=3  version=v002
PROBE vfx_zombie_goo_death_root_top3d.tscn enabled=false shockwave_count=0  version=v001
```

⚠️ **未做到的一件事（如实记录）**：本轮想对「冲击波开关」再做一次**故意改坏**的反向对照
（把 FX01-17 的 `_shockwave_enabled()` 翻成 false，期望那条 `== 3` 断言变红），但连试三次都**仍是绿的**。
排查发现是**脚本缓存问题**：改完 `VfxDeathBlast3D.gd` 后直接跑场景，Godot 仍执行旧版本（加
`print("PROBE_SWITCH_CALLED")` 探针一次都没触发即为证），清 `global_script_class_cache.cfg` + 重跑
`--import` 也没解决。**结论**：开关机制本身是好的（上面的探针已证明两个子类确实各走一边），
但「故意改坏 ⇒ 变红」这条对照在本会话没验成，**不能声称它验过**。下次要补时，先确认
Godot 真的重载了被改的脚本（加探针 print 是最快的判据）。

## 真渲染证据

`outputs/combat_vfx_batch2/combat_vfx_batch2_timeline.png`（四组 × 各 5-6 帧时间轴）
＋ 各组原始帧 `outputs/combat_vfx_batch2/<组名>/`。

## 账本与文档

- 账本：新增《资产主表》r39 `VFX-GOO-HIT-3D`、r40 `VFX-METAL-SPARK-HIT-3D`；r36 `VFX-DEATH-BLAST-3D`
  升 v002 + SHA 重算；r38 `VFX-ZOMBIE-GOO-DEATH-3D` 备注订正为「未改版」；《3D-特效》FX01-20/21 新增、
  FX01-17 改版；域变更日志 `v0.1.22`；派生列/总览/数据校验范围 `$38 → $40`。
- 门禁 `check_asset_registry.py --ledger vfx`：`asset_count` 33 → **35**，`sha_mismatch` 仍为**既有 14 条**
  （r17–r21、r26–r34），本轮**新增 0 条**。
- 14.6 §2.2 目录索引 + 版本历史 `v003.6`；`MODULE_INDEX.md` 的 VFX-POOL 行；`feature_registry.json`
  的 `VFX-POOL.verification`；`scripts/run_verification_suite.sh` 的 `core_scenes`。

## 下次可能被问到

- **「受击还是太大/太小」** → 改 `Projectile3D.GOO_HIT_SIZE_TARGET` / `METAL_SPARK_SIZE_TARGET` 及各派生档，
  别动特效内部几何常量（那会连死亡件一起带动）。
- **「胖子死亡想要更大」** → `Enemy3D.FAT_DEATH_EFFECT_SIZE`（现在是 2.0 = 小僵尸的 2 倍）。
- **「小僵尸死亡也想要冲击波」** → 把 `VfxZombieGooDeath3D._shockwave_enabled()` 返回 true 即可
  （身体是共用的，一行就行）；对应验收的 `EXPECTED_SHOCKWAVE_COUNT` 也要同步改。
- **「自爆伤害范围对不上视觉」** → 现在是**有意的**：尺寸固定 2.0，不再按伤害半径反推。
  要恢复「视觉顶到伤害半径」就改回 `radius × 0.6`。
