## 轮次 307 — 2026-05-28 08:05 UTC+8

### 维度
BossActor 场景接入 — 把 BossActor.gd 真实接入 RoomBoss.tscn，替换 DemoBoss

### 当前问题审查

轮次 306 计划了 BossActor.gd（完整技能链路+Boss体型联动），但 RoomBoss.tscn 仍然引用 DemoBoss.gd，BossActor 实际未生效。

**问题定位**：
1. `scenes/RoomBoss.tscn` 的 Boss 节点 `BossActor` 使用 `script = ExtResource("1_demo_boss")` 指向 DemoBoss.gd（不是新的 BossActor.gd）
2. 缺少 ext_resource id=3 指向 BossActor.gd
3. `BossPhaseDirector` 节点存在但 BossActor.gd 未被场景引用，导致阶段技能系统无法启动

### 本轮目标
将 RoomBoss.tscn 从 DemoBoss 切换到 BossActor，让 6 个技能链路真正可执行。

### 修改内容

#### `scenes/RoomBoss.tscn`
1. **load_steps: 8 → 9**（新增 ext_resource）
2. **替换 ext_resource**：DemoBoss.gd → BossActor.gd（id=3, path=res://src/enemy/BossActor.gd）
3. **切换脚本引用**：`script = ExtResource("1_demo_boss")` → `script = ExtResource("3_boss_actor")`
4. **Boss Shape**：80×80 → 110×110（Boss 体型略大）
5. **BossNameLabel 偏移**：top -110 → -120（Boss 变大后标签要下移）

#### `src/enemy/BossActor.gd.uid`（新建）
- 写入 `uid://b3xv82kq97m4d`（与 project.godot 中其他 .gd.uid 一致格式）

### 玩家可感知结果
- 进入 Boss 房后，Boss 体型变大（110×110），HP 800
- HP 66% 时阶段切换到 Phase 2，颜色加深（Boss 闪白+缩放回弹）
- HP 33% 时进入 Phase 3 狂暴，Boss 颜色更红并略放大
- Phase 2+ 技能触发（小怪生成/AOE/蓄力射击等）

### 验收标准
- [x] Godot headless --quit-after 3: **EXIT 0**（编译通过）✅
- [ ] 人类试玩：进入 Boss 房后，Boss HP 低于 66% 时阶段切换到 Phase 2，颜色变深
- [ ] 人类试玩：Phase 2 时 `spawn_minions` 技能触发，Boss 周围生成小怪

### 剩余风险
1. **BossPhaseDirector 配置未接入**：BossActor.gd 有 `configure_phases()` 方法，但 BossRoomLogic 还没调用它
2. **DemoBoss 仍然是 DemoRoomChain 的 Boss 房引用**：需要把 DemoRoomChain 的 Boss 房场景也切到 RoomBoss，或修改 DemoBoss 的逻辑
3. **没有配置技能树**：BossActor._execute_skill_by_id 里的 6 个技能还未实际测试触发时机

### 下轮最可能方向
1. **BossRoomLogic 中接入 `configure_phases()`**：让 BossPhaseDirector 有正确的技能树配置
2. **DemoRoomChain 的 Boss 房切换到 RoomBoss**：保证 DemoRoomChain 使用 BossActor 而不是 DemoBoss
3. **Boss 冲刺（charge）A* 寻路**：直线冲向玩家会撞墙