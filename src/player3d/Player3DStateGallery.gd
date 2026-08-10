class_name Player3DStateGallery
extends Node3D
## 独立 3D 表现验收场：所有按钮都驱动运行时 Player3D / Enemy3D / ThemedNPC3D。

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_ANCHOR := Vector3(0.0, 0.0, 0.0)
const ENEMY_ANCHOR := Vector3(5.2, 0.0, -1.0)
const NPC_ANCHOR := Vector3(-4.2, 0.0, 1.6)

const ENEMY_OPTIONS := [
	"melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher",
]
const NPC_CONFIGS := [
	{
		"id": "npc_signal", "name": "荒野信使", "role": "情报提供者",
		"text": "风向变了。别在没有照明的走廊停太久。", "color": Color(0.28, 0.78, 0.88),
	},
	{
		"id": "npc_quartermaster", "name": "补给员·柯尔", "role": "军需商",
		"text": "枪身和弹药分开看。背包满了，再好的战利品也带不走。", "color": Color(0.92, 0.58, 0.22),
	},
	{
		"id": "npc_mechanic", "name": "修复师·迦南", "role": "装备技师",
		"text": "手和 weapon_socket 必须同相。松一帧，换弹就会像穿模。", "color": Color(0.64, 0.42, 0.92),
	},
]
const DIY_LABELS := {
	"body": {"bunny_white": "兔子白身", "cat_orange": "复古橙色", "suit_olive": "橄榄防护服", "suit_sand": "沙色防护服", "suit_cobalt": "钴蓝防护服"},
	"head": {"bunny_white": "兔子白头", "cat_orange": "复古橙色", "sensor_olive": "标准传感头", "visor_cyan": "青色面板头", "plated_amber": "琥珀装甲头"},
	"hand": {"bunny_white": "兔子白手", "cat_orange": "复古橙色", "grip_olive": "橄榄握持手", "safety_orange": "橙色安全手", "gauntlet_teal": "青绿护手"},
	"feet": {"bunny_white": "兔子白脚", "cat_orange": "复古橙色", "boot_sand": "沙色短靴", "boot_cobalt": "钴蓝短靴", "boot_teal": "青绿短靴"},
	"hat": {"none": "无帽子", "field_cap": "荒野软帽", "hard_hat": "工兵安全帽", "sealed_hood": "密封兜帽"},
	"glasses": {"none": "无眼镜", "mono_lens": "单目镜", "dual_goggles": "双目护镜", "wide_visor": "宽面护目镜"},
}

var player: Player3D
var active_enemy: Enemy3D
var active_npc: ThemedNPC3D
var _actions: Dictionary = {}
var _player_motion := "idle"
var _enemy_ai_enabled := false
var _selected_enemy_index := 0
var _selected_npc_index := 0
var _status_label: Label
var _actor_label: Label
var _hint_label: Label
var _enemy_option: OptionButton
var _npc_option: OptionButton
var _diy_selectors: Dictionary = {}


func _ready() -> void:
	player = get_node_or_null("Player3D") as Player3D
	_prepare_player()
	_spawn_npc(0)
	_build_interface()
	call_deferred("_refresh_readout")


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.current_hp <= 0:
		return
	player.global_position = PLAYER_ANCHOR
	if _player_motion == "moving" and not player.input_locked:
		player.set_test_move_direction(Vector3(0.0, 0.0, -1.0))
	else:
		player.set_test_move_direction(Vector3.ZERO)


func _process(_delta: float) -> void:
	_refresh_readout()


func invoke_control(control_id: String) -> bool:
	if not _actions.has(control_id):
		return false
	var action := _actions[control_id] as Callable
	action.call()
	return true


func get_control_ids() -> Array[String]:
	var ids: Array[String] = []
	for control_id in _actions.keys():
		ids.append(str(control_id))
	ids.sort()
	return ids


func get_preview_snapshot() -> Dictionary:
	return {
		"player": player.get_state_machine_snapshot() if player != null and is_instance_valid(player) else {},
		"enemy": active_enemy.get_state_snapshot() if active_enemy != null and is_instance_valid(active_enemy) else {},
		"npc": active_npc.get_snapshot() if active_npc != null and is_instance_valid(active_npc) else {},
		"enemy_ai_enabled": _enemy_ai_enabled,
		"diy": player.get_avatar_customization() if player != null and is_instance_valid(player) else {},
		"controls": get_control_ids(),
	}


func run_player_action(action: String) -> void:
	if action == "reset":
		_reset_player()
		return
	if player == null or not is_instance_valid(player):
		_reset_player()
	if player.current_hp <= 0:
		_reset_player()
	var machine := player.get("_state_machine") as StateMachine
	if machine == null:
		return
	match action:
		"idle":
			player.set_input_locked(false)
			_player_motion = "idle"
			machine.transition_to("idle", true)
		"moving":
			player.set_input_locked(false)
			_player_motion = "moving"
			machine.transition_to("moving", true)
		"dashing":
			player.set_input_locked(false)
			_player_motion = "moving"
			player.dash_cooldown_timer = 0.0
			player.request_dash()
		"hurt":
			player.set("is_invincible", false)
			player.set("_invincible_remaining", 0.0)
			player.take_damage(12)
		"locked":
			_player_motion = "idle"
			player.set_input_locked(true)
		"falling":
			player.set_input_locked(false)
			_player_motion = "idle"
			player.velocity = Vector3(0.0, -8.0, 0.0)
			player.set("_fall_start_y", player.global_position.y)
			machine.transition_to("falling", true)
		"landing":
			player.set_input_locked(false)
			_player_motion = "idle"
			if machine.current_state_name != "falling":
				machine.transition_to("falling")
			player.set("_last_impact_speed", 10.0)
			player.set("_landing_duration", 0.22)
			machine.transition_to("landing")
		"dead":
			player.set("is_invincible", false)
			player.set("_invincible_remaining", 0.0)
			player.take_damage(player.max_hp + 1)
	_refresh_readout()


func request_preview_reload() -> bool:
	if player == null or not is_instance_valid(player) or player.current_hp <= 0 or player.weapon == null:
		return false
	var weapon := player.weapon
	weapon.current_ammo = maxi(0, weapon.magazine_size - 3)
	weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	var started := weapon.request_reload()
	_refresh_readout()
	return started


func request_preview_fire() -> bool:
	if not _ensure_living_player() or player.weapon == null:
		return false
	if player.weapon.is_reloading():
		player.weapon.cancel_reload()
	if player.weapon.gun_id == "bp_charge":
		player.equip_weapon("bp_pistol", "mod_bullet_standard")
	var fired := player.weapon.try_fire(player.aim_direction, player)
	_refresh_readout()
	return fired


func request_preview_melee(assembly_id: String) -> bool:
	if not _ensure_living_player():
		return false
	if not player.equip_weapon(assembly_id, ""):
		return false
	player.combat_enabled = true
	var started := player.request_melee_attack()
	_refresh_readout()
	return started


func begin_preview_charge() -> bool:
	if not _ensure_living_player():
		return false
	if not player.equip_weapon("bp_charge", "mod_bullet_standard") or player.weapon == null:
		return false
	if player.weapon.is_reloading():
		player.weapon.cancel_reload()
	player.weapon.try_fire(player.aim_direction, player)
	var charging := bool(player.get_action_snapshot().get("charging", false))
	_refresh_readout()
	return charging


func release_preview_charge() -> bool:
	if player == null or not is_instance_valid(player) or player.weapon == null:
		return false
	var fired := player.weapon.release_charge()
	_refresh_readout()
	return fired


func request_preview_knockback() -> bool:
	if not _ensure_living_player():
		return false
	_player_motion = "idle"
	var applied := player.apply_knockback(-player.aim_direction, 8.2, 0.38, true)
	_refresh_readout()
	return applied


func set_preview_customization(slot_id: String, variant_id: String) -> bool:
	if not _ensure_living_player():
		return false
	var changed := player.set_avatar_customization(slot_id, variant_id)
	if changed:
		_sync_diy_selector(slot_id, variant_id)
	_refresh_readout()
	return changed


func cycle_preview_customization(slot_id: String) -> bool:
	if not _ensure_living_player():
		return false
	var options := player.get_avatar_customization_options().get(slot_id, []) as Array
	if options.is_empty():
		return false
	var current := str(player.get_avatar_customization().get(slot_id, ""))
	var next_index := (options.find(current) + 1) % options.size()
	return set_preview_customization(slot_id, str(options[next_index]))


func reset_preview_customization() -> void:
	if not _ensure_living_player():
		return
	player.set_avatar_customization_loadout(PlayerAvatar3D.DEFAULT_CUSTOMIZATION)
	for slot_id in PlayerAvatar3D.DEFAULT_CUSTOMIZATION:
		_sync_diy_selector(slot_id, str(PlayerAvatar3D.DEFAULT_CUSTOMIZATION[slot_id]))
	_refresh_readout()


func toggle_low_health() -> void:
	if not _ensure_living_player():
		return
	player.current_hp = player.max_hp if player.is_low_health() else maxi(1, int(player.max_hp * 0.24))
	player.hp_changed.emit(player.current_hp, player.max_hp)


func toggle_invincible() -> void:
	if not _ensure_living_player():
		return
	var enabled := not player.is_invincible
	player.is_invincible = enabled
	player.set("_invincible_remaining", 999.0 if enabled else 0.0)


func toggle_silenced() -> void:
	if not _ensure_living_player():
		return
	var remaining := float(player.get("_silence_remaining"))
	player.set("_silence_remaining", 0.0 if remaining > 0.0 else 999.0)


func equip_preview_weapon(gun_id: String) -> bool:
	if not _ensure_living_player():
		return false
	return player.equip_weapon(gun_id, "mod_bullet_standard")


func spawn_selected_enemy() -> void:
	spawn_enemy(ENEMY_OPTIONS[_selected_enemy_index])


func spawn_enemy(kind: String) -> Enemy3D:
	if active_enemy != null and is_instance_valid(active_enemy):
		active_enemy.queue_free()
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	$Actors.add_child(enemy)
	enemy.global_position = ENEMY_ANCHOR
	enemy.room_id = "gallery"
	enemy.apply_profile(kind)
	enemy.set_physics_process(_enemy_ai_enabled)
	active_enemy = enemy
	_refresh_readout()
	return enemy


func spawn_boss() -> Enemy3D:
	return spawn_enemy("boss")


func toggle_enemy_ai() -> void:
	_enemy_ai_enabled = not _enemy_ai_enabled
	if active_enemy != null and is_instance_valid(active_enemy):
		active_enemy.set_physics_process(_enemy_ai_enabled)


func set_enemy_state(state_id: String) -> bool:
	if active_enemy == null or not is_instance_valid(active_enemy):
		return false
	active_enemy.set_physics_process(false)
	_enemy_ai_enabled = false
	return active_enemy.transition_to(state_id)


func damage_active_enemy() -> void:
	if active_enemy == null or not is_instance_valid(active_enemy):
		return
	active_enemy.take_damage(maxi(1, int(active_enemy.max_hp * 0.20)), false, Vector3.FORWARD)


func advance_boss_phase() -> void:
	if active_enemy == null or not is_instance_valid(active_enemy) or active_enemy.enemy_kind != "boss":
		spawn_boss()
	if active_enemy != null and is_instance_valid(active_enemy):
		active_enemy.take_damage(maxi(1, int(active_enemy.max_hp * 0.37)), false, Vector3.FORWARD)


func select_npc(index: int) -> void:
	_spawn_npc(clampi(index, 0, NPC_CONFIGS.size() - 1))


func interact_with_npc() -> void:
	if active_npc != null and is_instance_valid(active_npc):
		active_npc.interact()


func _prepare_player() -> void:
	if player == null:
		return
	player.combat_enabled = false
	player.set_test_move_direction(Vector3.ZERO)
	player.global_position = PLAYER_ANCHOR


func _reset_player() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = PLAYER_SCENE.instantiate() as Player3D
	player.name = "Player3D"
	player.combat_enabled = false
	add_child(player)
	move_child(player, 0)
	_prepare_player()
	_player_motion = "idle"


func _ensure_living_player() -> bool:
	if player == null or not is_instance_valid(player) or player.current_hp <= 0:
		_reset_player()
	return player != null and is_instance_valid(player) and player.current_hp > 0


func _spawn_npc(index: int) -> void:
	_selected_npc_index = index
	if active_npc != null and is_instance_valid(active_npc):
		active_npc.queue_free()
	active_npc = ThemedNPC3D.new()
	$Actors.add_child(active_npc)
	active_npc.global_position = NPC_ANCHOR
	active_npc.configure(NPC_CONFIGS[_selected_npc_index])
	if _npc_option != null:
		_npc_option.select(_selected_npc_index)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.name = "PreviewUI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title := Label.new()
	title.position = Vector2(28, 18)
	title.size = Vector2(760, 30)
	title.text = "角色与遭遇预览场 · 真实状态机 / 阿凡达 / AI"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.76, 0.93, 1.0))
	root.add_child(title)
	_hint_label = Label.new()
	_hint_label.position = Vector2(30, 50)
	_hint_label.size = Vector2(820, 24)
	_hint_label.text = "鼠标瞄准 · 左侧测试玩家 · 右侧生成怪物/Boss/NPC · 所有实体退出后销毁"
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.48, 0.68, 0.76))
	root.add_child(_hint_label)

	var player_panel := _make_panel("PlayerControls", Vector2(24, 88), Vector2(300, 616))
	root.add_child(player_panel)
	var player_box := VBoxContainer.new()
	player_panel.add_child(player_box)
	_add_section_label(player_box, "玩家状态机 · 八态")
	var state_grid := GridContainer.new()
	state_grid.columns = 2
	player_box.add_child(state_grid)
	_add_button(state_grid, "StateIdle", "待命", func(): run_player_action("idle"))
	_add_button(state_grid, "StateMoving", "机动", func(): run_player_action("moving"))
	_add_button(state_grid, "StateDashing", "突进", func(): run_player_action("dashing"))
	_add_button(state_grid, "StateHurt", "受创", func(): run_player_action("hurt"))
	_add_button(state_grid, "StateLocked", "锁定", func(): run_player_action("locked"))
	_add_button(state_grid, "StateFalling", "下落", func(): run_player_action("falling"))
	_add_button(state_grid, "StateLanding", "落地", func(): run_player_action("landing"))
	_add_button(state_grid, "StateDead", "死亡", func(): run_player_action("dead"))
	_add_button(player_box, "ResetPlayer", "重置玩家", func(): run_player_action("reset"))
	_add_section_label(player_box, "叠加层与武器")
	var overlay_grid := GridContainer.new()
	overlay_grid.columns = 2
	player_box.add_child(overlay_grid)
	_add_button(overlay_grid, "Reload", "换弹", request_preview_reload)
	_add_button(overlay_grid, "LowHealth", "低血", toggle_low_health)
	_add_button(overlay_grid, "Invincible", "无敌", toggle_invincible)
	_add_button(overlay_grid, "Silenced", "沉默", toggle_silenced)
	var weapon_grid := GridContainer.new()
	weapon_grid.columns = 2
	player_box.add_child(weapon_grid)
	_add_button(weapon_grid, "WeaponPistol", "手枪", func(): equip_preview_weapon("bp_pistol"))
	_add_button(weapon_grid, "WeaponShotgun", "霰弹", func(): equip_preview_weapon("bp_shotgun"))
	_add_button(weapon_grid, "WeaponRifle", "步枪", func(): equip_preview_weapon("bp_rifle"))
	_add_button(weapon_grid, "WeaponGreatblade", "工业断刃", func(): equip_preview_weapon("bp_greatblade"))
	_add_button(weapon_grid, "WeaponWaraxe", "裂甲斧", func(): equip_preview_weapon("bp_waraxe"))
	_add_section_label(player_box, "动作覆盖层 · 真实武器/受击驱动")
	var action_grid := GridContainer.new()
	action_grid.columns = 2
	player_box.add_child(action_grid)
	_add_button(action_grid, "FireShot", "射击", request_preview_fire)
	_add_button(action_grid, "StartCharge", "开始蓄力", begin_preview_charge)
	_add_button(action_grid, "ReleaseCharge", "释放蓄力", release_preview_charge)
	_add_button(action_grid, "Knockback", "受击击飞", request_preview_knockback)
	_add_button(action_grid, "MeleeGreatblade", "断刃三连", func(): request_preview_melee("bp_greatblade"))
	_add_button(action_grid, "MeleeWaraxe", "战斧三连", func(): request_preview_melee("bp_waraxe"))

	var diy_panel := _make_panel("DIYControls", Vector2(336, 88), Vector2(270, 310))
	root.add_child(diy_panel)
	var diy_box := VBoxContainer.new()
	diy_panel.add_child(diy_box)
	_add_section_label(diy_box, "DIY 模块装配 · 真实角色")
	for slot_id in ["body", "head", "hand", "feet", "hat", "glasses"]:
		_add_diy_selector(diy_box, slot_id)
	var diy_button_grid := GridContainer.new()
	diy_button_grid.columns = 2
	diy_box.add_child(diy_button_grid)
	_add_button(diy_button_grid, "DiyNextHat", "切换帽子", func(): cycle_preview_customization("hat"))
	_add_button(diy_button_grid, "DiyNextGlasses", "切换眼镜", func(): cycle_preview_customization("glasses"))
	_add_button(diy_button_grid, "DiyReset", "恢复默认", reset_preview_customization)

	var encounter_panel := _make_panel("EncounterControls", Vector2(956, 88), Vector2(300, 530))
	root.add_child(encounter_panel)
	var encounter_box := VBoxContainer.new()
	encounter_panel.add_child(encounter_box)
	_add_section_label(encounter_box, "怪物与 Boss · 正式 Enemy3D")
	_enemy_option = OptionButton.new()
	_enemy_option.name = "EnemyType"
	for kind in ENEMY_OPTIONS:
		_enemy_option.add_item(_enemy_display_name(kind))
	_enemy_option.item_selected.connect(func(index: int): _selected_enemy_index = index)
	encounter_box.add_child(_enemy_option)
	var enemy_grid := GridContainer.new()
	enemy_grid.columns = 2
	encounter_box.add_child(enemy_grid)
	_add_button(enemy_grid, "SpawnEnemy", "生成怪物", spawn_selected_enemy)
	_add_button(enemy_grid, "SpawnBoss", "生成 Boss", spawn_boss)
	_add_button(enemy_grid, "ToggleEnemyAI", "AI 开 / 关", toggle_enemy_ai)
	_add_button(enemy_grid, "DamageEnemy", "怪物受击", damage_active_enemy)
	_add_button(enemy_grid, "EnemyIdle", "怪物待机", func(): set_enemy_state("idle"))
	_add_button(enemy_grid, "EnemyPatrol", "怪物巡逻", func(): set_enemy_state("patrol"))
	_add_button(enemy_grid, "EnemyTelegraph", "攻击前摇", func(): set_enemy_state("telegraph"))
	_add_button(enemy_grid, "EnemyAttack", "执行攻击", func(): set_enemy_state("attack"))
	_add_button(encounter_box, "AdvanceBossPhase", "Boss 推进阶段", advance_boss_phase)
	_add_section_label(encounter_box, "NPC · 3D 交互适配")
	_npc_option = OptionButton.new()
	_npc_option.name = "NPCType"
	for config in NPC_CONFIGS:
		_npc_option.add_item(str(config["name"]))
	_npc_option.item_selected.connect(select_npc)
	encounter_box.add_child(_npc_option)
	_add_button(encounter_box, "InteractNPC", "切换 NPC 对话", interact_with_npc)

	var readout_panel := _make_panel("Readout", Vector2(336, 550), Vector2(608, 145))
	root.add_child(readout_panel)
	_status_label = Label.new()
	_status_label.name = "RuntimeReadout"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.84, 0.92, 0.96))
	readout_panel.add_child(_status_label)
	_actor_label = Label.new()
	_actor_label.position = Vector2(614, 88)
	_actor_label.size = Vector2(330, 96)
	_actor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_actor_label.add_theme_font_size_override("font_size", 14)
	_actor_label.add_theme_color_override("font_color", Color(0.66, 0.82, 0.90))
	root.add_child(_actor_label)


func _make_panel(node_name: String, position: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = position
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.038, 0.055, 0.90)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.52, 0.66, 0.76)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.48, 0.86, 1.0))
	label.custom_minimum_size.y = 26
	parent.add_child(label)


func _add_diy_selector(parent: Control, slot_id: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 29
	parent.add_child(row)
	var label := Label.new()
	label.text = {"body": "身体", "head": "头部", "hand": "手部", "feet": "脚部", "hat": "帽子", "glasses": "眼镜"}.get(slot_id, slot_id)
	label.custom_minimum_size.x = 52
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var selector := OptionButton.new()
	selector.name = "DIY%s" % slot_id.capitalize()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var options := PlayerAvatar3D.CUSTOMIZATION_OPTIONS[slot_id] as Array
	var current := str(player.get_avatar_customization().get(slot_id, PlayerAvatar3D.DEFAULT_CUSTOMIZATION[slot_id]))
	for variant_id in options:
		selector.add_item(str((DIY_LABELS[slot_id] as Dictionary).get(variant_id, variant_id)))
		selector.set_item_metadata(selector.item_count - 1, variant_id)
		if variant_id == current:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index: int): set_preview_customization(slot_id, str(selector.get_item_metadata(index))))
	row.add_child(selector)
	_diy_selectors[slot_id] = selector


func _sync_diy_selector(slot_id: String, variant_id: String) -> void:
	var selector := _diy_selectors.get(slot_id, null) as OptionButton
	if selector == null:
		return
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == variant_id:
			selector.select(index)
			return


func _add_button(parent: Control, control_id: String, text: String, action: Callable) -> void:
	var button := Button.new()
	button.name = control_id
	button.text = text
	button.custom_minimum_size = Vector2(0, 31)
	button.tooltip_text = "驱动运行时实体，不创建展示替身"
	button.pressed.connect(action)
	parent.add_child(button)
	_actions[control_id] = action


func _refresh_readout() -> void:
	if _status_label == null or _actor_label == null:
		return
	var player_snapshot := player.get_state_machine_snapshot() if player != null and is_instance_valid(player) else {}
	var overlays := player_snapshot.get("overlays", {}) as Dictionary
	var active_overlays: Array[String] = []
	for overlay_id in overlays:
		var overlay_value: Variant = overlays[overlay_id]
		var is_active := (
			bool(overlay_value)
			if overlay_value is bool
			else bool((overlay_value as Dictionary).get("enabled", false))
			if overlay_value is Dictionary
			else false
		)
		if is_active:
			active_overlays.append(str(overlay_id))
	active_overlays.sort()
	var weapon_snapshot := player.get_weapon_snapshot() if player != null and is_instance_valid(player) else {}
	var reload_snapshot := player.get_reload_snapshot() if player != null and is_instance_valid(player) else {}
	var diy := player.get_avatar_customization() if player != null and is_instance_valid(player) else {}
	_status_label.text = "玩家：%s  |  HP %d/%d  |  枪 %s %d/%d  |  覆盖层 %s  |  换弹 %.0f%%\nDIY：%s / %s / %s / %s  ·  %s / %s" % [
		str(player_snapshot.get("current", "未加载")),
		player.current_hp if player != null and is_instance_valid(player) else 0,
		player.max_hp if player != null and is_instance_valid(player) else 0,
		str(weapon_snapshot.get("gun_id", "无")),
		int(weapon_snapshot.get("current_ammo", 0)),
		int(weapon_snapshot.get("magazine_size", 0)),
		", ".join(active_overlays) if not active_overlays.is_empty() else "无",
		float(reload_snapshot.get("progress", 0.0)) * 100.0,
		str(diy.get("body", "-")), str(diy.get("head", "-")), str(diy.get("hand", "-")),
		str(diy.get("feet", "-")),
		str(diy.get("hat", "-")), str(diy.get("glasses", "-")),
	]
	var enemy_text := "怪物：未生成"
	if active_enemy != null and is_instance_valid(active_enemy):
		enemy_text = "怪物：%s · %s · HP %d/%d · AI %s · Boss阶段 %d" % [
			active_enemy.enemy_kind, active_enemy.ai_state, active_enemy.current_hp, active_enemy.max_hp,
			"运行" if _enemy_ai_enabled else "暂停", active_enemy.boss_phase,
		]
	var npc_text := "NPC：未加载"
	if active_npc != null and is_instance_valid(active_npc):
		npc_text = "NPC：%s · %s · 对话 %s" % [
			active_npc.display_name, active_npc.role, "显示" if active_npc.get_snapshot().get("dialogue_visible", false) else "隐藏",
		]
	_actor_label.text = "%s\n%s" % [enemy_text, npc_text]


func _enemy_display_name(kind: String) -> String:
	return str({
		"melee_chaser": "近战追击者", "ranged_caster": "远程施法体", "summoner": "召唤支援体",
		"shielded": "护盾重装体", "exploder": "爆破体", "ambusher": "伏击体",
	}.get(kind, kind))
