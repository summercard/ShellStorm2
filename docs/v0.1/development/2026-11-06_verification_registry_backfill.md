# 2026-11-06 四个孤儿验收登记 + 顺带修掉两处收招缺陷

- 起因：`check_verification_registry.py` 报 4 个 `verify_*.tscn` 没有归属分类。
  它们都是「写了、跑不起来 / 一直红着、于是没登记」的孤儿，最老的 2026-10-18，最新的 2026-11-02。
- 口径（业主 2026-11-06）：「以现在游戏内的效果为基准；验收标准和文档漂移都以游戏内现状为主」。
- 结果：4 个全部登记，3 个进 `core`、1 个进 `visual`；`VERIFICATION_REGISTRY_OK scenes=277`。

| 用例 | 分类 | 处理 | 现状 |
|---|---|---|:--|
| `verify_base_lamp_dynamics` | core | 无需改代码，直接登记 | 通过 `ACCEPT base_lamp_dynamics`（N1–N12 全绿） |
| `verify_base_lamp_visual` | visual | 无需改代码（headless 下按设计 exit 2），真渲染登记 | 通过 `ACCEPT base_lamp_visual`（V1 六通道 + V3 关灯态） |
| `verify_stairwell_turn_rail` | core | **判据坐标系修正**（详见 §2） | 通过 `failures=0 samples=20` |
| `verify_enemy_action_recovery` | core | **按当前 AI 节奏重写收招判据**（详见 §1），顺带修两处代码缺陷 | 通过 `checks=3278 notes=9` |

---

## 1. `verify_enemy_action_recovery`：旧判据整张作废，不是「调松阈值」

### 1.1 旧稿为什么红

| 旧判据 | 当前实现 | 结论 |
|---|---|---|
| 所有怪收招 0.34s（胖子 1.3 / ambusher 0.40 / EGT 0.34） | EGT 33 只按**攻击方式**分档：volley 0.18（射程 >7m 时 0.12）/ contact 0.10 / explode·rush·grab·flee 0.08 / support 0.16 / 其它 0.12；塔楼老怪不变（盾卫 0.48、ambusher 0.34） | 旧表**整张作废**，是 2026-11-02「逐只实测微调、每轮死时间 0.72→0.32s」的直接结果 |
| `get_state_snapshot()["skill_effect_active"]` | 该键已不存在，连发改成 `_pending_volleys` 队列 | 旧稿在 `_continuous_skills()` 抛 `Invalid access to property`，**从第一帧起就没跑完过** |
| 收招期间「反复强制重决策」不得打断 | `MonsterAIManager.force_refresh_enemy()` 会把状态改回 chase（调试接口语义） | 该判据测的是调试口，不是玩法；改为真实事件（普通受击 / 光照切换） |
| 突进之后必须有「静止反击窗口」 | 收招按 `_brake_planar(delta*18)` 线性刹车；从 7.2 m/s 刹到 0 需 0.40s > 0.34s 收招，**收招结束时仍在滑行** | 改为「速度单调不增 + 不超击退上限」，静止窗口这一条退役 |
| 近战结算帧穿墙不得命中 | `_perform_attack()` 里只有胖子僵尸查 `_has_line_of_sight()`；melee_chaser / ambusher / EGT 近战全部**只按距离结算**（`git log -L` 追过，一直是这个形状） | 该断言不再作为判据，转为已知缺口（§4.1），需业主裁决 |

### 1.2 新判据（跑绿的部分）

1. **收招时长表** `RECOVERY_SECONDS`：41 只 + 3 个 `_strong` 变体逐只对齐，改动任何一档都必须同步改表。
2. **收招窗口**：30/60/120Hz 三档 × 41 只，收招期间受击与光照切换不得打断、不得自主位移；到点必须退出到 chase/search/idle/patrol。
3. **单次结算**：一次 `attack` 只扣 1 次血；收招全程 `velocity` 峰值不得超击退上限；**速度必须单调下降**（这一条正好盯着本轮的缺陷①）。
4. **击退**：收招期间 `apply_melee_knockback(RIGHT, 5.0)` 之后两帧内 `v.x` 必须≈5.0，不许被吞、不许翻倍。
5. **冻结**：`_fate_freeze_remaining > 0` 期间 `_state_time` 不得前进。
6. **持续技能**：一次攻击只派发一次（`_egt_attack_count == 1`），`_pending_volleys` 必须 3 秒内清空。
7. **中断**：stagger / dormant / dead 必须清空排期弹丸（这一条盯着缺陷②）。

---

## 2. `verify_stairwell_turn_rail`：判据算错了 12 米

旧稿用世界常量 `FLOOR_BELOW_MIDDLE_LANDING = -6.0` 当折返平台楼面。层高从 6m 改成 **12m** 之后，
`99F↔98F` 那座楼梯间的可视根落在世界 `-12`，于是「护栏高」被算成 **-10.845m** ——
护栏本身没动，是**基准线**错了（资产自己声明 `coordinate_frame = stairwell_assembly_root_local`）。

修法：
- 高度改成在**楼梯间装配根局部坐标**里量：折返平台平面 = `-楼层高/2`（`TOWER_GEOMETRY.FLOOR_HEIGHT_M` × 0.5）；
- 楼板真实存在时再用向下射线复核该平面（容差 0.06m），两条口径互相咬；
  只对外沿段做——内侧段一侧是井口、另一侧是梯跑，最高点是**上行踏步**（实测 -5.508 对 -6.000）；
- 新增**开合判据**：楼梯间不可见时护栏碰撞必须全部 disabled（否则是看不见却挡人的空气墙），
  可见时必须 enabled。注意 `PROCESS_MODE_DISABLED` 的子树**连碰撞体都不进物理步进**，
  所以用例打开连接器时要同时恢复 `visible` / `process_mode` / 碰撞三样 —— 少一样射线一根都打不中。

---

## 3. 顺带修掉的两处代码缺陷（`src/enemy3d/Enemy3D.gd`）

### ① 收招段外部推力逐帧叠加（会把怪打飞出房间）

旧代码：

```gdscript
_brake_planar(delta * 18.0)
_push_planar(_external_velocity)   # = velocity += 外推，每帧完整体加一次
```

实测 `apply_melee_knockback(RIGHT, 5.0)` 之后：`v.x` **5.0 → 9.7 → 14+**。
这是本仓在逃跑型 / 游荡型上已经踩过两次的「稳态放大器」（见 `_tick_egt_state` 与
`_tick_egt_windup` 的注释）。收招段改成：外推还在生效时**直接赋值**（它就是这一段位移的唯一真源），
失效后才刹车收尾。

### ② 死 / 硬直 / 休眠后仍在打连发

`_pending_volleys` 由 `_tick_pending_volleys()` 按延迟**无条件**开火，不看状态。
`transition_to("dead")` 之前从不清队列 ⇒ 已经被打死的 `egt_bandana_kin` 会在半空中把剩下 3 发打完。
现在 `transition_to` 在进入 `stagger` / `dormant` / `dead` 时清空 `_pending_volleys` 与 `_pending_eggs`；
**`recovery → chase` 不清**（那一段连发本来就要打完）。

> 这两处都属「按当前游戏现状写验收时反查出来的真缺陷」，不是为了让用例变绿而改的阈值。

---

## 4. 记了但没改的（NOTE，需业主裁决）

### 4.1 近战结算不看视线

`melee_chaser` / `ambusher` / EGT 近战分支只判距离，不判遮挡；`fat_zombie03` 才查 `_has_line_of_sight()`。
玩家贴薄墙时，墙那侧的怪仍可能结算命中。**历史上一直如此**（`git log -L` 未找到删除点），
所以不是本轮回归。是否统一加视线判定，属玩法口径，留给业主。

### 4.2 体型缩放会放大 `move_and_slide` 位移（P1 候选，影响所有怪）

实测：同一只 `melee_chaser`，
- `scale = 0.7`（当前普通怪基准）⇒ 位移 = `velocity × delta`，7.2 m/s 走 0.120 m/帧；
- `scale = 1.05`（`_strong` 变体）⇒ 同样 `velocity = 7.2`，**实走 1.080 m/帧（64.8 m/s）**；
- 手动把普通怪 scale 设成 1.05 也能复现（0.841 m/帧，50.4 m/s）。

也就是 `scale ≠ 0.7` 时速度被放大，放大倍率不线性（1.05 → 约 7 倍）。
**这让「speed 数值」与实际移动速度脱钩**：`_strong` 变体、精英（`BODY_SCALE_MULTIPLIER = 2.5`）、
Boss（`boss_scale`）都在这条线上。当前 33 只复刻怪是「逐只实测后微调」的，
等于把缩放误差一起调进了配置值 —— 一旦改缩放，速度会整体跳变。
本用例把它降级成 NOTE（`raw_peak > peak × 3` 时打印），没有判红；建议单独立项排查
（方向：把体型缩放挂在视觉子节点上，`CharacterBody3D` 根节点保持 `scale = 1`）。

### 4.3 其他 NOTE

- `egt_gripmaster` 带 `die_when_others_dead`，单人夹具里一进 `_tick_egt_state` 就自灭，收招窗口未测（需要同伴）。
- 逃跑 / 游荡 / 抓取 / 不动型收招期间仍有外推位移（`_tick_egt_state` 接管位移），属设计。

---

## 5. 运行结果（2026-11-06 09:5x，Windows / Godot 4.6.3，隔离 APPDATA）

```
ACCEPT base_lamp_dynamics                                   exit 0
ACCEPT base_lamp_visual                                     exit 0（真渲染）
STAIRWELL_TURN_RAIL samples=20 failures=0 rails=2 floor_misses=0   exit 0
ENEMY_ACTION_RECOVERY_OK checks=3278 notes=9                exit 0
EGT_ASSEMBLER_OK runs=72 checks=47855                       exit 0（回归对照）
VERIFICATION_REGISTRY_OK scenes=277 categories={smoke:6, core:224, visual:41, manual:6, retired:0}
```

> 隔离方式：`APPDATA` 指到工程外目录，避免碰到正式存档。
> 本机 bash 的 `python` 没有 `openpyxl`，带账本的门禁要用
> `C:\Users\zhuangmenghong\AppData\Local\Python\pythoncore-3.14-64\python.exe`。
