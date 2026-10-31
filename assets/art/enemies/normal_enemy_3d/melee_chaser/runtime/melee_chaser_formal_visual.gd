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
## 走路 / 跑步的分界（相对满速的比例）。见 `_locomotion_clip()`。
const RUN_SPEED_RATIO := 0.62
var _player: AnimationPlayer
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _clock := 0.0
var _hurt_time := 10.0
var _flash_time := 0.0
## 本帧的**实际水平速度**（`Enemy3D` 用 `get_real_velocity()` 传进来）。
## 受击姿态要不要播、移动放走还是跑，判据都是它而不是状态名 —— 原因见 `sync_state`。
var _locomotion_speed := 0.0
## 这只怪的满速（`get_effective_move_speed()`）。用来把实际速度换算成比例。
var _base_speed := 0.0
## 本次受击是否允许播受击姿态。太阳伤害传 false：它每秒结算一次，
## 播姿态会让怪在跑动中反复被塞 hurt 段（= 漂移）。
var _hurt_pose_allowed := true
var _materials: Array[StandardMaterial3D] = []
## 闪白基线（逐材质记下原始 emission 色与能量）。见 `HitFlashMaterial3D` 头注：
## 自发光开关是 shader 变体而不是 uniform，每翻一次要重建管线（实测 +80~100ms/次），
## 而闪白是"受击翻上去、0.12s 后翻回来"⇒ **每打中一下卡一下**（2026-10-31 业主报单）。
var _flash_baseline: Array = []
const FLASH_DURATION := 0.12
## 受击姿态时长（秒）。旧值 0.8 s 是在"没有打断移动"的前提下写死的，
## 结果是追击中的怪有 0.8 s 看着在扑、人却在滑 —— 0.28 s 只够一个缩肩。
const HURT_POSE_DURATION := 0.28
## 超过这个水平速度就**不播**受击姿态（只闪白）。0.45 m/s 低于任何一只怪的移动档，
## 又高于分离推挤/击退的抖动值，等于"站着的才会踉跄"。
const HURT_POSE_MAX_SPEED := 0.45
## 允许播受击姿态的状态：只有**本来就不推进位移**的那几个。
## telegraph/attack/recovery 有自己的段，stagger 是硬直段，chase/search/return 在跑。
const HURT_POSE_STATES := ["idle", "alert", "patrol"]

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

## speed 只用于**判定**（能否踉跄、走还是跑），不参与其它选段。
func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, recovery_duration: float, base_speed := 0.0
) -> void:
	_state = state
	_locomotion_speed = absf(speed)
	if base_speed > 0.0:
		_base_speed = base_speed
	_clip = _locomotion_clip(str(CLIP_BY_STATE.get(state, "idle")))
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
	#
	# ⚠ 三条闸门缺一不可（2026-10-31 业主"受击后整只怪漂移"）：
	#   ① `_hurt_pose_allowed` —— 太阳伤害这类**环境结算**干脆不播姿态；
	#   ② `_locomotion_speed <= HURT_POSE_MAX_SPEED` —— 在跑的怪只闪白。
	#      旧实现只判状态名，`chase` 不在排除表里 ⇒ hurt 段整段盖掉 running，
	#      而位移照旧按 chase 推进，画面就是"原地扑咬的动画被平移"；
	#   ③ 状态白名单 —— 只有本来就不推进位移的 idle/alert/patrol 能踉跄。
	if (
		_hurt_pose_allowed
		and _hurt_time < HURT_POSE_DURATION
		and _locomotion_speed <= HURT_POSE_MAX_SPEED
		and state in HURT_POSE_STATES
	):
		_clip = "hurt"
		_sample = _hurt_time
	_player.play(_clip)
	_player.seek(_sample, true)

## 受击。闪白一定给（0.12 s，纯 uniform 能量，不重建管线）；
## 受击姿态由 `play_hit_pose` 决定，且**还要过速度闸门**才真的播。
## 按**实际速度**把移动段在 walking / running 之间改判。
##
## ## 为什么不能只按状态名给段（2026-10-31 业主："移动的时候都没使用跑步动画"）
## `CLIP_BY_STATE` 把 `chase` 映射成 running，这在塔楼老怪身上够用 —— 它们的位移
## 只有"巡逻慢走"和"追击全速"两种。但远征03 的复刻怪多出一批**位移由外推接管**的形态：
## 冲撞（11 m/s）、逃跑（×1.45）、游荡、瞬移后重定位、抓取下压抛人。
## 这些形态的 `ai_state` 往往还是 `patrol` 甚至 `idle` —— 于是"以 11 m/s 突进"的怪
## 播的是走路段甚至站立段，看起来就是**模型在漂**（业主报的正是这个）。
##
## 判据换成"实际速度 ÷ 满速"，与状态名解耦：
##   ≥ 62%   ⇒ running（追击 / 突进 / 逃跑）
##   30~62%  ⇒ walking（巡逻）
##   < 30%   ⇒ 保留状态名给的段（多半是 idle，正常）
## 老怪的速度分布本来就满足这条：追击 ≈ 100%、巡逻 = 50%，改判后与原来逐字一致。
func _locomotion_clip(clip: String) -> String:
	var ratio := _speed_ratio()
	if ratio < 0.0:
		return clip
	if clip == "walking":
		return "running" if ratio >= RUN_SPEED_RATIO else clip
	if clip == "idle" and _state in ["idle", "patrol"]:
		# 状态说"站着"，人却在位移 ⇒ 必须换成移动段，否则就是滑行。
		if ratio >= RUN_SPEED_RATIO:
			return "running"
		if ratio >= RUN_SPEED_RATIO * 0.5:
			return "walking"
	return clip


## 实际速度 / 满速。满速缺失（调用方没传）时按绝对阈值兜底，
## 阈值 1.4 m/s 是"小僵尸巡逻 1.0 / 追击 2.0"的中点。
func _speed_ratio() -> float:
	if _base_speed > 0.01:
		return _locomotion_speed / _base_speed
	if _locomotion_speed <= 0.01:
		return 0.0
	return _locomotion_speed / 1.4


func flash_hit(play_hit_pose := true) -> void:
	if _state == "dead":
		return
	_flash_time = FLASH_DURATION
	if play_hit_pose:
		_hurt_pose_allowed = true
		_hurt_time = 0.0
	else:
		_hurt_pose_allowed = false

func get_presentation_snapshot() -> Dictionary:
	return {"state": _state, "clip": _clip, "sample_time": _sample,
		"visual_height": VISUAL_HEIGHT, "death_duration": DEATH_DURATION,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"source": "blender_v005", "collision_owned": false, "procedural_pose": false,
		# 受击姿态的三条闸门逐条暴露，验收才能断言"跑动中不播 hurt"而不是只看 clip 名。
		"hurt_pose_allowed": _hurt_pose_allowed,
		"hurt_pose": _clip == "hurt",
		"hurt_time": _hurt_time,
		"locomotion_speed": _locomotion_speed}
