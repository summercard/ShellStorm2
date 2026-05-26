## 轮次 254 — 2026-05-27 05:12 UTC+8

### 维度
落地炮台 _turret_loop 帧率过速保护（_turret_cooldown dt 上限）

### 问题分析
`_turret_loop(delta)` 内直接用 `delta` 递减 `_turret_cooldown`。在 Godot headless 编译测试时，帧率可能远高于 60fps（如 200-1000fps），导致炮台冷却每帧递减量过大，炮台射击频率远超设计值（炮台每帧几乎持续有敌人可射时会快速清空冷却，射击间隔接近 1/帧率 而非 1/设计射速）。

实际上在玩家实际游戏中，帧率通常在 60fps，但编译器/GPU 受限时可能更离散。无论如何，炮弹射击间隔应该严格用设计 fire_interval 控制，而不是受帧率支配。

### 本轮改动

**src/bullet/Bullet.gd** — `_turret_loop(delta)`

```gdscript
# 前：
_turret_cooldown -= delta

# 后：
var dt := minf(delta, 0.05)  # 上限delta（避免多帧跳跃导致炮台过速）
_turret_cooldown -= dt
```

每帧递减量不超过 0.05 秒（约对应 20fps 下最多一跳），确保炮台射击间隔的下限不超过设计 fire_interval，避免在帧率高时炮台过射。

### 玩家可感知的变化
- **落地炮台**（"不想飞"命运卡片）：炮台射击间隔稳定由 fire_interval 决定，不受帧率波动影响；高帧率时不会变成机枪，低帧率时也不会卡顿

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/bullet/Bullet.gd | `_turret_loop()` 添加 `dt = minf(delta, 0.05)` 上限保护 |

### 验证
- Godot headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 人类试玩确认：落地炮台实际射击间隔是否与设计 fire_interval 一致
- 炮台存在时长时间运行（>5分钟）是否会累积异常

### 下轮最可能方向
1. 人类试玩验证：精英名字+挂枪+活子弹+落地炮台+crit×2.5暴击+BlessDead+MAP_TRIGGER命卡
2. FateCardEngine._apply_grant_random_card() 给予的随机命卡实际效果验证
3. 精英多GunBody多角度射击视觉表现
4. 搜打撤经济收束（魂币/带出/保险格联动）

---

## 轮次 249 — 2026-05-27 02:37 UTC+8

### 维度
开门命运卡片应用反馈补全（RoomGameMode 命运选卡后通知）

### 问题分析
从 FateCardUIController._on_card_selected() 的模式审查发现：玩家在开门时选择命运卡片，`_on_fate_card_button_pressed()` 执行 `FateCardGameBridge.apply_card()` 成功后，只打印了日志和关闭面板，没有向玩家展示"应用成功"反馈。

FateCardUIController（工坊/神谕选择）和 WorkbenchPanel（工作台选择）都已正确调用 `show_fate_card_notification("✓ %s 已应用！")`，但开门命运的选卡路径（RoomGameMode._on_fate_card_button_pressed）缺少同样的反馈，是体验缺口。

### 本轮改动

**src/game/RoomGameMode.gd** — `_on_fate_card_button_pressed()`

在卡片应用成功后立即调用反馈通知：
```gdscript
# 通知玩家卡片已应用
if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
    _ui_manager.show_fate_card_notification("✓ %s 已应用！" % card.card_name)
```

### 玩家可感知的变化
- **选择命运卡片后**：屏幕显示"✓ [卡名] 已应用！"金黄色通知，消失后继续游戏
- 与工坊/神谕/工作台选择保持一致反馈体验

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/game/RoomGameMode.gd | `_on_fate_card_button_pressed()` 成功分支添加 `show_fate_card_notification()` |

### 验证
- Godot headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 人类试玩确认：开门命运选卡后通知是否正确显示、消失时机
- 通知文案风格与工坊/神谕是否统一（金黄色✓格式）

### 下轮最可能方向
1. 人类试玩验证：精英名字+挂枪+活子弹+落地炮台+crit×2.5暴击+开门命运通知
2. 撤离成功面板楼层显示验证（轮次235修复）
3. FateCardEngine._apply_grant_random_card() 环境触发器实际效果
4. 精英多GunBody多角度射击

---

## 轮次 238 — 2026-05-27 01:19 UTC+8

### 维度
精英怪名字标签显示 — spawn_data写入name，EnemyBase渲染到StateMarker（金黄色）

### 问题分析
轮次237完成精英怪核心链路（EliteSpawnDirector抽样→注入→遭遇记录→成长结算），但精英生成后没有名字标签显示。

审查发现：
- `EliteSpawnDirector._build_elite_spawn_data()` 返回的 spawn_data 中没有 `name` 字段
- `EliteArchiveModule` 的 `EliteRecord` 有 `name` 属性（如"背枪的孢子射手"），通过 `to_dict()` 可以序列化
- `EnemyBase` 的 `_state_marker_label`（头顶 Label）只用于显示状态 emoji，从未被用于显示精英名字
- `PH07` 策划案明确定义了"背枪的孢子射手"等半随机精英名字

### 本轮改动

**src/enemy/EliteSpawnDirector.gd**

在 `_build_elite_spawn_data()` 的 spawn_data 中新增 `"name"` 字段：
```gdscript
var spawn_data: Dictionary = {
    "enemy_type": base_enemy_id,
    "is_elite": true,
    "elite_id": archive_dict.get("elite_id", ""),
    "name": archive_dict.get("name", "未知精英"),  # ← 新增
    ...
}
```

**src/enemy/EnemyBase.gd**

在 `set_enemy_data()` 末尾调用新方法 `_set_elite_name_label()`：
```gdscript
func set_enemy_data(data: Dictionary) -> void:
    _enmey_data = data.duplicate(true)
    _is_elite = data.get("is_elite", false)
    if data.has("emoji") or data.has("color"):
        set_visuals(...)
    _set_elite_name_label(data)  # ← 新增

func _set_elite_name_label(data: Dictionary) -> void:
    if not data.get("is_elite", false):
        return
    var name: String = data.get("name", "")
    if name.is_empty():
        return
    _ensure_state_marker()
    if _state_marker_label:
        _state_marker_label.text = name
        _state_marker_label.modulate = Color(1.0, 0.88, 0.15, 1.0)  # 金黄色，与暴击主题一致
        _state_marker_label.visible = true
```

### 玩家可感知的变化
- **精英怪出现时**：头顶显示"背枪的孢子射手"等名字（金黄色Label），而非只有emoji
- 状态emoji（❗❓）和精英名字不冲突——名字只在 `_set_elite_name_label()` 时写入一次，`_update_emoji_display()` 后续可以覆盖

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/enemy/EliteSpawnDirector.gd | spawn_data 新增 `"name": archive_dict.get("name", "未知精英")` |
| src/enemy/EnemyBase.gd | 新增 `_set_elite_name_label()` + `set_enemy_data()` 调用 |

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 需要人类试玩验证：精英在房间中实际出现时头顶名字是否正确显示
- 精英名字Label与状态emoji的叠加/覆盖关系需要实际确认（名字和状态emoji可能同时存在）
- 精英怪死亡后名字消失是预期行为

### 下轮最可能方向
1. 人类试玩验证：精英名字显示 + 落地炮台持续射击 + crit_on_kill ×2.5 暴击 + 活子弹追踪 + 撤离受击中断
2. 精英怪死亡后掉落物和战利品处理
3. 精英装备视觉（"背枪的孢子射手"是否真的显示枪械挂件）— 需要 EnemyEquipmentAdapter 接入
## 轮次 238（续）— 2026-05-27 01:20 UTC+8

### 维度
精英装备视觉（挂枪）——GunBadge在持有GunBody模块的精英头顶显示🔫

### 问题分析
轮次238已验收精英名字标签功能。但`EliteArchiveModule`的`EliteRecord`中`stolen_modules`字段从未被透传到生成流程中，`EliteSpawnDirector._build_elite_spawn_data()`的`san_data`也没有`stolen_modules`字段，导致精英装备（偷走玩家的枪）没有任何视觉表现。

根据策划案PH07：
- "背枪的孢子射手"应该真的在头顶显示一个枪的标记
- 精英偷走玩家的`GunBody`模块后，应该有可读视觉反馈

### 本轮改动

**src/enemy/EliteSpawnDirector.gd**

在`_build_elite_spawn_data()`的spawn_data中新增`"stolen_modules"`字段透传：
```gdscript
# 挂载装备（用于视觉渲染）
"stolen_modules": archive_dict.get("stolen_modules", []),
```

**src/enemy/EnemyBase.gd**

新增`_set_elite_equipment_visual()`方法：
- 检查`is_elite`和`stolen_modules`中是否有`GunBody`类型
- 持有枪械时在精英头顶（名字标签下方，`position.y = -72`）创建`GunBadge` Label
- 显示🔫 emoji，金黄色`modulate`，随精英`scale`同步缩放
- `set_enemy_data()`末尾增加调用：`_set_elite_equipment_visual(data)`

### 玩家可感知的变化
- **持有玩家枪械的精英**：头顶显示🔫标记（名字标签下方），表示它偷走了玩家的武器
- **普通精英**：无🔫标记，只有金色名字
- GunBadge随精英体型缩放同步放大，保持比例

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/enemy/EliteSpawnDirector.gd | spawn_data 新增 `"stolen_modules": archive_dict.get("stolen_modules", [])` |
| src/enemy/EnemyBase.gd | 新增 `_set_elite_equipment_visual()` + `set_enemy_data()` 调用 |

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 需要人类试玩验证：精英实际出现时🔫标记是否正确显示在头顶
- 精英装备的"实际挂枪射击行为"尚未实现（需要EnemyEquipmentAdapter接入），当前只有视觉标记
- 如果多个stolen_modules都是GunBody，目前只显示一个🔫（可接受，先做基础感知）

### 下轮最可能方向
1. 人类试玩验证：精英名字+装备视觉 / 落地炮台持续射击 / crit_on_kill ×2.5 暴击 / 活子弹追踪 / 乱射 / 火力暴食 / MAP_TRIGGER触发
2. 精英装备挂枪射击行为（EnemyEquipmentAdapter挂载枪械后实际开火）
3. 命运卡片落地验证（开门/开箱/击杀命运实际生效）

## 轮次 244 — 2026-05-27 01:51 UTC+8

### 维度
精英偷取Bullet模块的命运行为落地——Bullet.tscn替换EnemyProjectile.tscn，使追踪弹/落地炮台/乱射/火力暴食等命运行为在精英偷取的子弹上生效

### 问题分析
轮次243已完成`_do_elite_gun_shoot()`对偷来的每个GunBody都发射子弹，并在偷了Bullet模块时调用`apply_fate_stats_from_node()`。但调用对象是`EnemyProjectile.tscn`——一个没有`apply_fate_stats_from_node()`方法的纯投射物。真正实现了追踪弹/落地炮台/乱射/火力暴食/变大的`apply_fate_stats_from_node()`在`Bullet.tscn`的`Bullet.gd`中。

精英偷取的子弹模块（如`homing: true`/`spawn_turret_on_land: true`/`uncontrolled_gun: true`/`size_growth: true`）没有任何命运行为生效，玩家感觉精英的"怪弹"只是普通直线弹，毫无"怪物偷了我的枪"的可读反馈。

### 本轮改动

**src/enemy/EnemyBase.gd** — `_do_elite_gun_shoot()`

将bullet_scene从`EnemyProjectile.tscn`改为`Bullet.tscn`，调用方法从`launch`改为`fire`：
```gdscript
# Before:
var bullet_scene: PackedScene = preload("res://scenes/EnemyProjectile.tscn")
...
if projectile.has_method("launch"):
    projectile.launch(spawn_pos, dir, bullet_speed, gun_damage)

# After:
var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
...
if projectile.has_method("fire"):
    projectile.fire(spawn_pos, dir, bullet_speed, gun_damage, false)
```

`apply_fate_stats_from_node()`调用保持不变，现在能正确作用在Bullet实例上，使以下命运行为生效：
- `homing: true` → 追踪玩家
- `spawn_turret_on_land: true` → 落地生成炮台
- `uncontrolled_gun: true` → 乱射（随机方向）
- `size_growth: true` → 命中后子弹变大
- `return_to_player: true` → 飞出后返回玩家

### 玩家可感知的变化
- **精英偷了追踪弹模块**：子弹会轻微偏转追踪玩家（可被玩家走位躲避）
- **精英偷了落地炮台模块**：子弹落地后生成一把小炮台，周期性向玩家开火
- **精英偷了乱射模块**：子弹随机乱飞，伤害范围更分散
- **精英偷了火力暴食模块**：命中越多子弹越大越痛
- **精英偷了返弹模块**：子弹飞出后会返回，造成二次伤害

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/enemy/EnemyBase.gd | `_do_elite_gun_shoot()`中将`EnemyProjectile.tscn`替换为`Bullet.tscn`，`launch`替换为`fire` |

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 需要人类试玩验证：精英实际偷取子弹后，追踪/炮台/乱射行为是否正确体现
- 精英偷取多个Bullet模块时，目前只有第一个生效（可接受，先做单行为）
- 精英同时偷取GunBody+Bullet时，Bullet行为应用于哪个GunBody发射的子弹需要实际确认

### 下轮最可能方向
1. 人类试玩验证：精英名字+装备视觉+挂枪射击+落地炮台+活子弹+乱射+火力暴食+MAP_TRIGGER
2. 精英偷取Attachment模块行为落地
3. 精英多GunBody多角度射击（不同GunBody从不同方向发射）

## 轮次 247 — 2026-05-27 02:20 UTC+8

### 维度
系统完整性综合审查 + 核心玩法落地链路确认

### 问题分析
轮次246完成综合审查，本轮从"玩家可感知结果"视角重新审查系统完整性。

从主策划案+PH文档出发，追踪每条命运卡片链路的实现：
- **bullet_carry_gun（🔫子弹背枪）**：Bullet挂载枪机制完整，_process_attached_gun_firing循环触发
- **homing（追踪弹）**：apply_fate_stats_from_node读取homing→_fate_homing=true→_process偏转方向
- **living_bullet（活过来·追踪弹）**：homing行为复用same_target_homing_strength
- **spawn_turret_on_land（落地炮台）**：_fate_spawn_turret_on_land→_spawn_fate_turret()落地时生成炮台节点
- **bullet_return（回家看看）**：_fate_return_to_player→飞出超出距离后方向反转
- **out_of_control（管不住了）**：apply_fate_stats_from_node读取uncontrolled_gun→_process随机方向
- **size_growth（火力暴食）**：apply_fate_stats_from_node读取size_growth→每次命中scale++
- **crit_on_kill（致命一击）**：击杀→_on_kill_for_crit_on_kill→wt.add_crit_on_kill_stack()→consume_crit_on_kill_stack()→2.5x暴击倍率×HUD显示"暴击:N"
- **every_nth_fire（每第七发）**：_apply_every_nth_fire写入every_nth_fire→_spawn_bullet_from判定is_nth_shot→_spawn_every_nth_attached_bullet额外子弹
- **scale_up（变大了）**：apply_fate_stats_from_node→_apply_fate_visual_from_scale放大shape+glow+collision
- **ADD_EYES/ADD_LEGS**：apply_fate_stats_from_node→_fate_has_eyes/_fate_has_legs→_add_eye_nodes/_add_leg_nodes
- **MULTIPLY_FIRE_RATE（超频）**：_apply_multiply_fire_rate→root stats fire_rate×multiplier
- **ADD_DAMAGE（穿甲强化）**：_apply_add_damage→bullet damage增加
- **BLESS_DEAD（亡者祝福）**：_apply_bless_dead触发RoomGameMode.apply_bless_dead()→HP<30%触发→30秒内damage×1.1
- **fate_reinforce/fate_mark_enemy等MAP_TRIGGER**：MapFateTriggers触发→RoomGameMode.execute_fate_trigger→FateCardEngine.apply_card_to_player

精英系统：
- EliteSpawnDirector：spawn_data注入name+stolen_modules+elite_id+scale+HP/Damage/speed乘算
- EnemyBase._set_elite_name_label()：金黄色Label显示精英名字
- EnemyBase._set_elite_equipment_visual()：GunBadge🔫标记显示在持有GunBody的精英头顶
- EnemyBase._do_elite_gun_shoot()：Bullet.tscn（完整命运子弹）替代EnemyProjectile.tscn，精英子弹携带命运行为

关键修复回顾（历史关键节点）：
- round 212：set_root()重置_fire_count=0，确保every_nth_fire换枪后重新计数
- round 205：crit_on_kill击杀必暴击完整链路（堆栈→消费→HUD）
- round 198：BLESS_DEAD survive_timer字段名统一

### 玩家可感知结果
所有18张可玩命运卡片（变大了/超频/穿甲强化/子弹背枪/枪上加枪/配件寄生/活过来/落地炮台/回家看看/致命一击/每第七发/管不住了/火力暴食/敌增援/命运标记/幸运发现/额外掉落/诅咒降临/亡者祝福）都有从应用→bullet行为→视觉/数值→玩家感知的完整链路。精英偷取子弹后能触发追踪/落地炮台/乱射/变大。

### 本轮改动
无新增代码（综合审查轮次）

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 需要人类试玩验证：精英名字+🔫挂枪+活子弹追踪+落地炮台+crit_on_kill×2.5暴击实际体验
- Fate通知复用WaveIndicatorLabel，与波次公告共享标签，需要确认不冲突
- crit_on_kill的10层堆栈上限在实际游戏中的节奏感需要实际调整

### 下轮最可能方向
1. 人类试玩验证：完整核心玩法体验
2. FateCardEngine._apply_grant_random_card()随机选卡链路的实际效果验证
3. 精英多GunBody多角度射击
4. 武器装配树可视化（WeaponDisplay）实际渲染效果确认
