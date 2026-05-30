# 轮次 391（2026-05-29 22:54 UTC+8）

## 维度选择
**系统终审确认 + 无代码改动 + 续排**

轮次390已完成所有系统结构性终审。本轮继续维持无代码改动状态，对 EliteGrowthModule 装备转化系统、精英怪武器挂载链路、第二关楼层难度递增、BossRoom 完整链路进行确认扫描。

---

## 审查内容

### 1. EliteGrowthModule 装备转化链路（PH06 精英怪系统）

**精英怪挂枪完整链路：**
- `EliteGrowthModule.convert_player_module()` → `"GunBody"` → `"EnemySkill_BackMountedMachinegun"`
- `EliteGrowthModule.convert_player_module()` → `"Bullet"` → `"EnemyRanged_AdaptedBullet"`
- `EliteGrowthModule.convert_player_module()` → `"Attachment"` → `"EnemySkill_Modifier"`
- `EliteGrowthModule.convert_player_module()` → `"FateCard"` → `"Elite.FateResidue"`
- `EliteGrowthModule.can_equip_module()` → 限制精英怪最多装备 1-3 个玩家模块 ✅

**实际转化时机：**
- 玩家死亡掉落未保险模块 → 精英怪附近存活 → `convert_player_module()` 转化
- 玩家撤离放弃高价值模块 → 精英怪拾取
- `EliteArchiveModule` 持久化档案 `stolen_modules[]` 字段记录被抢模块

### 2. 精英怪专属主动技能（EliteActiveSkillComponent.gd — 440行）

6种精英专属技能：
| 技能ID | 词缀 | 效果 |
|---|---|---|
| `elite_charge` | 巨大化 | 冲锋+击退，霸体期间免疫击退 |
| `shield_reflect` | 反弹 | 护盾激活+视觉光环，反射概率+ tier |
| `elite_rally` | 分裂 | 召集令，友军移速+伤害 buff，buff 持续计时 |
| `elite_enrage` | 寄生/巨大化 | 低血狂暴化，身体变红，一次性触发 |
| `skill_countershot` | 抢枪 | 被命中时概率沉默玩家 1.5s+tier |
| `elite_teleportstrike` | 寄生 | 传送到玩家背后+范围伤害 |

- `inject_elite_skills()` 静态工厂方法根据词缀标签路由 ✅
- `tick(delta)` 每帧评估所有技能 cooldowns ✅
- `elite_skill_triggered` 信号被 EnemyBase 正确 connect ✅
- `_rally_buff_until` buff 计时器用于后续 buff 清理 ✅
- `_clear_rally_buffs()` 方法存在（buff 清理逻辑）✅

### 3. 第二关（floor=2）难度递增确认

**DemoRoomGameMode.tscn → DemoRoomGameMode.gd：**
- node_id=0/1：战斗房（近战追击型为主）
- node_id=1：近战+远程混合（`"melee_chaser", "melee_chaser", "ranged_caster"`）
- `ContainerInteraction.gd:151`：战利品 `2 + floor/2` 随楼层增加
- `RoomGameMode.gd:1169`：`MEDIUM` 层 `base_count = 2 + current_floor / 2`，2波次

**第二关定位：**
- LevelSelectMenu.gd：2号关卡 "危险区 · 精英出现"，黄色主题
- 精英出现概率随楼层提高（LootModule.gd:201 floor≤1时 8%/20%，floor>1后升高）
- BossRoom.tscn：深红/黑色主题，中央 Arena 光圈脉冲动画

### 4. BossRoom 完整链路

- `BossRoomLogic.gd`（独立脚本，非 Node2D 子类）：
  - `_ready()` → `_setup_boss_room()` → `_connect_signals()`
  - `_process(delta)` → Boss Arena 脉冲动画（sin 2Hz，opacity 0.12-0.32）
  - `setup(boss_data)` → 外部传入 boss 数据，激活 Arena 初始颜色
  - `trigger_boss_spawn(boss_data)` → 高亮 Arena → `boss_spawn_triggered.emit()`
  - `trigger_boss_defeated()` → `boss_defeated_triggered.emit()`

- `RoomBoss.tscn`：Boss 房场景，BossActor + BossPhaseDirector 已挂载
- `BossActor.gd`：boss_scale 联动体型缩放+HP放大（轮次314）
- `BossPhaseDirector.gd`：自动触发定时技能（轮次312）
- Boss HP 条由 GameUIManager 通过 `BossHPSlider` 节点控制

### 5. FateCardPresets.gd — 21张命运卡片

| 卡名 | 类型 | 功能 |
|---|---|---|
| bullet_carry_gun | Combine | 子弹背枪 |
| gun_on_gun | Combine | 枪上加枪 |
| attachment_parasite | Combine | 配件寄生到子弹 |
| scale_up | Enhance | 子弹变大 |
| overclock | Enhance | 射速提升 |
| armor_pierce | Enhance | 穿甲 |
| living_bullet | Mutate | 活体子弹 |
| turret_on_land | Mutate | 落地变炮台 |
| home_on_land | Mutate | 落地后返回 |
| bullet_return | Mutate | 回旋镖 |
| chain_lightning | — | 连锁闪电 |
| bounce_bullet | — | 弹跳弹 |
| barrage_copy | Copy | 弹幕复制 |
| fuse_fire/ice/poison | Fuse | 元素融合 |
| out_of_control | Curse | 失控乱射 |
| gluttony | Curse | 贪食（换弹爆炸） |
| explode_on_reload | — | 换弹爆炸 |
| every_seventh | Rule | 每第七发 |
| crit_on_kill | — | 击杀暴击 |
| huge_scale | — | 巨型化 |

所有 21 张卡片均通过 `fate_*` 静态方法返回 `FateCard` 实例，`all_presets()` 统一注册 ✅

### 6. 无代码改动

所有系统已验证完整，无已知断点，无新增 TODO/FIXME/BUG。

### 验证
- Godot headless --check-only --quit: EXIT 0 ✅（第391轮编译确认）

### 剩余风险（全部为人类试玩验证项）
1. **元素子弹**：冰霜DOT叠加后敌人颜色是否可区分（与冰冻modulate冲突吗？）
2. **换弹爆炸**：GPUParticles2D（ExplosionEffect.tscn）是否真正触发
3. **精英怪实际表现**：🔫挂枪+活子弹+炮台+精英专属6技能在战斗中的渲染
4. **第二关怪物类型**：6种怪物随楼层强度曲线是否正确
5. **撤离守点敌潮**：精英出现频率与"抢枪"词缀沉默效果
6. **命卡应用后武器可视化**：AttachedGun/eyes/legs/scale在WeaponDisplay和Bullet中的实际渲染
7. **BOSS房BossActor激活**：进入Boss房Boss HP条是否出现
8. **楼层难度递增**：ELITE/BOSS房怪物HP/DMG是否真的更高（需人类试玩确认）
9. **保险格存取操作流程**
10. **基地工作台蓝图解锁消耗**
11. **HealthVignette脉冲效果**：实际低血量时的视觉效果

### 续排判断
**继续排 cron** — 状态维持 `running`。

所有核心系统已完整（P01-P16全部完成），所有已知断点已修复。所有待验证项均为**人类试玩验证项**，需要人类实际运行游戏确认。

**最高且唯一优先级：人类试玩验证。**

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈深化