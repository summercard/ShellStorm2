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
- <span style="color:#2E7D32">**[已实装｜2026-08-06平衡]** 3D Profile原始生命仍为普通怪42–112、Boss 520；最终运行时统一为普通怪×3（126–336）、Boss×10（基线5200），伤害不变。所有怪物最终移动速度为旧值70%。</span>
- <span style="color:#2E7D32">**[已实装｜2026-08-07战斗可读性]** 七种敌人使用以旧模型比例为基准的独立体型：炸弹果0.8；远程、追猎与伏击1.0；护卫与召唤1.2；Boss1.5。模型、角色碰撞、头顶锚点同步缩放。所有敌人都有与角色 HUD 同系的简洁头顶血条：单张 Sprite3D 绘制深红黑底框与红色生命填充，低血转暖橙；血条脱离怪物旋转层级、固定在头顶世界坐标，并由原生 Billboard 永久朝向摄像机。怪物应用真实内容种类后会同步重建对应条宽，所有生命修饰器和伤害都立即按实际 `current_hp / max_hp` 重绘同一张血条纹理。Boss继续保留HUD总血条并使用更宽的头顶条。</span>
- <span style="color:#2E7D32">**[已实装｜2026-08-07战斗可读性]** 敌人每次实际扣血都会在头顶生成3D飘字：普通伤害为珊瑚红、重击为暖橙、暴击为金黄星标；使用 SF Mono 风格的粗等宽终端字体（系统回退 Menlo/monospace），字号为原方案150%，文字先弹出、上浮并淡出，使用深蓝描边且始终朝向镜头。格挡的零伤害不生成误导飘字。</span>

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

<span style="color:#2E7D32">**[已实装｜关卡侧]** 已提交内容房不小于30×25m，并包含标准、宽、深、中、大与Boss竞技场；现有刷怪仍按房间类型/难度预算生成，不按面积无上限增怪。独立不可变 `EncounterPlan` 仍待进一步收敛。</span>

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
- <span style="color:#2E7D32">**[已实装]** Boss同时保留屏幕顶部总血条和头顶3D红色血条；头顶血条随当前/最大生命更新并保持面向镜头。</span>
- <span style="color:#2E7D32">**[已实装｜首批]** `floor_number % 5 == 0` 已由纯数据规划器判定；95F在11个主路/整备内容房后生成不可绕过Boss。90F、85F场景内容尚未扩展。</span>
- <span style="color:#1565C0">**[用户设计]** Boss 死亡后必须产生专用下行钥匙，作为下一层路线的唯一权限来源。</span>
- <span style="color:#EF6C00">**[Codex补充]** Boss 系统只发出一次 `boss_defeated` 与奖励清单；关卡系统根据事件签发钥匙并解锁门资格，Boss 脚本不直接寻找门节点。</span>
- <span style="color:#1565C0">**[用户设计]** 95F Boss 的专用门通向95→94真实楼梯间；全游戏关卡内唯一电梯固定在该楼梯间。电梯不是Boss房、普通楼层或随机房间内容。</span>
- <span style="color:#1565C0">**[用户设计]** 玩家进入95→94楼梯后的隔离间前必须收到旧区段未拾取物永久丢失提示；Boss死亡本身不卸载98–95F。</span>
- <span style="color:#EF6C00">**[Codex补充]** 90→89、85→84等后续Boss边界也使用隔离间释放上一Boss区段，但只有95→94楼梯间带电梯。</span>
- <span style="color:#EF6C00">**[Codex补充]** Boss只提供死亡事实和一次性钥匙奖励，不拥有隔离门、区段提交或卸载权限。旧区段只能在玩家完整进入隔离间且后门锁定后由关卡生命周期服务释放。</span>
- <span style="color:#EF6C00">**[Codex补充]** Boss 内容表应逐步从单一通用模板扩展为每个 Boss 楼层的独立内容 ID、技能阶段和资产。</span>

## 7. 施工阶段

1. 固定 `EncounterRequest / EncounterPlan`，让正式 3D 成为唯一刷怪入口。
2. 建立 12 行 `EliteDefinition` 并实现 `EliteRosterService`。
3. 以正式 3D 名册重新实现两只历史原型及存档迁移；旧 `RoomGameMode` 运行依赖已清除。
4. 实现唯一预约、成长结算和夺械转译。
5. <span style="color:#2E7D32">**[已完成首段]** Boss死亡签发一次性下行权限，并与95→94楼梯、唯一电梯、隔离提交和98–95F卸载完成专项联测；存档幂等恢复待补。</span>
6. 为每种怪、每只精英和每个 Boss 建立自动化/场景验收。

## 8. 验收标准

- [x] 六种普通怪与Boss统一应用普通HP×3/Boss HP×10、全体速度×0.70，并按种类应用可读体型层级；专项检查最终生命、速度、世界碰撞半径、头顶血条和受击3D飘字。
- [ ] 开门创建的敌人实例与进房激活的是同一批对象。
- [ ] 敌人生成失败有诊断并能安全结束房间，不会卡死。
- [ ] 12 个精英稳定 ID 唯一，任意时刻同一 ID 最多一个预约/实例。
- [ ] 精英逃脱、死亡、场景卸载和崩溃恢复均正确释放预约。
- [ ] 精英成长与夺取枪械可跨局保存并在正式 3D 再现。
- [ ] 旧精英档案能够迁移，失败时保留备份且不生成重复精英。
- [ ] Boss 死亡事件只触发一次，专用钥匙只签发一次。
- [ ] 95F、90F、85F……必然生成不可绕过 Boss 遭遇，普通层不误生成 Boss。
- [ ] 普通钥匙不能开启 Boss 下行门，专用钥匙不能开启普通门。
- [x] 98–95F只在玩家确认隔离并跨过隔离前门时卸载；Boss死亡、下行门开启和楼梯阶段不会直接卸载。
- [x] 首段生成快照中关卡内电梯只在95→94出现一次；普通层为0。90F、85F后无电梯规则已由生成分支固定，连续区段实机巡检待补。
- [ ] 更换敌人 Mesh/动画不改变 AI、碰撞、生命、技能与掉落。
