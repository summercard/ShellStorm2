class_name Base99TelescopicLadder3D
extends Node3D
## 99F 东阁楼→100F 的一次性展开直梯。局部原点是下层落脚点。

const TRAVEL_HEIGHT := 6.0
const DEPLOY_SECONDS := 0.85
const LOWER_RETRACTED_Y := 2.5
## +Z 是踏棍正面；关卡实例绕 Y 轴 -90°，使其朝向阁楼内侧(-X)。
const FACE_OFFSET_Z := 0.42
const TOP_LANDING_Z := -1.0
const BOTTOM_LANDING_Z := 1.45

var deployed := false
var _deploy_progress := 0.0
@onready var lower_visual: Node3D = $LowerVisual
@onready var lower_collision: StaticBody3D = $LowerCollision


func _ready() -> void:
	add_to_group("interaction_provider_3d")
	deployed = BaseManager != null and BaseManager.is_base99_rooftop_ladder_deployed()
	_deploy_progress = 1.0 if deployed else 0.0
	_update_visual()


func _process(delta: float) -> void:
	if deployed and _deploy_progress < 1.0:
		_deploy_progress = minf(1.0, _deploy_progress + delta / DEPLOY_SECONDS)
		_update_visual()


func _update_visual() -> void:
	if lower_visual != null:
		lower_visual.position.y = LOWER_RETRACTED_Y * (1.0 - _deploy_progress)
	if lower_collision != null:
		# 动画期间只移动视觉件，不推动动态物体；完全落锁后才启用下段碰撞。
		lower_collision.position.y = 0.0
		lower_collision.collision_layer = 1 if deployed and _deploy_progress >= 1.0 else 0


func get_climb_position(progress: float) -> Vector3:
	var clamped := clampf(progress, 0.0, 1.0)
	# 最后10%穿过现有东门洞，在100F门外平台落脚；反向会沿同一路径退回。
	var across := clampf((clamped - 0.9) / 0.1, 0.0, 1.0)
	# 跨过门槛时轻抬脚底，避免胶囊体从侧面切进100F楼板，落地后再由地面承托。
	var step_lift := 1.6 * across * (1.0 - across)
	var height := TRAVEL_HEIGHT * minf(clamped / 0.9, 1.0) + step_lift + 0.1 * across
	return to_global(Vector3(0.0, height, lerpf(FACE_OFFSET_Z, TOP_LANDING_Z, across)))


func get_exit_position(at_top: bool) -> Vector3:
	return to_global(Vector3(0.0, TRAVEL_HEIGHT + 0.1 if at_top else 0.1, TOP_LANDING_Z if at_top else BOTTOM_LANDING_Z))


func prepare_upper_exit() -> void:
	var door := get_tree().root.find_child("BaseRooftopTransitDoor", true, false) as RoomDoor3D
	if door != null:
		door.set_open(true, true)


func get_interaction_candidate(player: Player3D) -> Dictionary:
	if player == null or player.input_locked or player.current_hp <= 0:
		return {}
	var top := get_exit_position(true)
	var bottom := get_exit_position(false)
	if not deployed:
		if player.get_state_machine_state() in ["idle", "moving"] and player.global_position.distance_to(top) < 1.5:
			return {"available": true, "interaction_id": "deploy_ladder", "prompt": "E 放下伸缩梯", "priority": 90, "position": top}
		return {}
	if _deploy_progress < 1.0 or player.get_state_machine_state() not in ["idle", "moving"]:
		return {}
	if player.global_position.distance_to(bottom) < 1.45:
		return {"available": true, "interaction_id": "climb_ladder_up", "prompt": "E 爬上直梯", "priority": 85, "position": bottom}
	if player.global_position.distance_to(top) < 1.45:
		return {"available": true, "interaction_id": "climb_ladder_down", "prompt": "E 爬下直梯", "priority": 85, "position": top}
	return {}


## 常驻圆点锚点：取梯子中段，玩家在任一端都能一眼看到。
func get_interaction_dot_anchor() -> Vector3:
	return to_global(Vector3(
		0.0, TRAVEL_HEIGHT * 0.5, (TOP_LANDING_Z + BOTTOM_LANDING_Z) * 0.5
	))


func get_interaction_dot_accent() -> Color:
	return Color(0.72, 0.88, 1.0)


func perform_interaction(player: Player3D, candidate: Dictionary) -> bool:
	match str(candidate.get("interaction_id", "")):
		"deploy_ladder":
			if deployed or player.global_position.distance_to(get_exit_position(true)) >= 1.5:
				return false
			if BaseManager != null and not BaseManager.deploy_base99_rooftop_ladder():
				return false
			deployed = true
			return true
		"climb_ladder_up":
			return deployed and _deploy_progress >= 1.0 and player.try_start_ladder_climb(self, true)
		"climb_ladder_down":
			return deployed and _deploy_progress >= 1.0 and player.try_start_ladder_climb(self, false)
	return false
