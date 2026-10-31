extends Node3D
## 仅采样美术骨动画。攻击事件与位移仍由 Enemy3D 拥有。
##
## 用 `preload` 而不是直接写全局类名：美术资产脚本随时可能被单独实例化
## （编辑器预览 / 探针 / 离线出图），那时 `.godot` 的全局类缓存不一定已扫到新脚本，
## 裸类名会报 `Identifier ... not declared`，且报错发生在解析期 ——
## 表现为"闪白整段消失、怪一动不动"，很难一眼看出是类解析问题（本轮实测踩过）。
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
## 管线缓存挂在使用中的材质上：不留一份长命引用，这只怪一回收，
## 同变体的材质下次又要重编译（实测每只 100ms 量级）。见 keeper 头注。
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
const DEATH_DURATION := 2.4
const VISUAL_HEIGHT := 1.857143
## 走路动画只服务巡逻；只要朝玩家方向移动（追击、搜寻、归位）一律用跑步，不按速度切档。
const CLIP_BY_STATE := {
	"dormant": "idle", "idle": "idle", "patrol": "walking", "alert": "idle",
	"chase": "running", "search": "running", "return": "running",
	"telegraph": "attack", "attack": "attack", "recovery": "attack",
	"stagger": "hurt", "dead": "dead",
}
var _player: AnimationPlayer
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _clock := 0.0
var _hurt_time := 1.0
var _flash_time := 0.0
var _materials: Array[StandardMaterial3D] = []
## 闪白基线（逐材质记下原始 emission 色与能量）。见 `HitFlashMaterial3D` 头注：
## 自发光开关是 shader 变体而不是 uniform，每翻一次要重建管线（实测 +80~100ms/次），
## 而闪白是"受击翻上去、0.12s 后翻回来"⇒ **每打中一下卡一下**（2026-10-31 业主报单）。
var _flash_baseline: Array = []
const FLASH_DURATION := 0.12

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "Zombie animation player missing")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
				Keeper.pin(material)
	_flash_baseline = HitFlash.prepare(_materials)
	sync_state("idle", 0.0, 0.0, 0.38, 0.34)

func _process(delta: float) -> void:
	_clock += delta
	_hurt_time += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	# 只推能量，**不碰 `emission_enabled`**（见 `_flash_baseline` 注释与 HitFlashMaterial3D 头注）。
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

## speed 仍按契约保留在参数位（调用方按顺序传入），但不再参与选段。
func sync_state(state: String, state_time: float, _speed: float, telegraph_duration: float, recovery_duration: float) -> void:
	_state = state
	# 速度不再参与选段：巡逻走、接近玩家跑，由状态唯一决定，避免同一状态在快慢档之间抖动。
	_clip = str(CLIP_BY_STATE.get(state, "idle"))
	if _player == null or not _player.has_animation(_clip):
		return
	var length := _player.get_animation(_clip).length
	_sample = fmod(_clock, maxf(length, 0.001))
	match state:
		"dormant": _sample = 0.0
		"telegraph": _sample = length * 0.48 * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack": _sample = length * 0.48
		"recovery": _sample = length * lerpf(0.48, 1.0, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
		"stagger": _sample = length * clampf(state_time / 0.16, 0.0, 1.0)
		"dead": _sample = minf(state_time, length)
	# 非硬直受击只覆盖表现，不延迟攻击与伤害事件。
	if _hurt_time < 0.8 and state not in ["dead", "telegraph", "attack", "recovery", "stagger", "dormant"]:
		_clip = "hurt"
		_sample = _hurt_time
	_player.play(_clip)
	_player.seek(_sample, true)

func flash_hit() -> void:
	if _state != "dead":
		_hurt_time = 0.0
		_flash_time = FLASH_DURATION

func get_presentation_snapshot() -> Dictionary:
	return {"state": _state, "clip": _clip, "sample_time": _sample,
		"visual_height": VISUAL_HEIGHT, "death_duration": DEATH_DURATION,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"source": "blender_v005", "collision_owned": false, "procedural_pose": false}
