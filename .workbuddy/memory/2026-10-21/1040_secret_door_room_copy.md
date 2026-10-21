# 2026-10-21 暗门破板「碎块飞了、木板不动、按 E 无反应」

业主原话：「打门后，有模板破碎的动画，但是木板没有消失，也不能点击进入支线。」

## 结论

不是破板动画坏了，是**同一处叠了两扇门**，玩家打中的是没装配的那扇。

## 时序（真因，别再往 tween 里找）

```
_commit_floor_bundle()
├─ _prepare_floor_bundle()
│   └─ _create_secret_branches()   ← build() 在这里跑：房间记录齐、房间节点/壳体都没建
│        ⇒ _adopt_authored_door() 的 find_child 必然落空 ⇒ 自己建一扇
├─ _instantiate_dynamic_room() × N
└─ _ensure_structural_shells_resident()   ← 壳体建好，TSCN 里那扇副本才冒出来
```

`build()` 末尾的 `call_deferred("settle_sites")` 补救过：能重读 TSCN 位点、把门搬到手摆位置
（所以 A24 是绿的），也调 `_drop_room_duplicate_door()` —— 但那一刻壳体还没建，同样落空。

子图侧：`secret_0_0` / `secret_1_1` 借 `room_03` 共享房壳，房壳里带 `SecretDoor_S1`，
每借一次多一扇副本。实测共 6 扇。

## 三症状 ↔ 三处代码

| 症状 | 代码事实 |
|---|---|
| 碎块动画照播 | `_spawn_board_debris()` 不读 `_boards` / `_has_teleport` |
| 木板不消失 | `_break_open()` 对 `_boards`（副本为 null）缩放 + 隐藏，整段空转 |
| 按 E 无反应 | `can_teleport()` 要 `_has_teleport`，副本从没 `set_teleport_target()` |

## 修法

- `SecretBranch3D._arm_room_copy_watch()`：`build()` 里挂 `get_tree().node_added` 一次。
- `_on_tree_node_added()` → `call_deferred("_prune_room_copy_door")`：延迟到帧末，
  避免误杀「`add_child` 在前、`_doors` 登记在后」的正主。
- `_prune_room_copy_door()`：判据 = **`site_id` 为空**（`configure()` 写的）。
  `remove_child` + `queue_free`（不能只 queue_free，同帧射线/A22 还会扫到）。
- `_sweep_room_copies()`：`settle_sites()` 收尾全场景扫，幂等兜底。
- `SecretDoor3D.take_damage()` 开头 `if str(site_id).is_empty(): return` —— 第二道闸。

## 验证

- 探针 `probe_secret_door_break`（真实流程，seed 1122239949）：清 6 扇，场上 10 = `_doors` 10；
  破板后 `Boards visible=false`、`可传送=true`、候选 `[E] 进入暗门`。
- 断言 **A26**（25 → 26 条）。反向对照（关 `_arm` + 关 `_sweep`）报红 2 扇，还原复绿。
- 正式套件 `SECRET_BRANCH_FLOW_OK … 门副本=已清`。

## 坑（下次别再踩）

**A26 第一版是空过**：套件 `test_mode` 下房间壳体没建、副本 0 扇，关掉清道夫做反向对照
**照样全绿**。必须在断言里先 `ensure_shell_built()` 催建房壳、等两帧再数。
与 A25「套件跑不出真实 bootstrap 顺序」同一类坑 —— **断言的前提条件本身要能被验证**。

## 遗留

- 房间 TSCN 里的门仍只是**摆位锚点**（不参与运行时逻辑）。要让它成为唯一真源，
  得把 `_create_secret_branches()` 排到壳体构建之后 —— 那是改装配顺序，不是改门。
- `_break_open()` 仍是缩放到 0.01 + 隐藏，`Boards` 节点留在场上（读档/对照依赖它在）。
