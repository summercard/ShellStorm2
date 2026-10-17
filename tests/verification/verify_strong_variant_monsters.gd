extends Node
## 「普通怪变种（-强化怪）」专项验收。
##
## 外部真源：
##   - 定义与倍率 src/enemy3d/MonsterVariants.gd
##   - 业主口径 docs/v0.1/design/怪物设计.md「普通怪变种」节
##   - 关卡概率 data/level_plans/expedition_01/level_plan.json → monster_rules.strong_variant
##
## 覆盖：
##   ① 三个变种在**每一张必须认识它的表**里都登记齐全 —— 这是本文件存在的首要理由：
##      各处查表判据都是 `kind if TABLE.has(kind) else "melee_chaser"`，
##      漏登记不会报错，只会静默变回小僵尸；
##   ② 倍率逐条等于业主口径（本文档侧硬编码一遍，改代码就红）；
##   ③ 真 Enemy3D 实例上的最终数值：生命 / 伤害 / 攻击距离 / 体型倍率；
##   ④ 弹道只影响强化远程怪，Boss 与普通远程怪的子弹逐字不变（回归）；
##   ⑤ 有 override 的关卡（远征01）：强化怪数值从原怪那一行派生，不是另抄一份；
##   ⑥ 自爆半径 ×1.5 派生，且原怪不自爆时变种不会凭空长出自爆；
##   ⑦ **zone 段透传**（回归钉：原先被 `_death_explosion_for` 丢弃 ⇒ 地面持续伤害场从未生成过）；
##   ⑧ 15% 概率在统计上成立、且同种子可复现；
##   ⑨ 未配置的关卡：一次随机数都不掷 ⇒ 随机流与改动前逐字一致；
##   ⑩ 精英不被随机升级（身份指派不该被改写）。
## 只读常量与实例快照，不读 viewport 纹理 ⇒ 可安全 headless 运行。
## 判据：`STRONG_VARIANT_OK` 行 + `STRONG_VARIANT_FAIL` 计数（不看裸退出码）。

const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const EXPEDITION_PLAN_PATH := "res://data/level_plans/expedition_01/level_plan.json"

## 业主 2026-10-16 口径，在这里**再写一遍**：改了 MonsterVariants 就会在此红。
## 换算口径为乘法（「×2」即 ×2，不是 ×3）。
const DOC_RATIOS := {
	"melee_chaser": {
		"hp_mult": 2.0, "damage_mult": 2.0, "scale_mult": 1.5, "attack_range_mult": 1.5,
	},
	"fat_zombie03": {
		"hp_mult": 2.0, "damage_mult": 2.0, "scale_mult": 1.5, "attack_range_mult": 1.5,
		"death_explosion_radius_mult": 1.5,
	},
	"ranged_caster": {
		"hp_mult": 1.5, "damage_mult": 1.0, "scale_mult": 1.5, "attack_range_mult": 1.5,
		"projectile_speed_mult": 1.3, "projectile_range_mult": 2.0,
	},
}

## 文档侧写死的中文名（正式名称 = 原怪名 + 后缀）。
const DOC_NAMES := {
	"melee_chaser_strong": "小僵尸-强化怪",
	"fat_zombie03_strong": "胖子僵尸-强化怪",
	"ranged_caster_strong": "保安僵尸-强化怪",
}

const EPS := 0.0001
const SEED := 20261016
## 统计样本量。0.15 ± 0.03 的容忍带在 n=4000 下极难被二项噪声击穿（σ ≈ 0.0056）。
const SAMPLE_COUNT := 4000
const RATE_MIN := 0.12
const RATE_MAX := 0.18

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_definition_table()
	_check_doc_ratios()
	_check_registration_everywhere()
	_check_names()
	_check_profile_is_derived_not_stored()
	_check_projectile_untouched_for_others()
	await _check_runtime_enemy()
	await _check_real_ranged_attack()
	_check_override_derivation()
	_check_death_explosion_derivation()
	_check_zone_passthrough_regression()
	_check_roll_statistics()
	_check_reproducible_with_seed()
	_check_unconfigured_level_unchanged()
	_check_elite_not_upgraded()
	_expect(_samples >= 20, "样本数 %d 低于下限（疑似用例被跳过）" % _samples)
	_report()


# ① 定义表本身自洽：变种 ID 规范、基类反查可逆。
func _check_definition_table() -> void:
	var ids := MonsterVariants.all_variant_ids()
	_expect(ids.size() == 3, "变种数量应为 3，实为 %d：%s" % [ids.size(), str(ids)])
	for base_kind in MonsterVariants.all_base_kinds():
		var variant_id := MonsterVariants.variant_of(base_kind)
		_expect(
			variant_id == base_kind + MonsterVariants.VARIANT_SUFFIX,
			"变种 ID 不符合「基类 + %s」规范：%s" % [MonsterVariants.VARIANT_SUFFIX, variant_id]
		)
		_expect(
			MonsterVariants.base_of(variant_id) == base_kind,
			"base_of(%s) 未能反查回 %s" % [variant_id, base_kind]
		)
		_expect(
			MonsterVariants.is_variant(variant_id),
			"is_variant(%s) 应为真" % variant_id
		)
		_samples += 1
	# 普通怪不许被误判成变种。
	for plain in ["melee_chaser", "fat_zombie03", "ranged_caster", "boss", "ambusher"]:
		_expect(not MonsterVariants.is_variant(plain), "%s 被误判为强化怪" % plain)
		_expect(MonsterVariants.base_of(plain) == "", "base_of(%s) 应为空" % plain)
		_samples += 1
	# 变种名后缀。
	_expect(
		MonsterVariants.DISPLAY_SUFFIX == "-强化怪",
		"显示名后缀应为「-强化怪」，实为 %s" % MonsterVariants.DISPLAY_SUFFIX
	)


# ② 倍率逐条等于业主口径。
func _check_doc_ratios() -> void:
	for base_kind in DOC_RATIOS:
		var doc: Dictionary = DOC_RATIOS[base_kind]
		for key in doc:
			var actual := MonsterVariants.multiplier(base_kind, key)
			_expect(
				is_equal_approx(actual, float(doc[key])),
				"%s.%s 应为 %.4f，实为 %.4f（业主口径）" % [base_kind, key, float(doc[key]), actual]
			)
			_samples += 1
	# 未声明的倍率一律 1.0（不变），不允许默默给出别的数。
	for key in ["speed_mult", "cooldown_mult", "nonexistent_mult"]:
		_expect(
			is_equal_approx(MonsterVariants.multiplier("melee_chaser", key), 1.0),
			"未声明的倍率 %s 应取 1.0" % key
		)
		_samples += 1
	# 业主明确「保安僵尸子弹伤害不变」——这条要能被正面钉住。
	_expect(
		is_equal_approx(MonsterVariants.multiplier("ranged_caster", "damage_mult"), 1.0),
		"保安僵尸-强化怪的子弹伤害必须保持不变（业主口径）"
	)


# ③ 每张必须认识变种的表都登记齐全。漏一处 = 静默退化，本用例就是要抓它。
func _check_registration_everywhere() -> void:
	var ids := MonsterVariants.all_variant_ids()
	for variant_id in ids:
		_expect(
			MonsterInjector.BASE_ENEMY_TYPES.has(variant_id),
			"MonsterInjector.BASE_ENEMY_TYPES 未登记 %s ⇒ 盒子/设计源点名时刷不出来" % variant_id
		)
		_expect(
			MonsterInjector.ENEMY_PRESENTATION.has(variant_id),
			"MonsterInjector.ENEMY_PRESENTATION 未登记 %s ⇒ 表现回落成默认配色" % variant_id
		)
		_expect(
			MonsterInjector.is_authorable_enemy_type(variant_id),
			"%s 未通过 is_authorable_enemy_type ⇒ 设计源与刷怪盒都拒绝它" % variant_id
		)
		_expect(
			SpawnBoxCatalog.ALLOWED_BOX_TYPES.has(variant_id),
			"SpawnBoxCatalog.ALLOWED_BOX_TYPES 未登记 %s ⇒ 刷怪盒点名会被判非法" % variant_id
		)
		_samples += 1
	# 「Enemy3D 真的认得这个 kind、没回退成 melee_chaser」由 `_check_runtime_enemy`
	# 用真场景实例断言（那里本来就要实例化，顺带钉住 `enemy_kind` 与 `_table_kind()`）。


# ④ 名称：Minjector 表、MonsterVariants、文档三处必须一致。
func _check_names() -> void:
	for variant_id in DOC_NAMES:
		var want := str(DOC_NAMES[variant_id])
		_expect(
			MonsterVariants.display_name_of(variant_id) == want,
			"%s 的 MonsterVariants 显示名应为 %s，实为 %s"
			% [variant_id, want, MonsterVariants.display_name_of(variant_id)]
		)
		_expect(
			str(MonsterInjector.BASE_ENEMY_TYPES[variant_id]["name"]) == want,
			"%s 的编成表名应为 %s，实为 %s"
			% [variant_id, want, str(MonsterInjector.BASE_ENEMY_TYPES[variant_id]["name"])]
		)
		_samples += 1
	# 守卫：显示名必须带后缀，且带后缀的必须真的是变种。
	for variant_id in DOC_NAMES:
		_expect(
			str(DOC_NAMES[variant_id]).ends_with(MonsterVariants.DISPLAY_SUFFIX),
			"%s 的正式名称未带「%s」后缀" % [variant_id, MonsterVariants.DISPLAY_SUFFIX]
		)


# ⑤ PROFILES 里**不允许**出现变种行 —— 数值必须是派生的，不能是抄的。
func _check_profile_is_derived_not_stored() -> void:
	for variant_id in MonsterVariants.all_variant_ids():
		_expect(
			not Enemy3D.PROFILES.has(variant_id),
			"PROFILES 里出现了 %s 的独立行 ⇒ 又变成两份数值，调普通怪时必然漂移" % variant_id
		)
		_samples += 1
	# 派生结果必须逐键正确。
	for base_kind in MonsterVariants.all_base_kinds():
		var variant_id := MonsterVariants.variant_of(base_kind)
		var derived: Dictionary = Enemy3D.profile_for(variant_id)
		var base_profile: Dictionary = Enemy3D.PROFILES[base_kind]
		_expect(
			is_equal_approx(float(derived["hp"]), float(base_profile["hp"]) * MonsterVariants.multiplier(base_kind, "hp_mult")),
			"%s 派生生命错：%.4f" % [variant_id, float(derived["hp"])]
		)
		_expect(
			is_equal_approx(float(derived["damage"]), float(base_profile["damage"]) * MonsterVariants.multiplier(base_kind, "damage_mult")),
			"%s 派生伤害错：%.4f" % [variant_id, float(derived["damage"])]
		)
		_expect(
			is_equal_approx(float(derived["range"]), float(base_profile["range"]) * MonsterVariants.multiplier(base_kind, "attack_range_mult")),
			"%s 派生攻击距离错：%.4f" % [variant_id, float(derived["range"])]
		)
		# 速度与冷却不在业主口径内 ⇒ 必须逐字照抄。
		_expect(
			is_equal_approx(float(derived["speed"]), float(base_profile["speed"])),
			"%s 的速度被改动（业主未要求强化怪变速）" % variant_id
		)
		_expect(
			is_equal_approx(float(derived["cooldown"]), float(base_profile["cooldown"])),
			"%s 的冷却被改动" % variant_id
		)
		_samples += 1


# ⑥ 弹道只对声明了倍率的变种生效；其余怪与 Boss 的子弹逐字不变。
func _check_projectile_untouched_for_others() -> void:
	for plain in ["ranged_caster", "boss", "melee_chaser", "fat_zombie03", "summoner"]:
		var profile: Dictionary = Enemy3D.PROFILES[plain]
		_expect(
			not profile.has("projectile_speed"),
			"%s 的 PROFILES 里出现了 projectile_speed ⇒ 会改变既有子弹行为" % plain
		)
		_expect(
			not profile.has("projectile_range"),
			"%s 的 PROFILES 里出现了 projectile_range ⇒ 会改变既有子弹射程" % plain
		)
		_samples += 1
	# 强化远程怪必须拿到 9.1 m/s 与 14 m（= 基准 7 / 7 × 倍率）。
	var derived: Dictionary = Enemy3D.profile_for("ranged_caster_strong")
	_expect(
		is_equal_approx(float(derived.get("projectile_speed", 7.0)), Enemy3D.DEFAULT_ENEMY_PROJECTILE_SPEED * 1.3),
		"强化远程怪弹速应为 %.4f，实为 %.4f" % [Enemy3D.DEFAULT_ENEMY_PROJECTILE_SPEED * 1.3, float(derived.get("projectile_speed", 7.0))]
	)
	_expect(
		is_equal_approx(float(derived.get("projectile_range", 0.0)), Enemy3D.DEFAULT_ENEMY_PROJECTILE_RANGE_M * 2.0),
		"强化远程怪射程应为 %.4f，实为 %.4f" % [Enemy3D.DEFAULT_ENEMY_PROJECTILE_RANGE_M * 2.0, float(derived.get("projectile_range", 0.0))]
	)
	# 基准常量本身也要钉住：它们等于「改动前的事实」。
	_expect(
		is_equal_approx(Enemy3D.DEFAULT_ENEMY_PROJECTILE_SPEED, 7.0),
		"敌弹基准弹速应为 7.0（改动前的事实）"
	)
	_expect(
		is_equal_approx(Enemy3D.DEFAULT_ENEMY_PROJECTILE_RANGE_M, 7.0),
		"敌弹基准射程应为 7.0（= 1 秒存活 × 7 m/s）"
	)
	_samples += 1


# ⑦ 真实例：最终数值、体型、外观基类。
func _check_runtime_enemy() -> void:
	for base_kind in MonsterVariants.all_base_kinds():
		var variant_id := MonsterVariants.variant_of(base_kind)
		var plain := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(plain)
		plain.apply_profile(base_kind)
		var variant := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(variant)
		variant.apply_profile(variant_id)

		# 最要紧的一条：kind 真的被认下来了，没有悄悄回退成 melee_chaser。
		# 各处查表判据都是 `kind if TABLE.has(kind) else "melee_chaser"`，
		# 一旦漏登记，这里读到的会是 melee_chaser —— 静默退化就在这里现形。
		_expect(
			variant.enemy_kind == variant_id,
			"apply_profile(%s) 把 kind 改成了 %s ⇒ 静默退化" % [variant_id, variant.enemy_kind]
		)
		# `_table_kind()` 必须把变种映射回原怪 —— 体型表 / 血条表 / 血量基线表
		# 全靠它才能取到原怪那一行。
		_expect(
			variant._table_kind() == base_kind,
			"%s 的 _table_kind() 应为 %s，实为 %s" % [variant_id, base_kind, variant._table_kind()]
		)

		_expect(
			is_equal_approx(
				float(variant.max_hp),
				float(plain.max_hp) * MonsterVariants.multiplier(base_kind, "hp_mult")
			),
			"%s 实际生命 %d 不等于原怪 %d × %.2f"
			% [variant_id, variant.max_hp, plain.max_hp, MonsterVariants.multiplier(base_kind, "hp_mult")]
		)
		_expect(
			is_equal_approx(
				float(variant.contact_damage),
				float(plain.contact_damage) * MonsterVariants.multiplier(base_kind, "damage_mult")
			),
			"%s 实际伤害 %d 不等于原怪 %d × %.2f"
			% [variant_id, variant.contact_damage, plain.contact_damage, MonsterVariants.multiplier(base_kind, "damage_mult")]
		)
		_expect(
			is_equal_approx(
				variant.attack_range,
				plain.attack_range * MonsterVariants.multiplier(base_kind, "attack_range_mult")
			),
			"%s 攻击距离 %.4f 不等于原怪 %.4f × %.2f"
			% [variant_id, variant.attack_range, plain.attack_range, MonsterVariants.multiplier(base_kind, "attack_range_mult")]
		)
		_expect(
			is_equal_approx(
				variant.scale.x,
				plain.scale.x * MonsterVariants.multiplier(base_kind, "scale_mult")
			),
			"%s 体型 %.5f 不等于原怪 %.5f × %.2f"
			% [variant_id, variant.scale.x, plain.scale.x, MonsterVariants.multiplier(base_kind, "scale_mult")]
		)
		# 速度不变。
		_expect(
			is_equal_approx(variant.move_speed, plain.move_speed),
			"%s 移速被改动（业主未要求）" % variant_id
		)
		# 外观：必须挂上原怪的正式模型，而不是掉进程序化外壳。
		_expect(variant.avatar != null, "%s 的 avatar 为空" % variant_id)
		if variant.avatar != null:
			var snapshot: Dictionary = variant.avatar.get_component_snapshot()
			_expect(
				str(snapshot.get("base_kind", "")) == base_kind,
				"%s 的外观基类应为 %s，实为 %s"
				% [variant_id, base_kind, str(snapshot.get("base_kind", ""))]
			)
			_expect(
				bool(snapshot.get("formal_normal_asset", false)),
				"%s 没有挂上正式模型（掉进了程序化外壳分支）" % variant_id
			)
		# 头顶条宽必须取自原怪，而不是 table 缺失时的默认值 (1.65, 0.16)。
		_expect(
			variant._overhead_health_size.is_equal_approx(plain._overhead_health_size),
			"%s 头顶条宽 %s 与原怪 %s 不一致（疑似吃了查表默认值）"
			% [variant_id, str(variant._overhead_health_size), str(plain._overhead_health_size)]
		)
		# 碰撞体形状取自原怪，世界尺寸靠根 scale 放大 —— 不允许在形状上乘两遍。
		var variant_fp := EnemyAvatar3D.get_footprint_profile(variant_id)
		var plain_fp := EnemyAvatar3D.get_footprint_profile(base_kind)
		_expect(
			is_equal_approx(float(variant_fp["radius"]), float(plain_fp["radius"])),
			"%s 的碰撞半径在表里被放大了（会与根 scale 叠乘两次）" % variant_id
		)
		_samples += 1
		plain.free()
		variant.free()


# ⑧ 远征01：强化怪数值从原怪那一行派生，不另抄一份。
func _check_override_derivation() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		_fail("读不到 %s 的 monster_rules" % EXPEDITION_PLAN_PATH)
		return
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	var per_kind: Dictionary = (rules.get("stats", {}) as Dictionary).get("per_kind", {})
	for base_kind in MonsterVariants.all_base_kinds():
		if not per_kind.has(base_kind):
			continue
		var src: Dictionary = per_kind[base_kind]
		var variant_id := MonsterVariants.variant_of(base_kind)
		var data := injector._generate_basic_enemy(variant_id, 1, 0)
		_expect(
			data.has("override_max_hp"),
			"%s 没有派生出关卡生命覆盖（远征01 写了 %s.hp）" % [variant_id, base_kind]
		)
		if data.has("override_max_hp"):
			var want := int(round(float(src["hp"]) * MonsterVariants.multiplier(base_kind, "hp_mult")))
			_expect(
				int(data["override_max_hp"]) == want,
				"%s 关卡生命应为 %d（原怪 %s.hp × %.2f），实为 %d"
				% [variant_id, want, base_kind, MonsterVariants.multiplier(base_kind, "hp_mult"), int(data["override_max_hp"])]
			)
		if data.has("override_damage") and src.has("damage"):
			var want_dmg := int(round(float(src["damage"]) * MonsterVariants.multiplier(base_kind, "damage_mult")))
			_expect(
				int(data["override_damage"]) == want_dmg,
				"%s 关卡伤害应为 %d，实为 %d"
				% [variant_id, want_dmg, int(data["override_damage"])]
			)
		if data.has("override_speed") and src.has("speed"):
			_expect(
				is_equal_approx(float(data["override_speed"]), float(src["speed"])),
				"%s 的关卡速度应等于原怪 %.4f" % [variant_id, float(src["speed"])]
			)
		_samples += 1


# ⑨ 自爆半径派生；原怪不自爆 ⇒ 变种也不自爆。
func _check_death_explosion_derivation() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		return
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	var table: Dictionary = rules.get("death_explosion", {}) as Dictionary
	var src: Dictionary = table.get("fat_zombie03", {})
	var data := injector._generate_basic_enemy("fat_zombie03_strong", 1, 0)
	_expect(data.has("death_explosion"), "胖子僵尸-强化怪没有继承到自爆规格")
	if data.has("death_explosion"):
		var spec: Dictionary = data["death_explosion"]
		var want_radius := float(src.get("radius_m", 5.0)) * MonsterVariants.multiplier("fat_zombie03", "death_explosion_radius_mult")
		_expect(
			is_equal_approx(float(spec["radius_m"]), want_radius),
			"强化胖子自爆半径应为 %.4f（%.1f × 1.5），实为 %.4f"
			% [want_radius, float(src.get("radius_m", 5.0)), float(spec["radius_m"])]
		)
		_expect(
			int(spec["damage"]) == int(src.get("damage", 0)),
			"自爆伤害不该被改动（业主只说了范围）"
		)
		_samples += 1
	# 没有配自爆的原怪，其变种不许凭空长出自爆。
	var plain_probe := injector._generate_basic_enemy("melee_chaser_strong", 1, 0)
	_expect(
		not plain_probe.has("death_explosion"),
		"小僵尸-强化怪凭空获得了自爆（原怪没有）"
	)
	_samples += 1


# ⑩ 回归钉：zone 段必须透传，否则地面持续伤害场永远不会生成。
func _check_zone_passthrough_regression() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		return
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	var table: Dictionary = rules.get("death_explosion", {}) as Dictionary
	var src: Dictionary = table.get("fat_zombie03", {})
	_expect(src.has("zone"), "远征01 配置里已没有 zone 段，本回归钉失去意义")
	for kind in ["fat_zombie03", "fat_zombie03_strong"]:
		var data := injector._generate_basic_enemy(kind, 1, 0)
		if not data.has("death_explosion"):
			_fail("%s 没有自爆规格，无法验证 zone 透传" % kind)
			continue
		var spec: Dictionary = data["death_explosion"]
		_expect(
			spec.has("zone"),
			"%s 的 zone 段被丢弃 ⇒ Enemy3D._spawn_ground_blast_zone 永远不会生成地面伤害场（2026-10-16 修过的回归）" % kind
		)
		if spec.has("zone"):
			var zone: Dictionary = spec["zone"]
			_expect(
				is_equal_approx(float(zone.get("duration_sec", 0.0)), float((src["zone"] as Dictionary).get("duration_sec", 0.0))),
				"%s 的 zone 时长被改动" % kind
			)
		_samples += 1


# ⑪ 15% 概率统计成立。
func _check_roll_statistics() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		return
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	injector.set_seed(SEED)
	var strong := 0
	for _index in range(SAMPLE_COUNT):
		var data := injector._generate_basic_enemy("melee_chaser", 1, 0)
		if str(data["enemy_type"]) == "melee_chaser_strong":
			strong += 1
	var rate := float(strong) / float(SAMPLE_COUNT)
	_expect(
		rate > RATE_MIN and rate < RATE_MAX,
		"强化怪占比 %.4f 落在 [%.2f, %.2f] 之外（期望 0.15）" % [rate, RATE_MIN, RATE_MAX]
	)
	_samples += SAMPLE_COUNT


# ⑫ 同种子可复现。
func _check_reproducible_with_seed() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		return
	var first := _roll_sequence(rules, SEED)
	var second := _roll_sequence(rules, SEED)
	_expect(
		first == second,
		"同一 run_seed 两次生成的强化怪序列不一致（破坏可复现性）"
	)
	var other := _roll_sequence(rules, SEED + 1)
	_expect(
		first != other,
		"换了 run_seed 强化怪序列却完全相同（随机流没有真正接入种子）"
	)
	_samples += 2


func _roll_sequence(rules: Dictionary, seed_value: int) -> Array[String]:
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	injector.set_seed(seed_value)
	var out: Array[String] = []
	for _index in range(120):
		out.append(str(injector._generate_basic_enemy("melee_chaser", 1, 0)["enemy_type"]))
	return out


# ⑬ 未配置强化怪规则的关卡：不升级，且**一次随机数都不掷**。
func _check_unconfigured_level_unchanged() -> void:
	var injector := MonsterInjector.new()
	injector.set_seed(SEED)
	var before_state := injector._strong_rng.state
	var data := injector._generate_basic_enemy("melee_chaser", 2, 0)
	_expect(
		str(data["enemy_type"]) == "melee_chaser",
		"未配置 strong_variant 的关卡不该产出强化怪，实得 %s" % str(data["enemy_type"])
	)
	_expect(
		injector._strong_rng.state == before_state,
		"未配置的关卡掷了随机数 ⇒ 既有固定种子的产物会整体位移"
	)
	_samples += 2
	# 显式关闭同样不生效。
	var disabled := MonsterInjector.new()
	disabled.set_level_rules({"strong_variant": {"enabled": false, "chance": 0.9}})
	disabled.set_seed(SEED)
	var disabled_data := disabled._generate_basic_enemy("melee_chaser", 2, 0)
	_expect(
		str(disabled_data["enemy_type"]) == "melee_chaser",
		"enabled=false 时仍在产出强化怪"
	)
	_samples += 1


# ⑭ 精英是身份指派，不该被随机升级成强化怪。
func _check_elite_not_upgraded() -> void:
	var rules := _expedition_monster_rules()
	if rules.is_empty():
		return
	var injector := MonsterInjector.new()
	injector.set_level_rules(rules)
	injector.set_seed(SEED)
	# 直接验证门禁参数：allow_strong=false 时必须原样返回。
	for _index in range(200):
		var data := injector._generate_basic_enemy("melee_chaser", 1, 0, false)
		_expect(
			str(data["enemy_type"]) == "melee_chaser",
			"allow_strong=false 仍产出了 %s ⇒ 精英会被双重强化" % str(data["enemy_type"])
		)
	_samples += 200


func _expedition_monster_rules() -> Dictionary:
	var raw := FileAccess.get_file_as_string(EXPEDITION_PLAN_PATH)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var rules: Variant = (parsed as Dictionary).get("monster_rules", null)
	if not (rules is Dictionary):
		return {}
	return (rules as Dictionary).duplicate(true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("STRONG_VARIANT_OK: definition / registration / ratios / runtime / override / explosion / zone / roll / seed pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("STRONG_VARIANT_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)


# 实际攻击回归：只检查 profile 会漏掉强化保安掉进近战分支的问题。
func _check_real_ranged_attack() -> void:
	var pool := ProjectilePool3D.new()
	add_child(pool)
	for kind in ["ranged_caster", "ranged_caster_strong"]:
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		add_child(enemy)
		enemy.apply_profile(kind)
		enemy.set_physics_process(false)
		enemy.position = Vector3(0, 2.0, 0)
		var before := pool.get_child_count()
		enemy._perform_attack(Vector3.FORWARD, 4.0)
		_expect(pool.get_child_count() - before == 3, kind + " actual attack must emit 3 bullets")
		for index in range(before, pool.get_child_count()):
			var bullet := pool.get_child(index) as Projectile3D
			bullet.set_physics_process(false)
			_expect(is_equal_approx(bullet.global_position.y - enemy.global_position.y, 0.92), kind + " bullet height must stay 0.92m above feet")
			_expect(is_zero_approx(bullet.direction.y), kind + " bullets must fly horizontally")
			_expect(bullet.visible and bullet.find_child("*", true, false) != null, kind + " missing bullet visual")
			_expect(is_equal_approx(bullet.speed, 9.1 if kind.ends_with("_strong") else 7.0), kind + " wrong actual bullet speed")
			_expect(bullet.damage == enemy.contact_damage, kind + " wrong actual bullet damage")
		print("RANGED_ACTUAL ", kind, " bullets=", pool.get_child_count() - before, " height=0.92")
		_samples += 1
		# Bullets keep shooter references: release them before the shooter.
		for bullet in pool.get_children():
			bullet.free()
		enemy.free()
	pool.free()
