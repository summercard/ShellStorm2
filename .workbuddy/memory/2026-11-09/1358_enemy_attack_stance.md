# 怪物攻击姿态站住（MONSTER-AI）

时间：2026-11-09 13:58。事务：业主报「怪物一边攻击一边移动」。

## 定案

- 攻击姿态 = `telegraph` + `attack`，这两段**不许自主位移**；回到 `chase` 才重新起步。
- 刹车：`ATTACK_STANCE_BRAKE_MPS2 = 55`（`a = v²/(2s)`，s=0.125 m、v=3.7 ⇒ 54.8），
  由 `_tick_attack_stance()` 在 `telegraph` 用。`_tick_egt_windup()` 与
  `EGT_WINDUP_SPEED_RATIO = 0.35`（"边举枪边踱半步"）**已删除，别再恢复**。
- 外力不吞：前摇里击退/牵引按原值生效，且**只能赋值**，不许 `_brake_planar` + 逐帧
  `_push_planar` 叠加（本仓稳态放大器，5.0→9.7 → 14+）。
- 自主动位移（枪精灵 `wander` / 逃跑 / 枪歌者 `interrupt`）在攻击姿态里闭闸，
  并在 `transition_to("telegraph")` 时清 `_external_velocity` + `_external_timer`。
- 排期连发没打完（`_pending_volleys` 非空）不退出 `recovery`。冷却在出手帧起算，
  **攻击频率不变**，变的只是"打完再走"。
- 例外（招式本身的位移，故意保留）：链枪手 `orbit` 的边转边压、抓握大师 `dive`、
  自爆族 `leap`、近战突进（melee_chaser 7.2 / ambusher 9.4 / egt_contact 6.4）。

## 证据

- 新增 `tests/verification/verify_enemy_attack_stance.tscn`（core 已登记），35 检查绿。
- 反向验证：`git stash` 掉 `Enemy3D.gd` 重跑 ⇒ 11 条精准变红（A 段 6 / C 段 2 / D 段 2 / E 段 1）。
- 判据用 `velocity` 不用位置差 —— 体块 scale 会把 `move_and_slide` 实际位移放大数倍。
- 既有红项：`verify_monster_ai_system_complete` 令牌预算 1/0，改前改后一致，与本轮无关。

## 文档

- `docs/v0.1/development/2026-11-09_enemy_attack_stance_hold.md`（本轮记录）
- `docs/v0.1/design/怪物设计.md §T2.9.2` 已改写（原文书写的"35% 踱步"作废）
- `docs/v0.1/design/远征关卡03设计.md`、`docs/v0.1/19_远征03专项工作链路.md` M3 行同步划线。
