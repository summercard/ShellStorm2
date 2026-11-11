# 99F 基地「点远征入口恒报保存失败」：根因与修法

日期：2026-11-12 01:35 左右 · 事务：99F 入场仪式收口（承接 2026-11-11 的全息入场两套表演）

## 一句话

99F 基地点任何远征入口都会失败，因为出发事务强制要求 `flush_runtime_checkpoint()` 成功，
而基地场景根本没有运行快照提供者。**这不是磁盘问题，是判据写错。**

## 根因链（可复现）

```text
RogueMapSelectMenu._commit_departure()
→ ExpeditionDepartureService.prepare(get_parent(), BASE)
→ BaseManager.flush_runtime_checkpoint()
→ _capture_runtime_checkpoint()                # 需要 _runtime_checkpoint_provider
→ 全仓只有 Dungeon3D 调 register_runtime_checkpoint_provider()
→ 99F 基地是 BaseWorld3D extends Node3D，没有 build_runtime_save_snapshot()
⇒ snapshot 恒空 ⇒ flush 恒 false ⇒ prepare 恒「保存失败，请重试」
```

控制台特征只有一行：`ERROR: [HologramCity] 保存失败，请重试`。

## 为什么既有测试一直是绿的

`tests/verification/verify_expedition_departure_carry.gd` 用的是真实 `TowerDescent3D` 当提供者，
从来没有从 `BaseWorld3D` 出发。**测试绕开了真实起点**，所以这个缺陷能一直存在。

## 修法（2 个文件）

- `src/base/BaseManager.gd`：新增只读 `has_runtime_checkpoint_provider()`。
- `src/world3d/ExpeditionDepartureService.gd`：
  - 有提供者 → 仍必须 flush 成功（塔楼/关卡内行为不变）；
  - 无提供者 → 沿用已落盘快照；`previous` 为空（新档直接站在基地）**不伪造** schema
    不完整快照，返回 `carried=false`；
  - 回滚在 `previous` 为空时清空检查点，不写空字典冒充携带数据。
- 目的地来源不依赖空快照：`TowerDescent3D._expedition_entry_source` 默认就是 `base_99f`。

## 验收现状

- 已证：点击 → `state=entering/departing` → `base_menu_click_departure` → 读取页
  （`ShellStorm2-work/verification/expedition_entry/20261112_003833`）。
- 未证：基地菜单链整体。读取页停在「正在装配地图 · 11/13」；当次机器上另有 3 个无关
  Godot 4.7.2 进程各约 1 GB，有一次 600 s 连基地场景都没装完 ⇒ 既不算通过，也不定性为死锁，
  须空闲复跑 `python scripts/run_expedition_entry_qa.py --base-menu-e2e`。

## 学到的两条

1. **「没有东西可存」和「存失败」必须分开。** 前者是正常态，后者才是故障；合并判据会让整条
   产品路径静默死掉，而且只报一句泛化文案，看不出根因。
2. **验收要在真实起点上跑。** 出发点被替换成另一个场景后，测试覆盖的是一个不存在的玩法路径。

---

# 追加：入场朝向与遮挡（同夜，02:00–03:00）

主人反馈「角色要面对去第一个房间的门，而不是面对出口位置」。

## 根因

1. `aim_yaw` 出生默认 0 → 面向世界 −Z。远征01 起始房入口在东（`entry_side=east`）、主路向西，
   世界 −Z 正好是"回去的方向"。
2. 近景机位与角色之间卡着一张办公椅，把角色挡掉八成 —— 朝向改对之后反而更明显。

## 修法要点

- `Dungeon3D.forward_door_point_from(room_id)`：主路下一间的**那扇门**的世界坐标。
  按记录 `parent` 判主路；环状图退回开放邻边；门节点优先于房间中心。不认关卡 ID。
- `TowerDescent3D._face_player_toward_forward_door()`：只写 `aim_yaw`，**不手动转 avatar**
  （`PlayerAvatar3D` 每帧插值，手动转会打架）。
- `ExpeditionEntryPresentation3D.suppress_occluders()`：黑幕仍全覆盖时把挡在「相机→角色」之间的
  陈设移出这一镜，`restore()` 恢复。

## 两个必须记住的坑

1. **`transparency` 对 GLB 不透明家具无效。** 实测设 0.12，诊断打印 `faded=2`、截图毫无变化。
   这就是第一版"看起来改了其实没改"的原因。要么改共享材质（污染玩法画面），要么移出镜头。
2. **只判线段会漏掉"擦线而过"的大件。** 椅子中心离中心线 0.61 m，线段判定完全不算遮挡，
   但 0.75×1.29 的体量挡住大半 → `faded=0` 却看不见人，典型的假绿。
   加第二条「中心到线段距离 < 角色半径 + 该件半对角」并限 `≤3 m`（排除地板/承重底板/墙体/碎屑群）。

## 验证

正式 Runner 双 seed：`20261112_024819` exit0 / 0 engine error / `door_facing_dot=1.000` / 6 图。
host 组 `20261112_025300` 四条全过。fixture `20261112_024705` A3.15/B3.60。

## 另记

这一小时里另一会话正在改 `EncounterEventDirector3D.gd` / `LevelPlanValidator.gd`，
先后撞到"函数未定义"和"duration 校验"两个中间态。**并行开发时编译/校验失败先看 mtime**，
别急着把自己的改动当嫌疑犯。
