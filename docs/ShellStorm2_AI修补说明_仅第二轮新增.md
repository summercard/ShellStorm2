# ShellStorm2 当前版本后续修补说明（仅包含新增/仍需修的内容）

> 用途：把这份文档直接交给代码 AI / Cursor / Claude Code，让它只修当前版本仍未解决的问题。  
> 注意：不要重复修改第一轮已经完成的内容。  
> 当前版本基础：用户已完成第一轮修复，项目来自 `ShellStorm2(6).zip`。

---

## 一、修补范围

只允许重点修改以下 4 个文件：

```text
src/enemy/components/EnemySkillComponent.gd
src/enemy/EnemyBase.gd
src/map/RoomWaveSpawner.gd
src/game/CoreCombatMode.gd
```

不要改以下已经完成的内容：

```text
撤离 14s / 9s / 5s 波次逻辑
EnemyTypes.gd 中 inject_xxx_skill(enemy) 返回组件并 add_child 的修复
BaseMenu.gd 建筑入口面板
verify_bullet_trail_flow.tscn 删除
EnemySkillComponent.gd 重复函数清理
EnemyBase.gd 中 on_taken_damage / on_low_hp / on_death / on_engaged 基础事件入口
```

---

# 二、必须修复的问题 1：triggered 技能配置没有真正使用 cfg

## 文件

```text
src/enemy/components/EnemySkillComponent.gd
```

## 问题说明

当前 `register_triggered_skill()` 虽然已经写了：

```gdscript
var cfg := _normalize_skill_config(config)
```

但后面仍然在使用旧的 `config`：

```gdscript
"cooldown": config.get("cooldown", 8.0),
"config": config,
```

这样会导致嵌套在 `config` 字段里的技能参数没有被展开，触发型技能仍然可能使用默认值。

## 目标改法

找到 `register_triggered_skill()`，把它改成下面这种结构：

```gdscript
func register_triggered_skill(skill_id: String, config: Dictionary) -> void:
	var cfg := _normalize_skill_config(config)
	var skill: Dictionary = {
		"id": skill_id,
		"type": "triggered",
		"trigger": cfg.get("trigger", "on_hit"),
		"cooldown": cfg.get("cooldown", 8.0),
		"timer": 0.0,
		"config": cfg,
	}
	_triggered_skills.append(skill)
```

## 验收标准

搜索 `register_triggered_skill()` 内部，不应再出现：

```gdscript
config.get("cooldown"
"config": config
```

允许函数参数名仍然叫 `config`，但真正进入技能字典的必须是 `cfg`。

---

# 三、必须修复的问题 2：真实房间刷怪路径没有注入基础怪物技能

## 问题说明

第一轮已经修了 `EnemyTypes.gd`，但真实游戏中主要刷怪路径并不一定走 `EnemyTypes.gd`。

当前真实刷怪路径主要包括：

```text
src/map/RoomWaveSpawner.gd
src/game/CoreCombatMode.gd
```

这两个文件通常是直接实例化 `Enemy.tscn`，所以房间里刷出来的普通怪物仍然可能没有挂载 `EnemySkillComponent`。

需要在真实刷怪路径里，根据怪物类型调用新的统一注入方法。

---

# 四、在 EnemyBase.gd 添加统一基础技能注入方法

## 文件

```text
src/enemy/EnemyBase.gd
```

## 添加目标

新增一个公开方法：

```gdscript
func inject_basic_skill_for_kind(kind: String) -> void:
```

这个方法根据怪物类型给当前 enemy 节点注入对应基础技能组件。

## 建议添加位置

放在精英技能注入相关函数附近，或放在 `_ready()` 后面也可以。  
要求是 `RoomWaveSpawner.gd` 和 `CoreCombatMode.gd` 能通过：

```gdscript
enemy.call("inject_basic_skill_for_kind", enemy_type)
```

调用到它。

## 目标代码

```gdscript
func inject_basic_skill_for_kind(kind: String) -> void:
	var normalized := String(kind).to_lower()

	# 避免重复注入普通技能组件
	for child in get_children():
		if child.has_signal("skill_triggered") and not child.has_signal("elite_skill_triggered"):
			return

	var script_res := load("res://src/enemy/components/EnemySkillComponent.gd")
	if script_res == null:
		return

	var comp: Node = null

	match normalized:
		"chaser", "basic", "melee":
			comp = script_res.inject_chaser_skill(self)
		"ranged", "ranged_caster", "caster", "shooter":
			comp = script_res.inject_ranged_skill(self)
		"summoner":
			comp = script_res.inject_summoner_skill(self)
		"tank", "shielded", "brute":
			comp = script_res.inject_tank_skill(self)
		"bomber", "exploder", "suicide":
			comp = script_res.inject_bomber_skill(self)
		"trapper", "ambusher":
			comp = script_res.inject_trapper_skill(self)
		_:
			comp = script_res.inject_chaser_skill(self)

	if comp:
		add_child(comp)
		comp.set_owner(self)
```

## 注意

如果项目当前怪物类型名不是这些，请根据现有 `RoomWaveSpawner.gd` 和 `CoreCombatMode.gd` 里的 enemy type 字符串补充 match 分支。

至少要覆盖：

```text
chaser
ranged_caster
summoner
shielded
exploder
ambusher
```

---

# 五、修复 EnemyBase.gd 中 awareness_enabled=false 时普通技能不 tick

## 文件

```text
src/enemy/EnemyBase.gd
```

## 问题说明

当前 `_physics_process()` 中可能已经调用了：

```gdscript
_tick_skill_components(delta)
```

但 `_dispatch_behavior()` 中仍然可能保留旧逻辑：

```gdscript
for child in get_children():
	if child.has_method("tick") and child.has_signal("elite_skill_triggered"):
		child.tick(delta)
```

真实房间刷怪时，`RoomWaveSpawner.gd` 里可能设置：

```gdscript
enemy.awareness_enabled = false
```

这会导致代码走 `_dispatch_behavior()` 路径。  
如果这里仍然只 tick `elite_skill_triggered`，普通怪物技能组件不会运行。

## 目标改法

在 `EnemyBase.gd` 中搜索：

```gdscript
child.has_signal("elite_skill_triggered")
```

如果发现类似下面的片段：

```gdscript
for child in get_children():
	if child.has_method("tick") and child.has_signal("elite_skill_triggered"):
		child.tick(delta)
```

替换为：

```gdscript
_tick_skill_components(delta)
```

## 验收标准

`EnemyBase.gd` 中普通运行路径不应只 tick 精英技能。  
允许 `_tick_skill_components()` 内部判断：

```gdscript
child.has_signal("skill_triggered") or child.has_signal("elite_skill_triggered")
```

---

# 六、修复精英技能注入时创建空组件的问题

## 文件

```text
src/enemy/EnemyBase.gd
```

## 问题说明

当前 `_inject_elite_active_skills()` 可能类似这样：

```gdscript
var comp: Node = skill_comp_class.new(self, tier)
add_child(comp)
skill_comp_class.inject_elite_skills(self, modifier_id, tier)
```

这会创建两个组件：

```text
第一个：空组件
第二个：inject_elite_skills() 内部真正创建并添加的技能组件
```

这会造成调试混乱，也可能让某些信号连接到空组件上。

## 目标改法

不要手动 `new()` 一个空组件。  
直接接收 `inject_elite_skills()` 返回的真实组件。

目标结构：

```gdscript
func _inject_elite_active_skills() -> void:
	if not is_elite:
		return

	var modifier_id := String(elite_modifier_id)
	if modifier_id.is_empty():
		return

	var skill_comp_class := load("res://src/enemy/components/EnemySkillComponent.gd")
	if skill_comp_class == null:
		return

	var comp: Node = skill_comp_class.inject_elite_skills(self, modifier_id, elite_tier)
	if comp == null:
		return

	if not comp.is_inside_tree():
		add_child(comp)

	if comp.get_parent() != self:
		if comp.get_parent():
			comp.get_parent().remove_child(comp)
		add_child(comp)

	if comp.has_signal("elite_skill_triggered") and not comp.elite_skill_triggered.is_connected(_on_elite_skill_triggered):
		comp.elite_skill_triggered.connect(_on_elite_skill_triggered)
```

如果项目当前变量名不是 `elite_tier`，使用项目已有的 tier 变量。  
不要引入不存在的变量名。

## 验收标准

`_inject_elite_active_skills()` 内部不应再出现：

```gdscript
skill_comp_class.new(self, tier)
```

也不应先 `add_child(comp)` 后再调用 `inject_elite_skills()` 创建第二个组件。

---

# 七、在 RoomWaveSpawner.gd 注入真实房间普通怪技能

## 文件

```text
src/map/RoomWaveSpawner.gd
```

## 问题说明

真实房间刷怪时通常在这里实例化 `Enemy.tscn`。  
需要在 enemy 创建完成、enemy_type 已确定后调用：

```gdscript
enemy.call("inject_basic_skill_for_kind", enemy_type)
```

## 操作步骤

找到实例化敌人的位置，通常类似：

```gdscript
var enemy = enemy_scene.instantiate()
```

或者：

```gdscript
var enemy: Node2D = enemy_scene.instantiate()
```

在设置敌人类型、属性、位置之后，加入：

```gdscript
if enemy.has_method("inject_basic_skill_for_kind"):
	enemy.call("inject_basic_skill_for_kind", enemy_type)
```

如果该文件里变量名不是 `enemy_type`，请使用真实代表怪物种类的变量，例如：

```gdscript
kind
type_id
monster_type
enemy_kind
```

## 推荐位置

放在：

```gdscript
enemy.global_position = spawn_pos
```

以及设置完怪物类型之后。  
放在 `add_child(enemy)` 前后都可以，但建议在 `add_child(enemy)` 之后调用，更稳妥：

```gdscript
parent.add_child(enemy)
enemy.global_position = spawn_pos

if enemy.has_method("inject_basic_skill_for_kind"):
	enemy.call("inject_basic_skill_for_kind", enemy_type)
```

## 验收标准

`RoomWaveSpawner.gd` 中应该能搜索到：

```gdscript
inject_basic_skill_for_kind
```

---

# 八、在 CoreCombatMode.gd 注入街机/测试波次普通怪技能

## 文件

```text
src/game/CoreCombatMode.gd
```

## 问题说明

除房间刷怪外，`CoreCombatMode.gd` 里也可能直接实例化 `Enemy.tscn`。  
这条路径也要补基础技能注入，否则不同模式下怪物表现不一致。

## 操作步骤

找到敌人实例化位置，通常类似：

```gdscript
var enemy = enemy_scene.instantiate()
```

或：

```gdscript
var enemy: Node2D = enemy_scene.instantiate()
```

在确定怪物类型后加入：

```gdscript
if enemy.has_method("inject_basic_skill_for_kind"):
	enemy.call("inject_basic_skill_for_kind", enemy_type)
```

如果该文件没有明确 `enemy_type`，但有 wave 配置或随机类型变量，用那个变量。

如果完全没有类型变量，可先注入默认 chaser：

```gdscript
if enemy.has_method("inject_basic_skill_for_kind"):
	enemy.call("inject_basic_skill_for_kind", "chaser")
```

## 验收标准

`CoreCombatMode.gd` 中应该能搜索到：

```gdscript
inject_basic_skill_for_kind
```

---

# 九、编译检查命令

改完后在项目根目录执行：

```bash
godot --headless --check-only --path .
```

如果本机命令是 Godot 4：

```bash
godot4 --headless --check-only --path .
```

必须通过。

---

# 十、静态自检命令

## 1. 检查重复函数

```bash
python3 - <<'PY'
import re, collections, pathlib

for rel in [
    "src/enemy/components/EnemySkillComponent.gd",
    "src/enemy/EnemyBase.gd",
]:
    p = pathlib.Path(rel)
    by = collections.defaultdict(list)
    for i, line in enumerate(p.read_text().splitlines(), 1):
        m = re.match(r'\s*func\s+(\w+)\s*\(', line)
        if m:
            by[m.group(1)].append(i)
    dups = {k:v for k,v in by.items() if len(v) > 1}
    print(rel, dups or "OK")
PY
```

期望输出：

```text
src/enemy/components/EnemySkillComponent.gd OK
src/enemy/EnemyBase.gd OK
```

## 2. 检查真实刷怪路径是否接入

```bash
grep -R "inject_basic_skill_for_kind" -n src/enemy src/map src/game
```

至少应出现：

```text
src/enemy/EnemyBase.gd
src/map/RoomWaveSpawner.gd
src/game/CoreCombatMode.gd
```

## 3. 检查 triggered skill 是否仍使用旧 config

```bash
grep -n "func register_triggered_skill" -A20 src/enemy/components/EnemySkillComponent.gd
```

确认技能字典里是：

```gdscript
"cooldown": cfg.get(...)
"config": cfg
```

---

# 十一、试玩验收清单

改完并编译通过后，按下面顺序试玩：

```text
1. 进入普通战斗房。
2. 确认真实刷出来的 chaser / ranged_caster / summoner / shielded / exploder / ambusher 都不会报错。
3. ranged_caster 应该会触发远程技能或弹幕技能。
4. summoner 应该能触发召唤、治疗或集结相关技能。
5. exploder 低血时应能提前引爆，而不是无反应。
6. ambusher 受击时应能触发孢子/陷阱/隐身相关技能。
7. shielded 低血时应能触发狂暴或防御类技能。
8. 进入撤离房，确认撤离守点刷出的怪物也能触发普通技能。
9. 确认精英怪只挂一个有效精英技能组件，不出现重复技能组件或空组件。
```

---

# 十二、禁止事项

本轮不要做这些事：

```text
不要重构整个 EnemyBase.gd
不要重写 EnemySkillComponent.gd
不要新增第二关怪物
不要改地图生成逻辑
不要改武器系统
不要改 UI 系统
不要再次修改撤离波次时间
不要再次修改 BaseMenu.gd
```

本轮目标只有一个：

```text
让当前版本真实刷出来的普通怪物和精英怪技能组件真正接入、真正 tick、真正使用正确配置。
```
