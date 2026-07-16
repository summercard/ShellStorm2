## BossCombatState - Boss"战斗"状态
##
## 行为：HP>0 的战斗状态。
## 每帧：处理伤害冷却、tick 阶段 Director、检查 HP 阈值触发阶段切换。
## 退出：HP <= 0 → 进入 dead。

class_name BossCombatState
extends BossStateBase

func enter() -> void:
	super.enter()
	boss._activated = true
	boss._is_dead = false
	boss._invulnerable = false
	if boss._phase_director:
		boss._phase_director.set_process(true)

func physics_update(delta: float) -> void:
	if boss._damage_cooldown_timer > 0:
		boss._damage_cooldown_timer -= delta
	# 检查 HP 阈值触发阶段切换
	var hp_pct: float = boss._current_hp / boss.max_hp
	if boss._phase_director and boss._phase_director.has_method("check_hp_threshold"):
		boss._phase_director.check_hp_threshold(hp_pct)

## 处理 take_damage 事件（从 BossActor.take_damage 转发）
func handle_event(event_name: String, data = null) -> void:
	if event_name == "take_damage":
		if boss._is_dead or boss._invulnerable:
			return
		if boss._damage_cooldown_timer > 0:
			return
		var damage: float = float(data.get("damage", 0.0)) if data is Dictionary else 0.0
		var is_crit: bool = bool(data.get("is_crit", false)) if data is Dictionary else false
		boss._current_hp -= damage
		boss._damage_cooldown_timer = boss.damage_cooldown
		boss.current_hp = boss._current_hp
		if boss.hp_bar:
			boss.hp_bar.value = max(0, boss._current_hp)
		if boss.has_method("_take_damage_feedback"):
			boss._take_damage_feedback(is_crit)
		if boss.has_method("_spawn_damage_number"):
			boss._spawn_damage_number(boss.global_position, int(damage), is_crit)
		if boss.has_method("_trigger_hit_screen_shake"):
			boss._trigger_hit_screen_shake(damage, is_crit)
		if boss.has_method("_notify_boss_damaged"):
			boss._notify_boss_damaged(damage)
		Global.trigger_hitstop(is_crit)
		# HP 归零：切到 dead
		if boss._current_hp <= 0:
			boss._state_machine.transition_to("dead", true)
