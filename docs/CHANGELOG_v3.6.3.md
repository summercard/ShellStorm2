# 补丁修复文档 v3.6.3

> 版本号：v3.6.3  
> 日期：2026-05-29  
> 优先级顺序：撤离波次 → 怪物技能接入 → 技能事件 → 重复函数 → 基地入口 → 测试场景清理

---

## ⚠️ apply 前必读

apply 后一定要本地跑 `--check-only` 验证。

```
godot --headless --check-only --path .
```

---

## 第 0 步：先建修复分支

```bash
cd ShellStorm2
git checkout -b fix/runtime-consistency-363
```

没有 git 的话，至少先复制一份项目备份。

---

## 第 1 步：修撤离中场波立即刷新的问题

**文件：** `src/game/RoomGameMode.gd`

### 1.1 在顶部常量区添加

找到：
```gdscript
const EXTRACTION_DEFENSE_DURATION := 14.0
```

改成：
```gdscript
const EXTRACTION_DEFENSE_DURATION := 14.0
const EXTRACTION_MID_WAVE_REMAINING := 9.0
const EXTRACTION_FINAL_WAVE_REMAINING := 5.0
```

### 1.2 修改 _update_extraction_defense()

找到当前逻辑：
```gdscript
if not _extraction_mid_wave_spawned and remaining > 5.0:
```

改成：
```gdscript
if not _extraction_mid_wave_spawned and remaining <= EXTRACTION_MID_WAVE_REMAINING and remaining > EXTRACTION_FINAL_WAVE_REMAINING:
```

并把 final wave 判断改成：
```gdscript
elif not _extraction_elite_wave_spawned and remaining <= EXTRACTION_FINAL_WAVE_REMAINING:
```

### 目标效果

撤离 14 秒倒计时：

```
14s：开始撤离，刷第一波
9s：刷中场波
5s：刷最终/精英波
0s：撤离成功
```

---

## 第 2 步：修基础怪物技能组件没有真正挂载的问题

**文件：** `src/enemy/EnemyTypes.gd`

当前写法是先创建一个空组件：
```gdscript
var skill_comp := SKILL_COMPONENT_SCRIPT.new()
enemy.add_child(skill_comp)
skill_comp.set_owner(enemy)
EnemySkillComponent.inject_chaser_skill(enemy)
```

问题是：`inject_chaser_skill()` 又创建了另一个组件，但没加到 enemy 上。

### 改法

每种怪物都改成：
```gdscript
var skill_comp := EnemySkillComponent.inject_chaser_skill(enemy)
enemy.add_child(skill_comp)
skill_comp.set_owner(enemy)
```

对应关系如下：

```gdscript
spawn_chaser    -> EnemySkillComponent.inject_chaser_skill(enemy)
spawn_ranged    -> EnemySkillComponent.inject_ranged_skill(enemy)
spawn_summoner  -> EnemySkillComponent.inject_summoner_skill(enemy)
spawn_tank      -> EnemySkillComponent.inject_tank_skill(enemy)
spawn_bomber    -> EnemySkillComponent.inject_bomber_skill(enemy)
spawn_trapper   -> EnemySkillComponent.inject_trapper_skill(enemy)
```

---

## 第 3 步：让 EnemyBase 真正 tick 基础怪物技能

**文件：** `src/enemy/EnemyBase.gd`

### 3.1 添加统一 tick 函数

放在 `_fire_timers()` 后面：
```gdscript
func _tick_skill_components(delta: float) -> void:
	for child in get_children():
		if child.has_method("tick") and (child.has_signal("skill_triggered") or child.has_signal("elite_skill_triggered")):
			child.tick(delta)


func _notify_skill_components(method_name: String, args: Array = []) -> void:
	for child in get_children():
		if child.has_method(method_name):
			child.callv(method_name, args)
```

### 3.2 替换原来的精英专用 tick

把这两处：
```gdscript
for child in get_children():
	if child.has_method("tick") and child.has_signal("elite_skill_triggered"):
		child.tick(delta)
```

替换成：
```gdscript
_tick_skill_components(delta)
```

需要替换的位置：
- `_physics_process()`
- `_dispatch_behavior()`

---

## 第 4 步：把受击、低血、死亡、进入战斗事件接入技能组件

**文件：** `src/enemy/EnemyBase.gd`

### 4.1 在进入 CHASE 时通知技能

在 `_transition_to()` 的 AIState.CHASE 分支里，找到：
```gdscript
if not was_chasing:
	enemy_entered_chase.emit(self, _last_known_player_pos)
```

改成：
```gdscript
if not was_chasing:
	enemy_entered_chase.emit(self, _last_known_player_pos)
	_notify_skill_components("on_engaged")
```

### 4.2 在 take_damage() 里通知受击和低血

在扣血前记录是否刚跨过低血线：
```gdscript
var was_above_low_hp := float(current_hp) / maxf(1.0, float(max_hp)) > 0.4
```

扣血、显示伤害数字之后，加：
```gdscript
var attacker_pos := global_position - hit_dir.normalized() * 64.0 if hit_dir.length_squared() > 0.0001 else global_position
_notify_skill_components("on_taken_damage", [amount, attacker_pos])

if _is_dead:
	return

if current_hp > 0 and was_above_low_hp and float(current_hp) / maxf(1.0, float(max_hp)) <= 0.4:
	_notify_skill_components("on_low_hp")
	if _is_dead:
		return
```

### 4.3 在 die() 里通知死亡事件

找到：
```gdscript
func die() -> void:
	if _is_dead:
		return
	_is_dead = true
```

改成：
```gdscript
func die() -> void:
	if _is_dead:
		return
	_notify_skill_components("on_death")
	_is_dead = true
```

这样 debris_on_death、spore_on_hit、low_hp_fury 这些触发型技能才有入口。

---

## 第 5 步：清理 EnemySkillComponent.gd

**文件：** `src/enemy/components/EnemySkillComponent.gd`

要做四件事。

### 5.1 删除重复函数

删除靠前的重复版本，保留后面的增强版本。

重复函数包括：
- `_exec_summoner_heal_aura`
- `_exec_tank_rock_throw`
- `_exec_bomber_charge_up`
- `_get_player`
- `_get_parent_scene`
- `_stun_player_if_contact`

删除后，用这个命令检查：
```bash
python3 - <<'PY'
import re, collections, pathlib
p = pathlib.Path("src/enemy/components/EnemySkillComponent.gd")
by = collections.defaultdict(list)
for i, line in enumerate(p.read_text().splitlines(), 1):
	m = re.match(r'\s*func\s+(\w+)\s*\(', line)
	if m:
		by[m.group(1)].append(i)
for name, lines in by.items():
	if len(lines) > 1:
		print(name, lines)
PY
```
应该没有输出。

### 5.2 修配置嵌套问题

在 `set_owner()` 后面加：
```gdscript
func _normalize_skill_config(config: Dictionary) -> Dictionary:
	var flat := config.duplicate(true)
	var inner = flat.get("config", null)
	if inner is Dictionary:
		for key in inner.keys():
			flat[key] = inner[key]
		flat.erase("config")
	return flat
```

然后把三个注册函数改成先 normalize：
```gdscript
func register_active_skill(skill_id: String, config: Dictionary) -> void:
	var cfg := _normalize_skill_config(config)
	var skill: Dictionary = {
		"id": skill_id,
		"type": "active",
		"cooldown": cfg.get("cooldown", 5.0),
		"timer": cfg.get("initial_delay", 1.0),
		"config": cfg,
	}
	_active_skills.append(skill)
```

`register_passive_skill()` 和 `register_triggered_skill()` 同理，都用 cfg，不要直接用 config。

### 5.3 补全 triggered 技能 ID 分支

把 `_execute_triggered_skill()` 的 match 改成支持这些别名：
```gdscript
match skill_id:
	"trapper_spore", "spore_on_hit":
		_exec_trapper_spore(cfg, ctx)
	"bomber_debris", "debris_on_death":
		_exec_bomber_debris(cfg, ctx)
	"ranged_escape_cloud", "close_quarter_retreat":
		_exec_ranged_escape_cloud(cfg)
	"ranged_flank_anticipation":
		_exec_ranged_flank_anticipation(cfg)
	"summoner_rally":
		_exec_summoner_rally(cfg)
	"tank_enrage", "low_hp_fury":
		_exec_tank_enrage(cfg)
	"bomber_early_detonation":
		_exec_bomber_early_detonation(cfg)
	"trapper_stealth":
		_exec_trapper_stealth(cfg)
```

### 5.4 修自爆怪低血提前引爆

找到：
```gdscript
_owner._is_dead = true
if _owner.has_method("take_damage"):
	_owner.take_damage(_owner.current_hp)
```

改成：
```gdscript
if _owner.has_method("_trigger_explosion"):
	_owner.call("_trigger_explosion")
elif _owner.has_method("die"):
	_owner.call("die")
```

原因：不能先把 `_is_dead` 设为 true，否则 `take_damage()` / `die()` 会直接 return。

---

## 第 6 步：修基地建筑升级入口

**文件：** `src/ui/BaseMenu.gd`

目标：点击建筑时先打开建筑面板，面板里有：
```
进入功能
升级建筑
关闭
```

### 6.1 添加入口场景表

放在 `BUILDING_INFO` 后面：
```gdscript
const BUILDING_ENTRY_SCENES := {
	0: "res://scenes/WorkshopMenu.tscn",
	3: "res://scenes/DivinationMenu.tscn",
	4: "res://scenes/VaultMenu.tscn",
	6: "res://scenes/MonsterArchiveMenu.tscn",
}
```

### 6.2 修改按钮点击逻辑

改成：
```gdscript
func _on_building_divination_pressed() -> void:
	_show_building_panel(3)

func _on_building_workshop_pressed() -> void:
	_show_building_panel(0)

func _on_building_vault_pressed() -> void:
	_show_building_panel(4)

func _on_building_archive_pressed() -> void:
	_show_building_panel(6)

func _on_building_fate_card_collection_pressed() -> void:
	_open_menu_scene("res://scenes/FateCardCollectionMenu.tscn")
```

新增：
```gdscript
func _open_menu_scene(scene_path: String) -> void:
	var menu_scene: PackedScene = load(scene_path)
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
		get_tree().get_root().add_child(menu)
```

### 6.3 在建筑面板按钮行里加"进入功能"

在 `_refresh_building_panel()` 里，创建 upgrade_btn 之前插入：
```gdscript
if BUILDING_ENTRY_SCENES.has(_selected_building_type):
	var enter_btn := Button.new()
	enter_btn.custom_minimum_size = Vector2(110, 44)
	enter_btn.text = "进入功能"
	enter_btn.pressed.connect(_on_enter_building_feature_pressed)
	btn_box.add_child(enter_btn)
```

再新增函数：
```gdscript
func _on_enter_building_feature_pressed() -> void:
	var scene_path: String = String(BUILDING_ENTRY_SCENES.get(_selected_building_type, ""))
	_hide_building_panel()
	if not scene_path.is_empty():
		_open_menu_scene(scene_path)
```

---

## 第 7 步：清理缺失测试脚本引用

**文件：** `verify_bullet_trail_flow.tscn`

它引用了不存在的：`res://verify_bullet_trail_flow.gd`

二选一：

**方案 A：**不用这个测试场景，删除
```bash
rm verify_bullet_trail_flow.tscn
```

**方案 B：**保留测试场景，补一个脚本

新建 `verify_bullet_trail_flow.gd`，内容先用最小占位：
```gdscript
extends Node

func _ready() -> void:
	print("[verify_bullet_trail_flow] placeholder loaded")
```
后面再补真正测试逻辑。

---

## 第 8 步：本地验证

### 8.1 先跑 Godot 编译检查

```bash
godot --headless --check-only --path .
```

如果你用的是 Godot 4.6 beta / dev 版，命令可能是：
```bash
godot4 --headless --check-only --path .
```

### 8.2 检查重复函数

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
```
src/enemy/components/EnemySkillComponent.gd OK
src/enemy/EnemyBase.gd OK
```

### 8.3 试玩验证顺序

先不要测全游戏，按这个顺序测：

```
1. 进入撤离房
2. 开始撤离
3. 确认中场波不是立刻刷出，而是在剩余约 9 秒时刷出
4. 确认最终波在剩余约 5 秒时刷出
5. 刷出 chaser/ranged/summoner/tank/bomber/trapper 各一只
6. 观察主动技能是否会触发
7. 打到低血，观察 low_hp/on_taken_damage/on_death 技能是否触发
8. 回基地，点击工坊/占卜/仓库/图鉴，确认先出现建筑面板，再能进入功能
```

---

## 推荐执行方式

最省事的做法：
```bash
cd ShellStorm2
git checkout -b fix/runtime-consistency-363
patch -p1 < /path/to/ShellStorm2_priority_fixes_gitstyle.patch
godot --headless --check-only --path .
```

如果 patch 冲突，就按上面的步骤手动改。

**优先顺序不要变：**
撤离波次 → 怪物技能接入 → 技能事件 → 重复函数 → 基地入口 → 测试场景清理