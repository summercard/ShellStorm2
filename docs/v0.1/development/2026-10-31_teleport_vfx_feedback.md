# 2026-10-31 怪物瞬移的「消失 / 出现」位置反馈（FX01-34 / FX01-35）

> 业主原话：「带有瞬移还有位移的一些怪物，它的这个**出现消失的那个位置**需要有一些反馈特效，
> 这些特效要记录到账本里面去，帮我做简单的这个特效……不然的话那怪物**突然消失出现很奇怪**。」

---

## 1. 先查清楚：到底谁在"凭空换位"

远征03 的 33 只复刻怪里，会不经过任何中间帧就换位置的只有两组，且都写在同一处代码：

| 行为 | 实现 | 触发者 | 参数 |
|---|---|---|---|
| `blink` 瞬移 | `Enemy3D._blink_to_random()` 直接改 `global_position` | `egt_hollowpoint` 空尖弹 | `interval 5.0` / `radius 7.0` / `cooldown 2.5` / 前摇 `0.35 s` |
| | 同上，但由出手触发 | `egt_gunjurer` 枪法师 | `on_attack: true` / `after_attack_delay 0.12` |
| `vanish` 蒸发 | `Enemy3D._vanish()` → `_die()` | `egt_keybullet_kin` / `egt_chance_kin` | 逃跑超时 `vanish_after 11.0 s` |
| | 同上 | `egt_gripmaster` 抓握大师 | 连抓空 `max_grab_misses 3` 次 |

**修前唯一的反馈是 `avatar.flash_hit()` 闪白一下**（`_begin_blink_telegraph` 里）。
0.35 s 后模型原地消失、在 7 m 外出现 —— 玩家读到的是"模型抖了一下，然后它就没了"。

`egt_spirat` 的 `_tick_rush_reposition()`（冲撞途中 3 次重定向）**故意没接**：
它是连续、有轨迹的位移，从没"消失"过。给它播瞬移特效会让玩家误判它有传送能力。

---

## 2. 做了什么

### 2.1 两件特效，共用一个脚本

`src/vfx/VfxTeleport3D.gd`（导出项 `mode = out | in`）：

| | FX01-34 `VFX-TELEPORT-OUT-3D` | FX01-35 `VFX-TELEPORT-IN-3D` |
|---|---|---|
| 时长 | **0.22 s** | **0.26 s** |
| 环 | 1.35 → 0.15 倍（**内向收拢**，"被抽走"） | 0.15 → 1.50 倍（**向外炸开**） |
| 亮芯 | `(1−t)` 一路缩没 | `sin` 在 35% 处弹到最大再收 |
| 竖丝 | 7 根，0.62 → 0.20 m，**向上抽离**变短 | 7 根，0.20 → 0.75 m，**向上冒出** |
| Prefab | `assets/art/vfx/combat_3d/vfx_teleport_out_root_top3d.tscn` | `.../vfx_teleport_in_root_top3d.tscn` |

**为什么拆两件而不是一件带参数**：

1. `VfxPool3D` 按 `asset_id` 分桶 —— 合并会让"消失"和"出现"抢同一批实例；
2. 账本按 AssetID 一行一件，要能分别查用量；
3. 两者时间曲线方向相反（收拢 vs 炸开），参数没法共用。

**成本控制**：程序几何（复用 `ToonVfxGeometry` 的 ring / core / streak），不引贴图、不引 Blender 产物、
**不挂灯**（unshaded 自发光 —— 塔内夜间光下也看得见，这和 FX01-02 同一口径）。

**颜色**取调用方传入的单位色（`EnemyAvatar3D.COLORS[enemy_kind]`），于是空尖弹是紫环、
枪法师是浅紫环 —— 玩家顺带能读出"是谁闪的"。

### 2.2 接入点：位移两端各播一件

```gdscript
# _blink_to_random() 成功分支
global_position = Vector3(target.x, origin.y, target.z)
_play_teleport_fx(origin, global_position)   # ← 新增

# _vanish()
_vanish_requested = true
_spawn_effect_at(VfxPool3D.FX01_TELEPORT_OUT, TELEPORT_FX_SIZE, ...)  # ← 新增，只播 OUT
_die()
```

`_vanish()` **不播 IN**：那是真的离场，播"出现"等于骗人。
`_blink_to_random()` 四次都落不进空地时**两端都不播**（原地不动，播了就是假信息）。

### 2.3 一个必须分出来的接口：`_spawn_effect_at()`

原来的 `_spawn_effect(asset_id, size)` 只会用 `global_position`。但位移是**直接改 transform** 的，
函数返回时 `global_position` 只剩**落点**，原点已经丢了 —— 硬用它就只能在落点连播两件，
等于没表达"从哪走的"。

所以拆成：

```gdscript
func _spawn_effect(asset_id, size) -> void:
    _spawn_effect_at(asset_id, size, global_position + Vector3(0, EFFECT_SPAWN_LIFT, 0))

func _spawn_effect_at(asset_id, size, world_position) -> void:
    ...   # 原实现，只是坐标改为参数
```

---

## 3. 门禁

新增 `tools/_egt_teleport_fx_probe.tscn`（`.gd` 同名）。它验**三层**，少一层都不算做完：

| 层 | 断言 |
|---|---|
| ① 资产 | 两个 AssetID 在 `VfxPool3D._REGISTRY` 里、能实例化、`FX01_TELEPORT_*` 常量值与字符串一致 |
| ② 预制件 | `mode` 对、时长 0.22/0.26、竖丝 ≥ 4 根、**无灯**、**不投影**、`metadata/asset_id` 一致；**并且环的时间方向确实相反**（OUT 递减 / IN 递增） |
| ③ 链路 | 让真的 `egt_hollowpoint` 跑一次 `_blink_to_random(6.0)`：位移 > 0.5 m、OUT/+1、IN/+1、**池里真有活跃实例**；再让 `egt_keybullet_kin` 跑 `_vanish()`：OUT/+1 且 `ai_state == "dead"` |

**为什么第 ② 层要验方向**：两件共用一个脚本，把 `mode` 判反了照样实例化成功、照样"有几何"，
但视觉上会变成"消失时炸开"。只测"能实例化"抓不到。

**为什么第 ③ 层要看池子而不是只看计数器**：枪法师的 `blink.on_attack` 曾经**静默失效两天**
（配置写了、代码没消费点）。计数器只能证明"我这条路径跑了"，池里的活跃实例才能证明"特效真的进了场景"。

**反向自测**（已执行）：把 `_play_teleport_fx(origin, global_position)` 换成 `pass`，4 条同时报红：

```
EGT_TELEPORT_FX_PROBE_FAIL  共 4 项：
  - 瞬移时没有播「消失」特效（计数 +0）
  - 瞬移时没有播「出现」特效（计数 +0）
  - VfxPool3D 的 VFX-TELEPORT-OUT-3D 活跃桶是空的：特效被丢弃了
  - VfxPool3D 的 VFX-TELEPORT-IN-3D 活跃桶是空的：特效被丢弃了
```

还原后 `EGT_TELEPORT_FX_PROBE_OK`。

### 3.1 探针自己踩的两个坑（会重犯，已写进项目记忆）

1. **`VfxPool3D.create_unpooled(id)` 的返回值是 `Node`，只丢弃引用不会回收**。
   第一版在"存在性检查"里直接 `if create_unpooled(id) == null:`，于是每次跑完都打印
   `Leaked instance: Node3D - Node path: (空)` + `resources still in use: VfxTeleport3D.gd`。
   本项目验收套件把**退出时资源泄漏算红（exit 4）**，探针自己制造的泄漏必须先自己收干净（`probe.free()`）。
2. **`queue_free()` 排在帧末，而 `quit()` 不等最后一帧** ⇒ 场地/测试怪要用 `free()` 立即销毁。

---

## 4. 账本与文档

| 位置 | 改动 |
|---|---|
| 特效账本《资产主表》 | 新增 r54 `VFX-TELEPORT-OUT-3D`、r55 `VFX-TELEPORT-IN-3D`（含 SHA-256：两个 Prefab 的 sha256） |
| 特效账本《3D-特效》 | 新增分组行「▼ 01 战斗反馈（续）· 怪物位移表现（瞬移 / 消失）」+ FX01-34（r55）、FX01-35（r56） |
| 特效账本《总览》 | 区间 `$6:$53 → $6:$55`，**共 8 处**：A6/C6/E6/G6 + B10/C10/B11/C11（后四条是 SUMPRODUCT 分类统计，第一次漏改，被 `check_asset_registry` 抓出来） |
| 特效账本《域变更日志》 | 新增 `v0.1.30` |
| 基线 | `assets/registry/ledger_split_baseline.json` 追加两个 AssetID，`asset_count 1415 → 1417`、特效 `38 → 40`；脚本 `scripts/refresh_ledger_baseline_teleport_vfx.py` |
| 规范 | `14.6_特效系统与制作规范.md` 新增 §3.10 + 版本记录 `v003.13` |
| CHANGELOG | 见同日条目 |

**账本门禁**：

- `tools/asset_pipeline/verify_ledger_split.py` → `LEDGER_SPLIT_VERIFY_OK assets=1417`，`failure_count 0`。
  顺带把「`3D-特效` 页早已漂移但未刷基线」（`moved_sheet_mutated`，今天上午跑的时候就已经红）一并落回基线。
- `scripts/check_asset_registry.py`：23 条 → **17 条**。清掉的 6 条全是本次引入或本次可修的
  （2 条 `missing_sha` = 新行没填 SHA；4 条 `overview_formula_scope_wrong` = 总览区间没扩）。
  剩余 17 条是 `scenes` / `props` 的既有 SHA 漂移（`ENV-BASE99-ART-LAYOUT-3D`、`ITM-PICKUP-BASE-GROUND-ITEM` 等），
  **不是本批路径**，属另一条工作线正在改场景文件。

---

## 5. 回归

| 验收 | 结果 |
|---|---|
| `tools/_egt_teleport_fx_probe` | **OK**（三层全过） |
| `tools/_egt_ai_flow_probe`（32 只逐只） | OK（见同日 AI 节奏那份记录） |
| `verify_3d_enemy_behavior_flow` | **OK** |
| `probe_expedition03_playable` | **PLAYABLE_OK** |
| `verify_ledger_split` / `check_ledger_refs` | OK |

---

## 6. 未做 / 留给后续

1. **没有真渲染截图**。本轮是 headless 验收（几何/时长/方向/链路都对），但"看起来够不够、会不会太亮"
   得真渲染才知道。要补的话：跑一次远征03，让空尖弹闪一次，前后各截一帧对比。
2. **没有音效**。瞬移现在只有视觉。要加的话是音效账本的新件（`SFX-`），不在本轮范围。
3. **`egt_spirat` 的中途重定向**没接任何新表现（理由见 §1）。若业主觉得它"飘"，那是**有轨迹的连续转向**，
   该做的是转向拖尾/速度线，不是传送特效。
4. **其余关卡**没接 —— 塔楼怪没有任何 blink / vanishing，同一套代码但走不到这两个入口。
