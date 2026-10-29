# 远征03 复刻怪（EGT 第一层）落地记录

日期：2026-10-29
范围：远征03 怪物层第一批 12 只 + 攻击方式 + 占位资产套用
上级设计：[怪物设计 §T1—§T4](../design/怪物设计.md)
数据来源：[第一层怪物数据表](../reference/挺进地牢/第一层怪物数据表.md)

---

## 1. 业主指令与我的理解

原话要点：

> 把这份怪物列表按新怪物的数据填入怪物设计文档，标注为远征03的怪物。
> 然后使用现有怪物资产进行套入。先把基础的这些怪物做出来，包括怪物AI和攻击方式等。
> 后期再更换美术资产。制作前要阅读总文档，查看模块约束和整体施工逻辑。

拆成四件可验收的事：

| # | 任务 | 验收方式 |
|---|---|---|
| 1 | 数据进设计文档，且标明「远征03」 | 文档 §T1 表，含 EGT 原始血量与换算后 3D 值两列 |
| 2 | 用现有资产套入 | `EnemyAvatar3D.PROXY_ASSET_KIND` 别名表 + 探针断言每只都映射到合法基类 |
| 3 | 做出基础怪物（AI + 攻击） | 12 只全部可生成、可攻击、行为键齐备 |
| 4 | 美术后期换 | 数值/AI/行为键与资产解耦，换模型不动数值 |

---

## 2. 先读的约束（这是这次做得比上次稳的原因）

| 文档 | 读到的硬约束 | 对本次决策的影响 |
|---|---|---|
| `02_技术架构总则` §4/§5/§8 | 五层结构、模块六项契约、依赖方向 | 怪种定义进数据层（`MonsterInjector`），AI 进领域层（`Enemy3D`），资产别名进表现层（`EnemyAvatar3D`），三层不互相写 |
| `06A_怪物AI设计` §3.1 | **「参数只改变数值时复用同一策略」**，只有改输入事实/行动拓扑/目标类型/阶段结构才允许新策略 ID | 12 只里 7 只纯参数复用；只有 4 项行为（分裂/全向喷/自杀冲撞/辅助）是新策略，且逐条写了理由 |
| `触发器刷怪设计` §0 | 4 入口 / 3 旁路 / 1 出口；**实例化出口只有一个** | 死亡分裂**不自己 new 敌人**，改走 `_reserve_room_spawn()` 这条既有旁路 |
| `怪物设计` 开头 | 所有怪共用 0.30–0.60 s 启动过程（转身→吼叫→图标） | 未改动，12 只新怪自动继承 |
| `远征关卡03设计` §8.2 | 已知遗留要如实登记 | 新增 §8.3，把「当前走的是兜底池、不是手作编排」写成显式缺口 |

---

## 3. 关键决策：血量不能照抄

EGT 第一层血量 1~100，Boss 700~950。直接搬会崩，因为：

- EGT 玩家武器成长陡，我们的塔楼结构敌人与武器**不同步**；
- EGT 的 1 血怪（Blobulin/Bullat）在 3D 里需要至少两发才有打击感。

采用幂律换算（文档 §T0.2 有完整推导）：

```
hp_3d = clamp( round( 42 × (egt_hp / 15) ^ 0.72 ), 6, 200 )
```

指数 `0.72 < 1` 是**压缩高端**：EGT 6.7 倍的血量差在我们这里只体现 3.9 倍。
基准点选 `Bullet Kin 15 ↔ melee_chaser 42`，因为两者都是各自游戏里"最基础的杂兵"。

换算结果保留了 EGT 的**分档结构**（这是要抄的）而非绝对值（这是不能抄的）：

| EGT 档 | EGT 血量 | 我们 3D 基线 | 倍率 |
|---|---|---|---|
| 杂兵 | 1–5 | 6–19 | 1× |
| 标准 | 10–18.8 | 31–42 | 1.8× |
| 精英级 | 22.5–40 | 56–85 | 3.1× |
| 重型 | 90–100 | 153–165 | 6.4× |

---

## 4. 代码改动清单

| 文件 | 改了什么 |
|---|---|
| `docs/v0.1/design/怪物设计.md` | 新增 §T0–§T4：前提、怪种表、攻击规格、资产套用、施工状态 |
| `docs/v0.1/design/远征关卡03设计.md` | 新增 §8.3 怪物层指路与已知缺口 |
| `src/map/MonsterInjector.gd` | `BASE_ENEMY_TYPES` +12 行；`ENEMY_PRESENTATION` +12 行；新增 `generate_split_child()`；`_get_available_types_for_level()` 支持关卡池 |
| `src/enemy3d/Enemy3D.gd` | `PROFILES` +12 行（含 `volley`/`death_split`/`death_burst`/`suicide_rush`/`support_buff` 键）；新增 10 个函数；`_perform_attack` +5 组分支；`_die()` 挂死亡行为；`_physics_process` 挂连发/buff/冲撞 tick |
| `src/enemy3d/EnemyAvatar3D.gd` | `PROXY_ASSET_KIND` 别名表 + `resolve_asset_kind()`；`configure()` 与 `get_footprint_profile()` 走别名 |
| `src/world3d/Dungeon3D.gd` | 新增 `_on_split_requested()` + 两处 `split_requested` 接线 |
| `data/level_plans/expedition_03/level_plan.json` | 新增 `monster_rules`：12 只绝对值、AI 参数、`enemy_pool`、`death_explosion`（pinhead/nitra） |
| `tools/_egt_monster_probe.gd/.tscn` | 数据层探针（不需要游戏世界） |
| `tools/_egt_runtime_probe.gd/.tscn` | 真实链路探针（进远征03战斗房看刷出什么） |

### 4.1 攻击方式为什么是"数据"而不是"分支"

业主说"包括怪物AI和攻击方式"，但 34 种怪如果各写一个 `if`，代码会烂。
按 §3.1 的「参数优先」，把四类差异抽象成四个键：

```gdscript
"volley": {
  "count": 3,        # 一次攻击发几发
  "spread_deg": 14,  # 扇形半角
  "interval": 0.12,  # 连发间隔（0 = 齐射）
  "predict": 0.45,   # 预判系数 0~1
}
```

`_perform_volley_attack()` 统一消费。**加第 13 只远程怪 = 加一行数据**，不改攻击代码。
将来补剩余 22 种时，只有落在"分裂/全向喷/自杀/辅助"这四类里的才需要碰函数。

---

## 5. 三个真实踩坑（都记进代码注释了）

### 5.1 未知 kind 会被静默降级成 `melee_chaser`

`EnemyAvatar3D.configure()` 第一行是 `var known := COLORS.has(kind) ...`。
不加别名表的话，`egt_bullet_kin` 会**静默变成小僵尸**，日志一个字都不说。
这就是 `PROXY_ASSET_KIND` 存在的全部理由，注释里写了。

### 5.2 池子配了但不生效（优先级反了）

第一版把 `level_pool` 判断写在 `theme_pool` **之后**。远征03 的 `gameplay_theme`
自己配了老三种（melee/ranged/exploder）⇒ 函数在主题那步就 `return` 了，
关卡池**一次都没读到**。

探针实测抓到：`monster_rules` 装载成功（`pool=12`），但刷出的 8 只全是老三种。
修正为「关卡池优先于主题池」（内容层覆盖视觉层），修完立刻变成 8 只全 `egt_*`。

### 5.3 flow 关卡把刷怪推迟了，探针读的是中间态

远征03 是 flow 关卡，`TowerDescent3D._spawn_room_enemies()` 是覆写版：
走进来 → 落门（0.30 s）→ 静默（0.45 s）→ **才**出怪。

第一版探针只等 10 帧，读到的是"门已关、怪还没出"，误判成"一只怪都没有"。
改为按时间等，且直接引用两个常量（改常量时等待会自动跟上）。

---

## 6. 验收记录

| 项 | 命令 / 场景 | 结果 |
|---|---|---|
| 全项目编译 | `godot --headless --quit-after 5` | **exit 0**，parse/compile error **0 条** |
| 数据层探针 | `tools/_egt_monster_probe.tscn` | `EGT_MONSTER_PROBE_OK`：生成/数值/行为键/资产别名/关卡规则 全部通过 |
| 真实链路探针 | `tools/_egt_runtime_probe.tscn` | `EGT_RUNTIME_PROBE_OK`：进远征03 `fireplace_room_inj2` 刷出 8 只，**8 只全为 `egt_*`**（veteran 2 / bandana 2 / blobuloid 1 / blobulin 1 / bullat 1 / gunsinger 1） |
| 回归：强化怪专项 | `verify_strong_variant_monsters.tscn` | **exit 0，ERROR 0 条** —— 改 `MonsterInjector` 未破坏强化怪的数值派生 |
| 回归：敌人行为流 | `verify_3d_enemy_behavior_flow.tscn` | **exit 0，ERROR 0 条**，日志 `3D_ENEMY_BEHAVIOR_FLOW_OK` —— 改 `_perform_attack` / `_physics_process` / `_die` 未破坏既有 9 项行为（视线、缩放血量、受击体积、埋伏、远程齐射、召唤治疗、正面护盾、死亡碎片、重力分离） |

### 6.1 未执行 / 未验证

- **真实战斗手感未验**：探针只验到"怪刷出来且数值正确"，**没有**验证
  连发节奏、分裂出来的子代是否真的落地、Gunsinger 是否真的给别人加了 buff。
  这些需要真实跑一局，属于下一轮。
- **完整验收套件未跑**：`run_verification_suite.sh` 在 preflight 就因
  `check_expedition03_room_layouts.py` 的 corridor 端口数不足而退出（存量问题，与本次无关，
  与小地图那次是同一个）。
- **美术未验**：当前全是占位资产，观感不在本轮范围。

---

## 7. 下一轮应该做的（按优先级）

1. **真实跑局验证行为**：连发、分裂链、buff、自杀冲撞这四条只有真打才知道对不对。
2. **逐房 `spawn_placements`**：现在走房型公式兜底，与原作「手作编排」不符（设计 §T0.1 已标注）。
   需要房型与盒位定稿。
3. **补剩余 22 种**：按 §T2 同机制，纯加数据。
4. **硝酸怪的线状爆炸**：现在是圆形，原作是朝远离玩家方向炸一条线。
5. **Boss**：子弹王 / 加特林海鸥 / 扳机兄弟，走 Boss 专属链，工作量单独计。
6. **美术替换**：换模型时必须保持 `EnemyAvatar3D` 三点契约（根在脚底、朝 −Z、头顶锚点进表）。
