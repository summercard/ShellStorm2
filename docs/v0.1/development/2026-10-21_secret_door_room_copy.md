# 暗门破板「碎块飞了、木板不动、按 E 无反应」

日期：2026-10-21
业主原话：「打门后，有模板破碎的动画，但是木板没有消失，也不能点击进入支线。」

## 1. 现象与第一猜测的分歧

碎块特效是上一轮刚做的（`VFX-BOARD-DEBRIS-3D`，FX01-33），第一反应会去查
`_break_open()` 里那段缩放 / `visible = false` 的 tween。**查错了。**

真正该问的是：**玩家打中的那扇门，是不是运行时装配好的那扇。**

## 2. 探针实测：同一处有两扇 `SecretDoor_S1`

`tests/verification/probe_secret_door_break.gd`（真实流程 `test_mode = false`）把场上
所有 `SecretDoor3D` 连同 `debug_snapshot()` 一起打出来：

```
[登记] _doors 共 10 扇
  S1     path=SecretBranches/SecretDoor_S1            pos=(92.50,0.00,-25.86)
         state=0 木板在=true 木板可见=true 落点=(1015,0,0) 可传送=false 提示=「进入暗门」
[全场景]
  **未登记** SecretDoor_S1  path=.../SecretBranch_0/SecretRoom_secret_0_0/
                                      AuthoredLayoutArtRoot/Room03/SecretDoor_S1
         state=0 木板在=false 木板可见=false 落点=(0,0,0) 可传送=false 提示=<空>
```

两扇同名同形，一扇被 `configure()` 认领过，另一扇**从来没被认领**（`site_id` 为空）。
未认领那扇的 `木板在=false` 是关键字：`_boards` 是 null，它连自己身上的木板都不认识。

## 3. 三个症状，三处代码，一一对上

| 业主看到的 | 代码事实 |
|---|---|
| 有木板破碎动画 | `_spawn_board_debris()` 不读 `_boards`、不读 `_has_teleport`，只要被 `take_damage()` 打到就播 |
| 木板不消失 | `_break_open()` 对 `visual = _boards if _boards != null else _fallback_mesh` 做缩放与 `visible = false`；副本两者皆 null ⇒ 整段空转 |
| 按 E 没反应 | `can_teleport()` 要求 `_has_teleport and state == BROKEN`；副本从没 `set_teleport_target()` ⇒ `_has_teleport = false` 恒假 |

一句话：**不是破板坏了，是玩家打中了一扇根本没装配的门。**

## 4. 副本为什么会出现（时序，不是遗漏）

```
Dungeon3D / TowerDescent3D._commit_floor_bundle()
├─ _prepare_floor_bundle()
│   └─ _create_secret_branches()      ← SecretBranch3D.build()
│        · 房间**记录**齐了
│        · 房间**节点**还没建（_instantiate_dynamic_room 在下一行之后）
│        · 房间**壳体**更没建（_ensure_structural_shells_resident 再往后）
│        ⇒ _adopt_authored_door() 的 find_child 必然落空 ⇒ 自己建一扇
├─ for record in _records: _instantiate_dynamic_room(record)
├─ _plan_room_layout()
└─ _ensure_structural_shells_resident()   ← 壳体建好，TSCN 里那扇副本才冒出来
```

`build()` 末尾的 `call_deferred("settle_sites")` 补救过一次：它重读 TSCN 位点、把门搬到
手摆位置（A24 因此是绿的），也调 `_drop_room_duplicate_door()` —— 但那一刻壳体同样还没建，
`find_child` 还是落空。于是「位置对了、副本留下了」。

子图那侧更直白：`secret_0_0` / `secret_1_1` 借的是 `room_03` 的共享房壳，房壳里带着
`SecretDoor_S1`，于是每借一次就多一扇副本。实测本次清掉 **6 扇**。

## 5. 修法

### 5.1 按事件盯，不按装配时机清一次

`SecretBranch3D`：

- `_arm_room_copy_watch()`：`build()` 里挂 `get_tree().node_added` 一次。
  任何 `SecretDoor3D` 入树都会被看到 —— 壳体什么时候建，副本就什么时候被抓。
- `_on_tree_node_added()` → `call_deferred("_prune_room_copy_door")`：
  延迟到帧末再判。装配自己建的门也走这条信号（`add_child` 在 `configure()` 之后、
  `_doors` 登记之前），提前判会误杀正主。
- `_prune_room_copy_door()`：判据是 **`site_id` 是否为空**（`configure()` 写入的）。
  副本永远空。命中就 `remove_child` + `queue_free`（不是只 `queue_free`：后者帧末才生效，
  同帧的射线 / A22 遮挡检查还会扫到它）。
- `_sweep_room_copies()`：`settle_sites()` 收尾全场景扫一遍，幂等兜底。

### 5.2 第二道闸：未认领的门不接受伤害

`SecretDoor3D.take_damage()` 开头：

```gdscript
if str(site_id).is_empty():
    return
```

即使清道夫漏了，玩家也不会再看到「碎块飞了、门没动」这种自相矛盾的反馈。

## 6. 验证

| 项 | 结果 |
|---|---|
| 真实流程探针（seed 1122239949） | 清掉 6 扇副本；场上门 10 扇 = `_doors` 10 扇 |
| 破板后状态 | `state=1`、`Boards visible=false scale=(0.01,0.01,1)`、`可传送=true` |
| 站位后交互候选 | `{"available": true, "prompt": "[E] 进入暗门", "priority": 90}` |
| 新增断言 A26 | `[NOTE] A26 场上门全部被认领：10 扇` |
| 反向对照（关掉清道夫） | `[FAIL] A26 场上仍有 2 扇没被装配认领的门副本：.../Room03/SecretDoor_S1（site_id=<空>）…` |
| 正式套件 | `SECRET_BRANCH_FLOW_OK … 落点在房内 门副本=已清 …` |

## 7. 一条必须记住的盲区

A26 第一版是**空过**的：验收套件的 `test_mode` 下房间壳体没建，场上副本 0 扇，
关掉清道夫做反向对照**依然是绿的**。

修法是在断言里主动 `ensure_shell_built()` 把位点房间的壳体催出来，再等两帧让 deferred
清道夫跑完，然后才数。**不催建 = 没东西可查**，与 A25「套件复现不出真实 bootstrap 顺序」
属同一类坑。

## 8. 遗留

- 主图房间 TSCN 里那扇门仍然只是**摆位锚点**：它不参与运行时的任何逻辑，靠清道夫处理。
  以后若真要让「房间 TSCN 里的门」成为运行时唯一真源，得让 `_create_secret_branches()`
  排到壳体构建之后（改的是装配顺序，不是门本身）。
- 破板仍有缩放到 0.01 的残留动作（`Boards` 节点留在场上、只是不可见 + 缩放 0.01）。
  要彻底干净可以让 `_break_open()` 直接 `remove_child`，但读档 / 反向对照都依赖节点还在，
  暂不动。

## 9. 进 `room_03` 第一眼看不看得见（业主 2026-10-21 问）

业主问：「那我进 room03 后会自动看到那个门吗」。答案是**不会，得主动转头**；但走到房间中间就看得到。

探针 `probe_room03_first_look`（真实流程 `test_mode = false`，种子 1122239949）实测：

| 站位 | 暗门水平偏角 | 垂直偏角 | 距离 | 结论 |
|---|---|---|---|---|
| 东门内侧 1.8m 朝房心 | **−68.4°** | −2.6° | 20.76m | 视野外（要转头 33.3°） |
| 西门内侧 1.8m 朝房心 | **+58.0°** | −1.6° | 23.73m | 视野外（要转头 23.0°） |
| 房间中心朝门 | 0° | — | 19.13m | **射线直接命中门，无遮挡** |

原因不是「门没摆好」，是三件事叠在一起：

1. **几何**：`room_03` 是 30 × 40m 的房，暗门在局部 +Z 那面宽墙上（世界 `(-87.5, 0, -20.86)`），
   距房心 **20.13m**；主路门在 east / west 两侧（世界 x = −75 / −105，z = −40），
   玩家进门后的自然视线横穿房间**短边**，门永远落在侧方 58~68°。
2. **视野窄**：玩家相机 `fov = 43°`（`Player3D.tscn`），16:9 下竖向半视角 21.5°、**水平半视角只有 35°**。
   58~68° 的偏角必然在画面外 —— 不是「不显眼」，是「不在屏幕上」。
3. **中途还挡**：从门口**转头**看门，射线在 5.92m（东门）/ 4.56m（西门）处命中 `work_cluster_d5` /
   `work_cluster_d` 的碰撞代理。站在门口往那边瞟一眼也看不到，得走进去。

玩家的实际体验因此是「进门 → 往前走 → 到房间中段往那面宽墙一看」，门在 19m 外直接可见
（实拍 `outputs/room03_first_look/02_room_center_turn.png`，不补光、fov 43°，木板 + X 斜撑 + 板缝透光都在）。

**这轮没有改任何东西**：门的位置是既定的固定槽位（S1 就在 `room_03` 那面墙），这次只把「第一眼在哪」量清楚。
若要更醒目，可选项是加引导（地面光斑 / 板缝透光更亮 / 声源），属另一件事。

## 10. 把 S1 从南墙移到北墙（业主封了南墙）

业主：「03号房间的那个门 帮我放到另一侧去 我把南面的墙封起来了。」

### 10.1 先确定「另一侧」是哪面墙

`_wall_normal()` 里 `south = +Z`、`north = −Z`（都指**朝房间外**）。运行时实测 `room_03` 中心
`(-90, 0, -40)`（当次布局，世界坐标随布局变）、局部内空 ±19.135，门原来在局部 `(2.5, 0, +19.135)` ⇒ 世界 `(-87.5, 0, -20.86)`，
**就是 `+Z` 那一面 = 南墙**，与业主封掉的是同一面。所以目标是对面：局部 `−Z`，世界 z=−59.135。

### 10.2 数据源不能直接改成 `north`（我先改错了）

`floor_00.json` 是**设计源**坐标，远征 01 整层固定旋转 180° 后才落地。
`FloorPlanGenerator._rotated_secret_site()` 对 `wall` 做法线旋转、对 `lane` 按切向同向/反向取号：

| | 设计源 | 旋转 180° 后（实机） |
|---|---|---|
| 原值（未动） | `south`, `lane +2.5` | `north`, `lane −2.5` |
| 我第一版误改 | `north`, `lane −2.5` | `south`, `lane +2.5` ← 又跑回业主封掉的南墙 |

所以**数据源保持原样**（`south / +2.5`），只在房间 TSCN 里把门手摆到北墙 `x = −2.5`。
这样「手摆」与「若删掉手摆后自动重算」落在同一处，不会埋雷。已还原并 `git status` 确认数据文件零改动。

### 10.3 但 `+2.5` 那个位置在北墙上是堵的

直接镜像到 `x = +2.5` 之后，房心朝门的射线在 **12.07m** 处命中 `work_cluster_a3` —— 军械库那排工作台。
于是沿北墙每 0.5m 打一条射线扫了一遍（`probe_room03_north_wall`）：

```
x ∈ [−14.0, −6.0]  被 work_cluster_b / b2 挡
x ∈ [−5.5,  +1.0]  通畅（7.0m）   ← 唯一可用空档
x ∈ [ +1.5, +14.0] 被 work_cluster_a3 / a2 / a 挡
```

门宽 2.2m，取空档近中心 `x = −2.5` ⇒ 门覆盖 `[−3.6, −1.4]`，左余 1.9m、右余 2.4m。

⚠️ **这个结论绑定当前家具布局**。同期 `f00_room_03_static_layout.tscn` 里还有一批家具被重排过
（`locker_bank_*`、`power_cabinet_*`、`work_cluster_*` 等位置全变、还新增了若干节点，不是本次改的）。
家具再动，空档要重扫。

### 10.4 改动与实测

| | 改前 | 改后 |
|---|---|---|
| TSCN `SecretDoor_S1` | `(2.5, 0, +19.135)`，无旋转 | `(−2.5, 0, −19.135)`，绕 Y 180° |
| 房间局部 | `(2.5, 0, +19.135)` | `(−2.5, 0, −19.135)` |
| 世界坐标（seed 414339956） | `(-87.50, 0, -20.86)`（另一布局） | `(87.50, 0, -64.14)` |
| 所在墙 | 局部 +Z（南） | 局部 −Z（**北**） |
| 房心 → 门，首个命中 | 家具（`work_cluster_a3`） | **门本身**（19.13m） |
| 距房心 | 20.13m | 20.13m |

旋转必须转 180°：门叶的 `+Z` 是「朝房间外」的契约（`SecretDoor3D` 文件头），
北墙朝外是 `−Z`，不转的话门会背对墙、木板朝向房间内侧。

从东/西门口「刚进门」仍看不到（水平偏角 +45.2° / −54.7°，玩家半水平视角 35°），
与移动前的性质一样：**要走进房间中段**。这一点没变，也没打算变 —— 位点是固定槽位。
