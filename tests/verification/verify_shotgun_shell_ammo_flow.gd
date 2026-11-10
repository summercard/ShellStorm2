extends Node
## 散射喷壶「弹匣按轮 / 装填按弹丸计费」专项验收（2026-11-10）。
##
## 业主原话：「散弹枪，需要改成弹夹为2发，然后每次打出去多少发子弹，每次装配弹药的时候，
## 消耗的普通子弹数量就是多少个。例如散弹枪一次打出去5发，那一次装弹就消耗10发备弹。」
##
## 本用例钉三层，缺一层就会放过一类回归：
##   ① **内容层**：枪身 `magazine_size == 2`、`bullet_count == 5`（改回 6 发弹匣即报红）；
##   ② **折算层**：`WeaponModel3D.get_reserve_cost_per_round()` —— 散弹枪 5、单发枪 1；
##      读的是**运行时** `projectile_count`，所以弹丸被命运/配件加过也会跟着涨；
##   ③ **交易层**：真起一次换弹，扣多少备弹、装几格、余量不足怎么拒 —— 这是唯一
##      能抓住「算对了但扣错了」的地方（要求 10 却扣 7 只填 1 格那类）。
##
## 判据：`SHOTGUN_SHELL_AMMO_OK` 行 + 失败计数（不看裸退出码）。

const WEAPON_MODEL_SCENE: PackedScene = preload("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn")

const SHOTGUN_ASSEMBLY_ID := "bp_shotgun"
## 业主点名的两个数：弹匣 2 轮、一次扣扳机 5 发弹丸。硬编码一份，改内容侧即报红。
const EXPECTED_MAGAZINE := 2
const EXPECTED_PELLETS := 5
const EXPECTED_COST_PER_ROUND := EXPECTED_PELLETS
## 单发枪（步枪）的成本必须仍是 1 —— 这条是「别把规则扩散到全枪族」的护栏。
const RIFLE_ASSEMBLY_ID := "bp_rifle"
const RIFLE_EXPECTED_COST := 1

var _failures: Array[String] = []
var _samples := 0
## 造的枪全部记账，退出前统一释放：套件按 `ObjectDB instances leaked at exit`
## 判 exit 4，任何 `queue_free()` 后立刻 `quit()` 都会假红。
var _weapons: Array[WeaponModel3D] = []


func _ready() -> void:
	await get_tree().process_frame
	_check_content_stats()
	_check_cost_derives_from_projectile_count()
	await _check_full_mag_drain()
	await _check_odd_reserve_stays_whole_rounds()
	await _check_reserve_below_one_round_is_refused()
	await _report()


func _expect(condition: bool, message: String) -> void:
	_samples += 1
	if not condition:
		_failures.append(message)


func _make_weapon(assembly_id: String) -> WeaponModel3D:
	var weapon := WEAPON_MODEL_SCENE.instantiate() as WeaponModel3D
	if weapon == null:
		_failures.append("%s：武器模型场景根节点不是 WeaponModel3D" % assembly_id)
		return null
	add_child(weapon)
	_weapons.append(weapon)
	var tree := BlueprintRegistry.build_weapon_tree(assembly_id, "mod_bullet_standard")
	if tree == null or not weapon.configure_from_tree(tree):
		_failures.append("%s：装配树构建或配置失败" % assembly_id)
		return null
	weapon.display_only = false
	return weapon


## 备弹提供者的离体替身：语义必须与 `Dungeon3D._provide_reload_ammo` 一致 ——
## `requested <= 0` 回**当前余量**，否则扣 `min(余量, requested)` 并回实扣数。
func _provide_reload_ammo(requested: int, bank: Array) -> int:
	var reserve := int(bank[0])
	if requested <= 0:
		return reserve
	var consumed := mini(reserve, requested)
	bank[0] = reserve - consumed
	return consumed


func _check_content_stats() -> void:
	var node := BlueprintRegistry.create_assembly_node(SHOTGUN_ASSEMBLY_ID)
	if node == null:
		_failures.append("%s 造不出装配节点" % SHOTGUN_ASSEMBLY_ID)
		return
	var stats := node.get_base_stats()
	_expect(
		int(stats.get("magazine_size", -1)) == EXPECTED_MAGAZINE,
		"散射喷壶 magazine_size 是 %d，期望 %d（业主 2026-11-10：弹夹改成 2 发）"
		% [int(stats.get("magazine_size", -1)), EXPECTED_MAGAZINE]
	)
	_expect(
		int(stats.get("bullet_count", -1)) == EXPECTED_PELLETS,
		"散射喷壶 bullet_count 是 %d，期望 %d：一次扣扳机的弹丸数不能被顺手改掉"
		% [int(stats.get("bullet_count", -1)), EXPECTED_PELLETS]
	)
	node.free()


func _check_cost_derives_from_projectile_count() -> void:
	var shotgun := _make_weapon(SHOTGUN_ASSEMBLY_ID)
	if shotgun != null:
		_expect(
			shotgun.projectile_count == EXPECTED_PELLETS,
			"散射喷壶运行时 projectile_count 是 %d，期望 %d"
			% [shotgun.projectile_count, EXPECTED_PELLETS]
		)
		_expect(
			shotgun.get_reserve_cost_per_round() == EXPECTED_COST_PER_ROUND,
			"散射喷壶每轮备弹成本是 %d，期望 %d"
			% [shotgun.get_reserve_cost_per_round(), EXPECTED_COST_PER_ROUND]
		)
		var snapshot := shotgun.get_snapshot()
		_expect(
			int(snapshot.get("reserve_ammo_per_round", -1)) == EXPECTED_COST_PER_ROUND,
			"snapshot 没有如实下发 reserve_ammo_per_round：%s"
			% str(snapshot.get("reserve_ammo_per_round", null))
		)
		# 命运/配件改弹丸数 ⇒ 成本必须同步涨（否则会留下「多打不多花」的白嫖口子）。
		shotgun.projectile_count = EXPECTED_PELLETS + 1
		_expect(
			shotgun.get_reserve_cost_per_round() == EXPECTED_PELLETS + 1,
			"弹丸数被改到 %d 时每轮成本没有跟着变成 %d（读的是静态值而不是运行时值）"
			% [EXPECTED_PELLETS + 1, EXPECTED_PELLETS + 1]
		)
	var rifle := _make_weapon(RIFLE_ASSEMBLY_ID)
	if rifle != null:
		_expect(
			rifle.get_reserve_cost_per_round() == RIFLE_EXPECTED_COST,
			"单发枪（步枪）每轮备弹成本是 %d，期望 %d：单发枪不该被这条规则涨价"
			% [rifle.get_reserve_cost_per_round(), RIFLE_EXPECTED_COST]
		)


## 空匣 + 12 发备弹 ⇒ 装 2 轮，扣 10 发，余 2 发。
func _check_full_mag_drain() -> void:
	var weapon := _make_weapon(SHOTGUN_ASSEMBLY_ID)
	if weapon == null:
		return
	var bank := [12]
	weapon.set_reload_ammo_provider(Callable(self, "_provide_reload_ammo").bind(bank))
	weapon.current_ammo = 0
	_expect(weapon.request_reload(), "散射喷壶空匣时换弹被拒（备弹 12 发足够装两轮）")
	weapon.call("_process", weapon.reload_time + 0.01)
	await get_tree().process_frame
	_expect(
		weapon.current_ammo == EXPECTED_MAGAZINE,
		"满装填后弹匣是 %d 轮，期望 %d" % [weapon.current_ammo, EXPECTED_MAGAZINE]
	)
	_expect(
		int(bank[0]) == 12 - EXPECTED_MAGAZINE * EXPECTED_COST_PER_ROUND,
		"两轮装填扣了 %d 发备弹，期望 %d 发（= 2 轮 × 5 发弹丸）"
		% [12 - int(bank[0]), EXPECTED_MAGAZINE * EXPECTED_COST_PER_ROUND]
	)


## 余量 7 发（不能整除 5）⇒ 只装 1 轮、扣 5 发、余 2 发；零头不许被扣走换半格。
func _check_odd_reserve_stays_whole_rounds() -> void:
	var weapon := _make_weapon(SHOTGUN_ASSEMBLY_ID)
	if weapon == null:
		return
	var bank := [7]
	weapon.set_reload_ammo_provider(Callable(self, "_provide_reload_ammo").bind(bank))
	weapon.current_ammo = 0
	_expect(weapon.request_reload(), "备弹 7 发时换弹被拒：够装一整轮就不该拒绝")
	weapon.call("_process", weapon.reload_time + 0.01)
	await get_tree().process_frame
	_expect(
		weapon.current_ammo == 1,
		"备弹 7 发装了 %d 轮，期望 1 轮（零头不能凑成一格）" % weapon.current_ammo
	)
	_expect(int(bank[0]) == 2, "备弹 7 发装 1 轮后余 %d 发，期望 2 发" % int(bank[0]))


## 余量 4 发 < 一轮成本 5 ⇒ 换弹直接拒绝，且一发都不许扣。
func _check_reserve_below_one_round_is_refused() -> void:
	var weapon := _make_weapon(SHOTGUN_ASSEMBLY_ID)
	if weapon == null:
		return
	var bank := [4]
	weapon.set_reload_ammo_provider(Callable(self, "_provide_reload_ammo").bind(bank))
	weapon.current_ammo = 0
	_expect(
		not weapon.request_reload(),
		"备弹 4 发（不足一轮 5 发）时换弹没有被拒绝"
	)
	_expect(int(bank[0]) == 4, "被拒绝的换弹扣了备弹：%d 发未扣前的余量应保持 4" % int(bank[0]))


func _report() -> void:
	if _samples < 14:
		_failures.append("判据采样数只有 %d，低于防假绿下限 14" % _samples)
	# 释放顺序：先全部 free，再让两帧跑完，最后才 quit —— 否则套件的
	# `ObjectDB instances leaked at exit` 会把一个通过的用例判成 exit 4。
	for weapon in _weapons:
		if is_instance_valid(weapon):
			weapon.free()
	_weapons.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("SHOTGUN_SHELL_AMMO_OK: 散弹枪弹匣按轮记（2 轮），每轮装填按一次扣扳机的弹丸数（5 发）扣备弹，零头不凑格、不足一轮拒绝；单发枪成本仍为 1（samples=%d）" % _samples)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SHOTGUN_SHELL_AMMO_FAILED: %d 项失败 / samples=%d" % [_failures.size(), _samples])
	get_tree().quit(1)
