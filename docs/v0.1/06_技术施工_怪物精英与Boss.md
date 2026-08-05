# 技术施工｜怪物、唯一精英与 Boss v0.1

系统编号：4  
上级设计：[游戏设计文档 §9](README.md#9-核心系统四怪物唯一精英与-boss)  
内容表：[游戏内容数据库](data/ShellStorm2_游戏内容数据库_v010.xlsx) 的 `怪物与Boss`、`精英怪`

## 1. 职责与边界

怪物系统拥有敌人内容模板、AI、技能、生命、阶段、精英档案绑定和战利品请求。关卡系统提供生成槽与房间边界；战斗系统传入伤害上下文；掉落系统根据结果生成物品；剧情和 UI 只订阅事件。

## 2. 当前正式怪物结构

- <span style="color:#2E7D32">**[已实装]** `Enemy3D` 是统一玩法根，状态包含 `idle / patrol / alert / chase / search / telegraph / attack / stagger / dead`。</span>
- <span style="color:#2E7D32">**[已实装]** `EnemyAvatar3D` 只负责可替换外观、轮廓和表现。</span>
- <span style="color:#2E7D32">**[已实装]** 六种普通模板：小菌猪、孢子射手、蜂巢怪、壳甲卫兵、炸弹果、地刺虫；另有统一 Boss 模板。</span>
- <span style="color:#2E7D32">**[已实装]** 正式 3D 基线生命为 42–112，Boss 为 520；旧 2D 数值只参与倍率换算。</span>

## 3. 普通怪与 Boss 数据契约

```text
monster_content_id
display_name
archetype
base_profile (hp/speed/damage/range/cooldown)
ai_strategy_id
skill_ids[]
floor_pool / room_pool
loot_table_id
presentation_asset_id
acceptance_case
```

楼层、主题、精英和 Boss 阶段只能通过显式修饰器改变基线；最终实例保留修饰来源列表，便于解释实际数值。

## 4. 遭遇生成接口

关卡提交 `EncounterRequest`：房间 ID、楼层深度、房间类型、主题、预算、生成槽、随机流。怪物系统返回不可变 `EncounterPlan`：敌人内容 ID、修饰器、槽位、出现时点和合法空计划原因。

<span style="color:#EF6C00">**[Codex补充]** 房间不能在循环中自行随机敌人；否则重载、开门、进入房间可能得到不同列表并破坏清房条件。</span>

## 5. 12 只唯一精英

### 5.1 已冻结规则

- <span style="color:#1565C0">**[用户设计]** 全游戏固定 12 只，每只有稳定 ID、独立名字、功能与档案。</span>
- <span style="color:#1565C0">**[用户设计]** 精英可随机出现、成长、逃脱、获取玩家枪械；同一时间最多存在一只同名精英。</span>
- <span style="color:#2E7D32">**[已实装原型]** 兼容链路已有独立 `elite_archive.dat`、成长阶段、逃脱/死亡结算、模块转技能和两只初始精英。</span>
- <span style="color:#EF6C00">**[Codex补充]** 正式 3D 需要一个全局 `EliteRosterService` 迁移并拥有这些能力。</span>

### 5.2 精英定义与档案分离

`EliteDefinition` 是数据库内容：名字、基础种类、核心机制、成长方向、夺械转译和表现。`EliteArchiveRecord` 是玩家存档：等级、状态、历史、最近出现、夺取模块、悬赏、成长残留和当前预约。

禁止把存档记录直接放在场景节点元数据里；场景节点只保存 `elite_id + encounter_instance_id`。

### 5.3 唯一生成事务

```text
SelectEligibleElite(seed, floor, history)
→ reserve(elite_id, encounter_id)
→ build encounter plan
→ instantiate and bind archive
→ confirm reservation
→ on death/escape/despawn settle archive
→ release reservation
```

同名唯一性以稳定 `elite_id` 为准，不以显示名字符串扫描场景树。游戏崩溃或生成失败后，加载存档时清除没有有效行动事务的陈旧预约。

### 5.4 夺取枪械

1. 记录玩家本次遭遇使用过的枪型内容 ID，以及必要的永久命运槽、子弹和配件能力快照；不取得玩家原始 `weapon_instance_id` 的所有权。
2. 按精英自身转译规则选择可夺取模块。
3. 保存内容 ID、版本和必要数值快照，不保存玩家枪械实例 ID、Node 或 Resource 实例。
4. 下次生成时转换为敌方技能，例如远程弹幕、爆炸区、护盾吸收或召唤武装。
5. UI 和档案展示“夺取来源—转换结果—当前等级”。

<span style="color:#EF6C00">**[Codex补充]** 夺取不应直接复制玩家每秒伤害；以技能模板和强度预算转译，避免高阶玩家制造不可解精英。</span>

## 6. Boss 与下行解锁

- <span style="color:#2E7D32">**[已实装]** 当前 Boss 具有独立 HUD、阶段变化、召唤/远程等行为和清房结果。</span>
- <span style="color:#1565C0">**[用户设计]** Boss 死亡后必须产生专用下行钥匙，作为下一层路线的唯一权限来源。</span>
- <span style="color:#EF6C00">**[Codex补充]** Boss 系统只发出一次 `boss_defeated` 与奖励清单；关卡系统根据事件签发钥匙并解锁门资格，Boss 脚本不直接寻找门节点。</span>
- <span style="color:#EF6C00">**[Codex补充]** Boss 内容表应逐步从单一通用模板扩展为每个 Boss 楼层的独立内容 ID、技能阶段和资产。</span>

## 7. 施工阶段

1. 固定 `EncounterRequest / EncounterPlan`，让正式 3D 成为唯一刷怪入口。
2. 建立 12 行 `EliteDefinition` 并实现 `EliteRosterService`。
3. 迁移两只原型和历史存档，清除对旧 `RoomGameMode` 的运行依赖。
4. 实现唯一预约、成长结算和夺械转译。
5. 将 Boss 奖励改为专用钥匙事件，并与关卡门事务联测。
6. 为每种怪、每只精英和每个 Boss 建立自动化/场景验收。

## 8. 验收标准

- [ ] 六种普通怪和 Boss 的正式数值与数据库一致。
- [ ] 开门创建的敌人实例与进房激活的是同一批对象。
- [ ] 敌人生成失败有诊断并能安全结束房间，不会卡死。
- [ ] 12 个精英稳定 ID 唯一，任意时刻同一 ID 最多一个预约/实例。
- [ ] 精英逃脱、死亡、场景卸载和崩溃恢复均正确释放预约。
- [ ] 精英成长与夺取枪械可跨局保存并在正式 3D 再现。
- [ ] 旧精英档案能够迁移，失败时保留备份且不生成重复精英。
- [ ] Boss 死亡事件只触发一次，专用钥匙只签发一次。
- [ ] 普通钥匙不能开启 Boss 下行门，专用钥匙不能开启普通门。
- [ ] 更换敌人 Mesh/动画不改变 AI、碰撞、生命、技能与掉落。
