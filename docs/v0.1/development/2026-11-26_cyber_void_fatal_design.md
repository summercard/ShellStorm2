# 赛博虚空坠亡与固定镜头设计

日期 2026-11-26。功能 `VFX-POOL` / `PLAYER-STATE` / `RUN-SETTLE`。工程 0.1.0，代码基线 `2b3c0478`，交付为工作区设计 r7。

## 与当前运行路径的差异

- 已有赛博虚空 v006 可裁切静态碰撞。玩家进入 `falling` 后，`Player3D.move_airborne()` 可触发下层落地，无支撑时还有 15 米回位。原独立物理专项仍用于校验 v006 的行为。
- 普通战斗死亡状态会向上抛飞并在触地时回弹。行动宿主用死亡动画与败北滤镜的完成信号开放结算。将两者直接套在虚空，会出现地面回弹和额外等待；r7 将虚空原因映射到独立的固定镜头，由该表现接回原有结算。
- 本轮改动为目标设计和项目索引。没有运行代码、资源、关卡和账本版本变动。传送与其他特殊结果待分别设计。

## 验收状态

- `python3 scripts/check_feature_traceability.py` 与 `git diff --check` 均退出 0。
- `python3 scripts/check_documentation_contracts.py` 修改前后均退出 1，11 条既有断链的文件和目标完全一致。日志见工程外 `verification/2026-11-26_cyber_void_fatal_design`。
- 坠亡判定、固定机位、原结算交接待实现及实测。

[赛博虚空 r7](../design/scene_void_erosion.md#玩家坠入赛博虚空死亡)
