# 打中怪物卡一下：材质 shader 变体开关的代价（及两个连带缺陷）

日期：2026-10-31。功能：ENEMY-AI / VFX / PERF。

业主两轮报单：

> ① 「进入远征03后，战斗打中怪物会卡顿，会是怎么回事？」
> ② 「我的观察是怪物只要受到伤害，就会进入卡顿一下的状态，衍生有没有其他同样类型的问题，深度检查一下」

第 ② 条把范围从"远征03"收敛到"受击路径"，也明确要求排查同类问题。本文按这个顺序写：
先量化，再定位，再修，再扫同类，再门禁。

---

## 零、结论

受击闪白用 `StandardMaterial3D.emission_enabled = true/false` 实现。这个属性在 Godot 里
**不是 uniform，是 shader define（`USE_EMISSION`）**：翻转它等于换 shader 变体、重建 GPU 管线。
闪白恰好是「受击翻上去、0.12 s 后翻回来」，下一发再翻 ⇒ **每打中一下就卡一下**。

| 项 | 改前 | 改后 |
|---|---:|---:|
| 命中帧相对空闲帧 | **+82 ~ +107 ms** | **+0.00 ms** |
| 单次翻 `emission_enabled` 本身 | **+98 ~ +107 ms** | 不再翻 |
| 受击闪白画面 | **完全不可见**（另有第二个 bug，见 §4） | 可见（luma 0.278 → 0.393） |
| 房间流送时的灯罩自发光 | 每盏灯每次进出翻一次 | 只推能量 |
| 基地灯开关的自发光 | 逐面翻 | 只推能量 |

改的是三处实现，方向一致：**「灭」用能量 0 表达，不用开关表达**。能量 0 与"自发光关闭"
出图逐像素等价（实测 `AB max pixel diff` 见 §3.3、能量 0.6→3.0 差异 0.706 说明通道本身通）。

---

## 一、先量化，不要凭"感觉卡"

现有探针都不覆盖这条：`_exp03_perf_probe` 只量整关装配与空转帧时（不命中），
`verify_3d_performance_budget` 跑的是塔楼、且不含受击路径。

新写 `tools/_exp03_hit_cost_probe.gd`，把一次命中拆成 7 个环节逐项计时，
再单独量「命中帧 vs 空闲帧」的整帧差值。

两个口径必须先钉死，否则读数会骗人：

1. **必须真渲染、必须 `--disable-vsync`**。开垂直同步时帧时被锁在 16.7 ms，
   尖峰直接被吃掉，全部读成 0（第一次就跑出这个假绿）。
2. **判据是差值不是绝对值**。窗口模式帧率会因为焦点/节流漂到 66 ms，
   绝对值毫无意义；`hit_p50 − idle_p50` 才是"命中这一下额外付了多少"。

### 1.1 环节计时（改前，真渲染）

| 环节 | first | p50 |
|---|---:|---:|
| `flash_hit()` | 0.02 ms | 0.02 ms |
| `hit_effect_anchor()`（AABB 现算） | 0.13 ms | 0.14 ms |
| 命中特效 `VFX-IMPACT acquire` | **70.11 ms** | 0.35 ms |
| 火星 `VFX-METAL-SPARK acquire` | 0.51 ms | 0.24 ms |
| 飘字 `VFX-DAMAGE-NUMBER acquire` | 1.25 ms | 0.96 ms |
| 受击音效 | 1.84 ms | 0.70 ms |
| 血条重绘 | 0.05 ms | 0.05 ms |
| `take_projectile_damage()` 全程 | 0.78 ms | 0.79 ms |

**这张表本身是会骗人的**：`flash_hit()` 只花 0.02 ms，因为它只是置一个计时器，
真正的材质翻转发生在**同帧稍后的 `_process`** 里；而 `take_projectile_damage()`
量到 0.79 ms 也只覆盖 CPU 侧脚本，管线重建在 GPU 侧、提交时刻不在函数体内。
⇒ 「函数级计时看不见卡顿」并不意味着没卡顿，必须量整帧。

### 1.2 整帧差值（改前）

```
FRAME_hit   p50=101.26ms
FRAME_idle  p50= 66.66ms     ← 窗口模式，帧率被压到这个档
GROUP full_hit  delta = +34.69 ~ +85.03ms（随窗口帧率浮动）
```

---

## 二、逐项排除，不要猜

`_probe_frame_groups()` 把命中帧多出来的时间分给各个动作，每个动作单独跑 120 帧配对采样。
**改前**（`--disable-vsync`，idle 16.66 ms）：

| 分组 | delta |
|---|---:|
| baseline（什么都不做） | −0.00 ms |
| 只放命中特效 | +0.00 ms |
| 只放火星 | +0.00 ms |
| 只放飘字 | +0.00 ms |
| 只播音效 | +0.01 ms |
| **只调 `avatar.flash_hit()`** | **+82.20 ms** |
| `take_damage()`（不含弹道分流） | +83.12 ms |
| **完整 `take_projectile_damage()`** | **+81.92 ms** |

⇒ 特效、飘字、音效、血条全部干净；**只有闪白那一支**。

---

## 三、假说与反证

### 3.1 假说

闪白写成：

```gdscript
material.emission_enabled = _flash_time > 0.0
material.emission_energy_multiplier = 0.6 * _flash_time / 0.12
```

`emission_enabled` 是变体开关 ⇒ 每帧受击都重建管线。

### 3.2 反证（A/B）

`_probe_material_switch()` 直接对同一份材质做三组对照：

| 分组 | delta |
|---|---:|
| `mat_emission_enabled_toggle`（翻开关） | **+98.55 ms** |
| `mat_energy_only`（只改能量） | −0.01 ms |
| `mat_energy_pulse(=fix)`（常开 + 能量在 0↔0.6 之间走） | +0.01 ms |

假说成立。**修法就是第三行**：出厂即 `emission_enabled = true`、能量 0，闪白只推能量。

### 3.3 为什么"能量 0"等于"关掉自发光"

不是推断，是量出来的：

```
AB max pixel diff (old vs new peak) = 1.125   ← 峰值时两份实现逐像素一致
energy 0.6 -> 3.0 max pixel diff   = 0.706   ← 证明这条通道确实影响画面
```

第一条说明新旧在峰值时画面相同；第二条说明这个通道不是死参数
（否则"画面没变"只能说明它本来就没生效）。

---

## 四、顺线查出：**闪白本来就完全不可见**

改完卡顿之后，实机仍"没有画面反馈"。逐像素量化（怪身平均亮度）：

```
FLASH_LUMA idle   0.2502
FLASH_LUMA flash  0.2595      ← 只涨 0.009，等于没闪
FLASH_LUMA after  0.2505
```

排查材质身份，发现受击写的是**孤儿材质**：

```
HELD 1 ids=[...8240133]
MESH enm_ranged_sporeshooter01_mesh  s=0 active=...3027445 override=...3027445 in_held=false
```

`_materials` 里只有 1 个对象，而渲染面用的是**另一个**对象。

### 4.1 成因

表现层 `_ready()` 里逐面 `duplicate()` + `set_surface_override_material()`，把副本收进
`_materials`。而 `EnemyAvatar3D._apply_formal_tint()` 在**之后**才跑，旧实现又
`duplicate()` 了一份**新的** override 盖上去：

```gdscript
var clone := base.duplicate() as BaseMaterial3D
clone.albedo_color = base.albedo_color * tint
mi.set_surface_override_material(surface, clone)   # ← 把表现层那份顶掉
```

于是表现层手里那批成了没人用的孤儿，场上渲染的那份从没被闪过。

**只在有染色项的怪种上发生**：`FORMAL_MODEL_TINT` 里只有少数几只（远征03 的 5 只远程怪全在，
所以那 5 只闪白一直是空的；用同一模型但没染色的怪正常）。这解释了为什么是"远征03 感觉特别怪"。

### 4.2 为什么所有既有验收都是绿的

| 验收 | 它查的 | 为什么漏 |
|---|---|---|
| `verify_melee_zombie_presentation` | `visual._materials[0].emission_enabled` | 查的**正是**那份孤儿，永远为真 |
| `verify_strong_variant_eye_glow` | 眼球材质 | 不是身体材质 |
| 其余表现类验收 | 动画/骨骼/尺寸 | 不碰闪白 |

⇒ 判据必须落在「`_materials` 里的对象 id == 渲染面上 `get_active_material()` 的 id」上。
这是唯一能区分"写给自己看"和"写进画面"的断言。

### 4.3 修法

`_apply_formal_tint()` 改为**复用面已有的 override**（就是表现层那份），只改 albedo；
原色取 `mesh.surface_get_material()`（资产原材质）而不是 `get_active_material()`
—— 后者会返回 override，重复调用会把色重复乘一遍。

---

## 五、同类问题深度扫描

业主第 ② 条要求扫同类。先建**属性代价表**（`tools/_material_variant_cost_probe.gd`，
单材质、真渲染、`--disable-vsync`）：

| 属性 | delta | 性质 |
|---|---:|---|
| albedo_color / emission_energy_multiplier / roughness | ≈0 | uniform，随便改 |
| **emission_enabled** | **+107.40 ms** | shader define |
| **transparency** | **+106.69 ms** | shader define |
| **vertex_color_use_as_albedo** | **+108.62 ms** | shader define |
| **no_depth_test** | **+105.32 ms** | shader define |
| **billboard_mode** | **+93.82 ms** | shader define |
| **depth_draw_mode** | **+86.22 ms** | shader define |
| **receive_shadows**（disable_receive_shadows） | **+76.71 ms** | shader define |
| **shading_mode** | **+19.46 ms** | shader define（较轻） |
| cull_mode | −0.00 ms | uniform |
| `GeometryInstance3D.transparency`（实例级） | +0.01 ms | uniform |
| `GeometryInstance3D.cast_shadow` | −0.00 ms | 不是变体 |

⇒ **8 / 15 是昂贵的**。规律与 Godot 源码一致：进 `MaterialKey` 的位才是变体。
注意 `shading_mode` 只有 19 ms（变体已预热？）而 `cull_mode` 完全不贵 —— 所以不能按
"听起来像不像结构属性"猜，必须量。

### 5.1 全仓扫描结果

`grep '\.emission_enabled = '` 共 80 处。逐处按「是否**运行时反复翻转**」分类：

| 类 | 处置 |
|---|---|
| **运行时反复翻转（必须改）** | 3 处，见 §5.2 |
| 建成时设一次、之后不变（安全） | 绝大多数（灯具初始态、VFX 材质在 `_build_*` 里设一次） |
| 只在事件里翻（可接受） | `VfxBoardDebris3D`（暗门打碎一次）、`BaseLampDynamics3D` 的启动序列（一次） |
| 用户手动操作才翻 | `BaseLampDynamics3D._set_self_owned_emission`（按一下开关一次，已改） |

另外 `transparency` / `vertex_color_use_as_albedo` / `no_depth_test` / `billboard_mode` /
`disable_receive_shadows` 的赋值点也都扫了：全部在**材质创建时**（`_make_material()` 一类），
不在运行时翻转。唯一例外是 `HologramCity3D` / `RogueMapSelectMenu` 的渐显渐隐 ——
它们用的是 `GeometryInstance3D.transparency`（实例级 uniform，实测 0.01 ms），命中"安全"。

### 5.2 改掉的三处

| 位置 | 原来 | 现在 |
|---|---|---|
| `melee_chaser` / `ranged_caster` / `fat_zombie03` 的 `_formal_visual.gd` | 每次受击翻 `emission_enabled` ×2 | `HitFlashMaterial3D` 只推能量 |
| `WastelandLight3D._update_lens_state()` | `emission_enabled = light_enabled and _runtime_active`，**每次房间流送状态切换**逐灯调用 | 能量取 `LENS_EMISSION_ENERGY` 或 0 |
| `BaseLampDynamics3D._set_self_owned_emission()` | 按灯开关时逐面翻 | 只推能量，开关语义记 `_self_owned_allowed` |

### 5.3 一个必须显式声明的取舍

`BaseLampDynamics3D.are_self_owned_lit()` 原来读 `emission_enabled`，改后读
`_self_owned_allowed`（新增的授权位）。**不能改读能量**：屏幕面的常态能量本来就是 0
（只在事件里闪），拿"能量 > 0"当判据会恒为 false，`verify_base_lamp_dynamics` 的 N10/N12 立刻红
（第一版就这么红过）。

---

## 六、顺带修的语义缺陷

三个 `_formal_visual.gd` 原来都把闪白时长写成字面量 `0.12`，而 `_process` 里除的是
`_flash_time / 0.12`。现在收敛成一个 `FLASH_DURATION` 常量 —— 改一处不会再出现
"时长变了但强度曲线没跟着变"。

`HitFlashMaterial3D.prepare()` 会在打开自发光之前**记下原始 emission 色与能量**，
闪白是叠加而不是覆盖。理由是正式模型里有本来就该常亮的件（强化怪眼球发光件），
无条件写 0 会把它们一起灭掉 —— 那是"修卡顿顺手改坏美术"。

---

## 七、验收

| 项 | 命令 | 结果 |
|---|---|---|
| 全项目编译 | `godot --headless --path . --quit-after 200` | SCRIPT ERROR 0 |
| 命中帧（真渲染） | `_exp03_hit_cost_probe.tscn --disable-vsync` | `HIT_COST_OK 命中帧额外耗时 0.00ms（阈值 3.0ms）`；改前 +82 ~ +107 |
| 闪白可见性 | 同上（逐像素亮度） | idle 0.278 → **flash 0.393** → after 0.280，两条断言都过 |
| **闪白绑定门禁（新）** | `_hit_flash_binding_probe.tscn` | `FLASH_BINDING_OK checks=30 failures=0` |
| 属性代价表（新） | `_material_variant_cost_probe.tscn --disable-vsync` | 昂贵项 8 / 15，清单见 §5 |
| 近战僵尸表现 | `verify_melee_zombie_presentation` | `MELEE_ZOMBIE_PRESENTATION_OK` |
| 强化怪眼球 | `verify_strong_variant_eye_glow` | `EYE_GLOW_OK (samples=36)` |
| 基地灯动态 | `verify_base_lamp_dynamics` | `ACCEPT base_lamp_dynamics`（N1~N12 全过） |
| 敌人行为流 | `verify_3d_enemy_behavior_flow` | `3D_ENEMY_BEHAVIOR_FLOW_OK`（连跑 3 次稳定） |
| **非材质开关表（新）** | `_runtime_switch_cost_probe.tscn --disable-vsync` | 昂贵项 1/15（只有阳性对照） |
| **生成代价门禁（新）** | `_enemy_spawn_cost_probe.tscn --disable-vsync` | `SPAWN_COST_OK`（同类第二次 1~2 ms） |
| **特效冷启动（新）** | `_vfx_cold_start_probe.tscn`（默认 / `-- --prewarm`） | 134.6 ms → **2.2 ms** |
| 全仓变体赋值点 | `python3 scripts/audit_variant_switch_sites.py --hot` | 150 处 / 8 处疑似，逐条核实无真实热路径 |

### 7.1 反向自证（门禁真的会红）

- `_hit_flash_binding_probe`：把 `_apply_formal_tint()` 改回旧写法（无条件新 `duplicate()`）
  → `FLASH_BINDING_FAILED checks=30 failures=1`，点名
  `egt_bullet_kin: 只有 0/1 份材质真的挂在渲染面上`。还原复绿。
- `_exp03_hit_cost_probe`：改前 +82~+107 ms 报红路线已被实测走通（§2、§3.2 的表就是它抓出来的）。

### 7.2 两条断言语义已换口径（必须记）

| 断言 | 原判据 | 现判据 | 理由 |
|---|---|---|---|
| `verify_melee_zombie_presentation` "hit flash missing" | `_materials[0].emission_enabled` | `_materials[0].emission_energy_multiplier > 0.1` | 开关常开后原判据恒真，等于没验 |
| `verify_strong_variant_eye_glow` "fat body must not emit in idle" | `not emission_enabled` | `is_zero_approx(emission_energy_multiplier)` | 同上：常开 + 能量 0 才是"不亮" |

这两条**不是放宽阈值**：新判据比旧判据严格（旧的在修好后恒真）。

---

## 八、探针自身踩的坑（防重犯）

1. **`--script` 模式加载不了 autoload** ⇒ `Enemy3D.gd` 里引用 `MonsterAIManager` 直接编译失败。
   一律用 `--scene` 跑。
2. **headless 下材质变体根本不重建** ⇒ 同一个 bug 逐项读 0.0 ms、全绿。
   所以 `_exp03_hit_cost_probe` 在 headless 下**只打印不判**，并明确输出
   `HIT_COST_SKIP_HEADLESS`，不许假装验过。
3. **探针自己关掉了被测对象的 `_process`**：`_probe_parts()` 为了计时干净把怪
   `set_process(false)`，后面的帧尖峰组全在"什么都没跑"的状态下测 —— 假绿。
   现在 `_probe_frame_groups()` 开头显式恢复，并在注释里写明原因。
4. **哨兵值不能拿 0 当"没量到"**：修好后差值本来就是 ≈0（甚至 −0.00），
   用 `-1` 当初值会把已修好的结果误判成"没跑"。现在用 `-999`。
5. **截图要定格在峰值**：`flash_hit()` 之后等两帧再截，强度已经掉到 45%，
   出图会读成"闪白很弱"。改成手动 `_process(0.0)` 推一次再截。
6. **美术资产脚本里不要写裸全局类名**（`HitFlashMaterial3D.xxx`）：资产脚本可能被单独
   实例化（编辑器预览 / 探针 / 离线出图），那时 `.godot` 全局类缓存不一定扫到新脚本，
   报 `Identifier ... not declared`，而报错发生在解析期 —— 表现为"闪白整段消失、怪一动不动"。
   改用 `const HitFlash := preload(...)`。

---

## 九、第二轮：把「同类」扫干净

业主第二轮报单：「都深度检查一下，然后修复掉」。上一轮只修了受击闪白，这一轮做四件事：
① 把**非材质**的运行时开关也量一遍（不能假设只有材质贵）；② 用脚本**穷举**全仓变体赋值点，
不靠人工 review；③ 顺着这条线继续挖出两个更基础的代价（管线缓存、场景弱引用）；
④ 把命中前第一次要付的冷启动整体挪到加载期。

### 9.1 非材质开关：全部便宜（但必须有阳性对照）

新探针 `tools/_runtime_switch_cost_probe.gd`（真渲染 / `--disable-vsync`）：

| 开关 | delta |
|---|---:|
| 点光 / 平行光 `shadow_enabled` | −0.01 ms |
| 点光 `visible`、`light_energy` | −0.01 ms |
| `Label3D.font_size` 116↔134（飘字每发都在改） | +0.01 ms |
| `Label3D.outline_size`、`text`、`transparency` | +0.01 ms |
| `material_override` 换一份、`mesh` 换资源 | +0.01 ms |
| `MeshInstance3D.visible` | +0.00 ms |
| `albedo_texture` / `emission_texture` 有↔无 | −0.01 ms |
| **`emission_enabled`（阳性对照）** | **+100.19 ms** |

**阳性对照是这一节的合法性来源**：如果整张表都读 0，无法区分"真的便宜"和"探针测不出东西"。
所以同一份材质上翻一次已知昂贵的 `emission_enabled`，确认探针有效后才认其余读数。

⇒ 结论：**只有材质变体这一类贵**。灯光、文字、实例开关、贴图有无都不需要改。

### 9.2 全仓穷举：`scripts/audit_variant_switch_sites.py`

人工 review 150 个赋值点必然漏，所以用脚本按**所在函数**分类（建材质时一次 vs 运行时翻转）：

```
变体属性赋值点：150 处（其中疑似运行时翻转 8 处）
扫描范围：src, scenes, assets/art（跳过 tests/tools）
```

8 处"疑似热路径"逐条核完，**没有一处真的在翻材质**：

| 位置 | 真相 |
|---|---|
| `BaseFacility3D._apply_material()` / `DungeonEntrance3D._apply_material()` | 材质工厂，只在建场景时跑 |
| `Base99Radio3D._update_feedback()` | 每次交互跑一次，且写的是 `true`（值相同 ⇒ setter 提前返回，不重建） |
| `HologramCity3D._update_staging()` / `RogueMapSelectMenu._apply_transition()` | 改的是 `GeometryInstance3D.transparency`（实例级 uniform，实测 −0.00 ms） |
| `VfxDamageNumber3D._on_tick()` / `VfxHealNumber3D._on_tick()` | 改的是 `Label3D.transparency`（同上，实例级） |

其余全在 `_build()` / `_make_material()` / `_material()` 这类创建期函数里，
`VfxExplosion3D` / `VfxMeleeImpact3D` / `VfxMeleeSlash3D` 那几个由 `if _xxx == null` 守住，池化后只跑一次。

> 脚本第一版把 `tests/`、`tools/` 也数了进去（报 150 处虚高）—— 原因是拿 `"/tests/"` 匹配
> Windows 的反斜杠路径永远失败。改成按 `Path.parts` 比较。这条记在脚本注释里。

### 9.3 更基础的代价一：管线缓存**跟着材质一起消失**

上一轮量到"翻 `emission_enabled` 要 100 ms"，这一轮问了一句「那这 100 ms 能复用多久」，
答案是**只要那份材质还活着**：

```
第一次        101.15 ms    ← 编译
第二次          0.15 ms    ← 旧材质还在（即使是另一个材质实例）
全释放后再建    96.41 ms    ← 缓存跟着最后一个使用者一起没了
再建            0.15 ms
```

后果不是"偶尔卡一下"，而是**每只怪都要重编译**。实测 `EnemyAvatar3D._rebuild()` 每次新建
`_shell_material`（无自发光）、`_core_material`（有自发光）、预警环（ALPHA + 自发光）：

| 怪种 | 每次 `configure()` |
|---|---:|
| summoner / shielded / exploder（程序化壳） | ~200 ms |
| melee_chaser / ranged_caster（正式 GLB） | ~310 ms |
| 同一段在 headless | 2 ms（不编译管线，所以无渲染验收永远看不见） |

**修法**：`src/enemy3d/MaterialPipelineKeeper.gd` —— 按变体签名留**一份长命引用**，
之后任何新实例都命中缓存。签名只取进 `MaterialKey` 的位（透明、着色模式、自发光开关、
贴图有无、顶点色、billboard、深度…），不含颜色/能量这些 uniform。

⚠ 有一个顺序陷阱：闪白 `prepare()` 会把 `emission_enabled` 从 false 翻成 true，
**必须先翻再登记**。先登记等于登记了一个已作废的签名，真正在用的变体没人留 ——
实测正式 GLB 怪因此仍然每只 105~118 ms（修好后 1.5 ms）。

它不改渲染：各实例仍用自己的那份材质、仍各自改颜色，留住的只是引用。

### 9.4 更基础的代价二：`load()` 拿不到稳定引用，每只怪重读盘

同一个探针里，正式 GLB 怪的 `add_child` 拆开是：

```
FORMAL_SPLIT load=118 instantiate=0 add=0
```

**`load()` 本身 100~118 ms，而且每次都这样**。原因是 Godot 的资源缓存是**弱引用**：
场上最后一只 `melee_chaser` 被回收后，那份 `PackedScene` 就没人持有，下一次生成从磁盘重新解析。

**修法**：`EnemyAvatar3D._cached_scene()` —— `static` 字典持有 PackedScene（首次用到才留，
不用 `preload`，避免启动时把三种 GLB 全读进内存）。正式模型 / Boss / 精英三条路径都走它。

### 9.5 效果（`tools/_enemy_spawn_cost_probe`，依次生成 3 次）

| 怪种 | 修前（第 1/2/3 次） | 修后 |
|---|---|---|
| summoner | 235.8 / 1.0 / 1.0 | **240.2 / 1.0 / 1.3** |
| shielded | 0.9 / 1.0 / 1.1 | 1.1 / 0.9 / 0.9 |
| melee_chaser | 125.3 / **108.2 / 106.7** | **118.8 / 1.9 / 1.3** |
| ranged_caster | 122.3 / **113.3 / 113.2** | **16.8 / 1.5 / 1.6** |
| fat_zombie03 | 23.2 / 8.0 / 8.0 | 23.7 / 1.5 / 1.7 |

**第一次见某怪种仍要付一次冷成本**（读盘 + 变体编译），这是允许的一次性开销；
关键是**同类第二次起从 100~300 ms 降到 1~2 ms**。一间房 10 只怪，从 1~3 秒降到"一只的量"。

反向自证：把 `_cached_scene()` 改回裸 `load()`，门禁立刻红并点名
`melee_chaser 第 2 次生成仍要 108.2ms`、`ranged_caster 113.3ms`。还原复绿。

### 9.6 把第一次的冷成本也挪走：VFX 池预热

上一轮只报告了"第一次命中要 65 ms"，这一轮做成修复。

新探针 `tools/_vfx_cold_start_probe.gd`（两种口径，同一进程只能冷一次，所以跑两遍对比）：

```
默认        COLD_TOTAL 134.6ms（11 种）  WARM_TOTAL 5.1ms
--prewarm   PREWARMED_TOTAL  2.2ms（11 种）
```

拆解（顺带纠正了上一轮的一个说法）：**贵的不是"画"，是"节点带材质进渲染场景"**。

```
instantiate 0.04 / add_child 0.01 / activate 64.36 / 首帧渲染 14.68
摆在相机背后（必被视锥剔除、根本不绘制）⇒ activate 仍 64.65ms，第二次 0.37ms
单独 new 一个同款 StandardMaterial3D ⇒ 0.03ms
```

⇒ `VfxPool3D.prewarm(ids)`：逐帧把每个特效**造一次**（不是画一次），摊到 8~11 帧；
由 `ExpeditionLoadingScreen._finish_loaded_scene()` 在加载页背后调用，
`VfxPool3D.COMBAT_PREWARM` 覆盖"第一次打中 / 第一枪 / 第一刀 / 第一杀"要用的 11 件。

三个死亡件（`ZOMBIE-GOO-DEATH` / `EXPLOSION` / `DEATH-BLAST`）必须算进来：第一次打死怪
就在第一次命中后几秒；不过实测它们在其余件之后已经是热的（同一变体族），排进去只是保险。

headless 下**不预热**：那边没有管线可编译，而测试会断言特效池的绝对计数
（`verify_3d_melee_feedback_flow` 就查 `active_count(...) != 1`），插 8 个预热实例只会造假红。

### 9.7 顺带修掉一条既有竞态（不是放宽阈值）

`verify_3d_enemy_behavior_flow` 的「受伤必须产生 3D 飘字」判据是
`_count_damage_numbers()` 前后比较，而飘字退池与新建**可能落在同一帧** ——
旧的这一帧退、新的这一帧进，前后相等 ⇒ 假红。实测同一份代码连跑两次一次红一次绿
（`Enemy damage does not create a 3D floating number: boss`）。

修法：取基准前先等已有飘字自然退池（上限 120 帧），把基准固定到 0 上。
判据仍是"必须多出一个"，没有放宽。修后连跑 3 次全绿。

## 十、没做的事

- **没有逐只复刻怪实测**。33 只借三种正式 GLB，验的是三种基类 + 三只实际别名；
  别名解析本身由既有 `_egt_monster_registry_probe` 覆盖。
- **没有量 `transparency` 类改动的性能收益**。全仓扫下来它们都在创建期设置，不在热路径，
  没有可改的点。
- **`ConEmissive` 类"只在事件里翻"的没动**（暗门碎片、启动序列）。它们的翻转次数是 1~2 次/局，
  单次 80~100 ms 在一个过场里可以接受；要改需要先确认"碎片出来后自发光是否必须彻底关掉"。
- **`verify_monster_ai_system_complete` 仍 2 条既有红项**（令牌预算 `1/0`、melee token 不复用），
  与本次无关（HEAD 同红，10-31 记录已登记）。
- **`probe_expedition03_playable` 仍 1 条既有红项**（`落门之后没有刷怪（hub_01）`）。
  本轮用回退版脚本对照跑过，红项逐字相同 ⇒ 与本次改动无关。
- **每一只"首次见到"的怪仍要付 100~300 ms**（读盘 + 变体编译）。要彻底消掉得在加载期
  预生成一次各类怪（会牵动 AI / 注册 / 碰撞，风险高于收益，本轮没做）。`_cached_scene()`
  之后它已经**只付一次**，而不是每只都付。
- **AudioManager 每次命中新建一个 `AudioStreamPlayer`**（0.70 ms/发）。在预算内，没动；
  高射速武器若将来堆出问题，这里可以做 voice pool。
- **`shading_mode` 的 19 ms 没深挖**：它比其他变体便宜一个数量级，怀疑是变体已预热，
  没有成本压力就没有再研究。
- **`MaterialPipelineKeeper` 只覆盖怪**（`EnemyAvatar3D` 与三份正式表现脚本）。
  武器、基地灯具、交互件的材质也是"每实例新建"，理论上同样每实例重编译一次；
  它们生成频率远低于怪，没有量到痛点，本轮没扩。
