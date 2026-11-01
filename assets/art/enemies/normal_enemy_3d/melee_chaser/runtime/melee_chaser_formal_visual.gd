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
## 退出跑步段的比值。与 `RUN_SPEED_RATIO` 差 0.12 构成**迟滞**：
## 只在阈值单侧抖动时不会来回换段（换段本身是"抽一下"的唯一来源）。
const RUN_EXIT_RATIO := 0.50
## 归一化用的满速跟随实际速度的时间常数（秒）。见 `_smooth_base_speed()`。
const BASE_SPEED_SMOOTH_SEC := 0.30
## 循环段的播放速率上下限（实际速度 ÷ 该段标称速度）。见 `_playback_rate()`。
const PLAYBACK_RATE_MIN := 0.25
const PLAYBACK_RATE_MAX := 2.0
## 循环移动段之间的交叉淡化时长（秒）。见 `sync_state()` 的换段段。
##
## 走路段和跑步段**手臂姿势本来就不同**（走路自然垂摆、跑步抬起），
## 所以"相位对齐"消不掉换段那一跳（实测仍差 35~67°，落在 `L/R_Upperarm`）。
## 用 `AnimationPlayer.play(name, blend)` 做淡入后，实测当帧跳变 **60.4° → 0.0°**。
## 0.16 s 是走路周期（1.6 s）的 1/10：够吸收，又不至于让"进入追击"读起来发软。
const CLIP_BLEND_SEC := 0.16
## 参与交叉淡化的段。攻击/受击/死亡有玩法时序（判定帧靠 `seek` 钉死），
## 一律不淡化 —— 混进去会让前摇读不出来，也会把判定帧推开。
const BLENDABLE_CLIPS := [
	"idle", "walking", "running",
	"armed_idle", "walking_armed", "running_armed",
]
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
## `_base_speed` 上一次被平滑的时刻（秒，取自 `_clock`）。见 `_smooth_base_speed()`。
var _base_speed_clock := 0.0
## 循环段的**归一化播放相位**（0..1）。跨段保留 —— 这是"换段不再抽一下"的关键，
## 推导见 `sync_state()` 里 `_phase` 的注释。
var _phase := 0.0
## 当前段长度（秒），`_process` 推进相位要用。
var _clip_length := 1.0
## 当前段是否是循环段（走路/跑步/站立）。只有循环段才按 `_phase` 播放。
var _looping := false
## 进这一段时"它本来该走多快"（m/s）。之后减速不再换段，只按它把动画放慢。
## 见 `_playback_rate()`。
var _nominal_speed := 0.0
## 交叉淡化剩余时间（秒）。> 0 时不 `seek()`，让引擎自己把两段淡开。见 `sync_state()`。
var _blend_left := 0.0
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
	# 循环语义双保险：导入脚本（`melee_chaser_post_import.gd`）已经设过一次，
	# 但这里也钉一遍 —— 表现层靠 `_looping` 决定是否推进相位，判错就定格。
	# 警察僵尸那份 GLB 没有导入脚本，靠的就是这一行。
	for clip_name in _player.get_animation_list():
		if str(clip_name) in BLENDABLE_CLIPS:
			_player.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
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
	# 循环段的相位按「实际速度 ÷ 该段标称速度」推进：
	# 被手电照到减速时动画跟着变慢（脚不打滑），不再靠换段表达速度变化。
	# 淡化期强制 1×：此时引擎自己在推进新段，相位必须和它同步，
	# 否则淡化结束恢复 `seek()` 会把姿势弹回别处。
	if _blend_left > 0.0:
		_blend_left = maxf(0.0, _blend_left - delta)
		# 淡化期由引擎推进：这是 `play(name, blend)` 的权重真正生效的唯一方式。
		# 手动 `seek()` 会把姿势直接钉到新段，淡化等于没做。
		if _player != null:
			_player.advance(delta)
		# 直接读取引擎推进后的相位，含淡化结束的最后一帧；不能另算一条时钟。
		if _clip_length > 0.0:
			_phase = fposmod(_player.current_animation_position / _clip_length, 1.0)
	elif _looping and _clip_length > 0.0:
		var rate := _playback_rate()
		_phase = fmod(_phase + delta * rate / _clip_length, 1.0)
	# 只推能量，**不碰 `emission_enabled`**（见 `_flash_baseline` 注释与 HitFlashMaterial3D 头注）。
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

## speed 只用于**判定**（能否踉跄、走还是跑），不参与其它选段。
func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, recovery_duration: float, base_speed := 0.0
) -> void:
	_state = state
	_locomotion_speed = absf(speed)
	_smooth_base_speed(base_speed)
	var previous_clip := _clip
	_clip = _locomotion_clip(str(CLIP_BY_STATE.get(state, "idle")), previous_clip)
	if _player == null or not _player.has_animation(_clip):
		return
	var anim := _player.get_animation(_clip)
	var length := maxf(anim.length, 0.001)
	_looping = anim.loop_mode != Animation.LOOP_NONE
	if _clip != previous_clip:
		# 换段只更新"这一段该走多快"。之后减速由 `_playback_rate()` 放慢动画表达，
		# **不再**因此换段 —— 业主："受到光照正常来说只会缩短移动速度和动画播放速度"。
		_nominal_speed = maxf(_locomotion_speed, 0.001)
	var sample := 0.0
	if _looping:
		# ## 相位跨段保留（本次修复的核心）
		#
		# 旧写法 `_sample = fmod(_clock, length)` 用**绝对时钟**取模。走路段 1.6 s、
		# 跑步段 0.8 s，同一个 `_clock` 在两段里落在**完全不同的姿势**上
		# （实测同一时刻相差 34~83°，是中位帧的 21~50 倍），且 `play()+seek()`
		# 没有混合 ⇒ 只要换段就"抽一下"，换回来又抽一下。
		#
		# 改成归一化相位后，走路与跑步都是左右腿循环、相位语义一致，
		# 在同一个 `_phase` 处两段姿势接近 ⇒ 换段时姿势连续。
		# 这条与光照无关：任何原因（状态切换、速度档切换）导致的换段都不会再抽。
		sample = _phase * length
		if state == "dormant":
			sample = 0.0
			_phase = 0.0
	else:
		# 非循环段（攻击/受击/死亡/硬直）必须钉在各自的显式相位上，
		# 播完把 `_phase` 同步成末帧比例，回到循环段时不会从别处突然开始。
		match state:
			"telegraph": sample = length * 0.48 * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			"attack": sample = length * 0.48
			"recovery": sample = length * lerpf(0.48, 1.0, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
			"stagger": sample = length * clampf(state_time / 0.16, 0.0, 1.0)
			"dead": sample = minf(state_time, length)
			_: sample = 0.0
		_phase = clampf(sample / length, 0.0, 1.0)
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
		anim = _player.get_animation(_clip)
		length = maxf(anim.length, 0.001)
		_looping = false
		sample = _hurt_time
		_phase = clampf(sample / length, 0.0, 1.0)
	_sample = sample
	_clip_length = length
	# 循环移动段之间做交叉淡化：这是"换段不抽一下"的第二半（第一半是相位连续）。
	# `AnimationPlayer.play(name, custom_blend)` 会把**当前姿势**淡入新段，
	# 实测把换段当帧的骨骼跳变从 60.4° 压到 0.0°。
	var blend := _clip != previous_clip and previous_clip in BLENDABLE_CLIPS and _clip in BLENDABLE_CLIPS
	if blend:
		_blend_left = CLIP_BLEND_SEC
		# `play()` 从新段的 0 秒开始播，相位必须跟着归零；否则淡化结束恢复 seek
		# 时会按旧相位把姿势弹回去（又变成一次硬切）。
		_phase = 0.0
		_sample = 0.0
		_player.play(_clip, CLIP_BLEND_SEC)
	elif _clip != previous_clip or _blend_left <= 0.0:
		# 战斗/死亡/受击打断移动淡化时，必须当帧取消淡化并采样权威进度。
		_blend_left = 0.0
		# 淡化结束后回到"每帧 play + seek"。⚠ 这两句不能只留 seek：
		# `callback_mode_process = MANUAL` 下单独 `seek()` **不会驱动骨架**
		# （本轮实测踩过：以为已经修好，实际画面定格，髋部高度恒定 0.3980）。
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
##
## ## 加迟滞（本轮）：`previous` 已经是跑步段时，要掉到 `RUN_EXIT_RATIO` 以下才退回走路
##
## 没有迟滞时，只要比值在 0.62 附近抖一下就会换段、再换回来。而**换段本身**
## 在旧实现里就是"抽一下"的唯一来源（相位被重置，见 `sync_state()` 的 `_phase` 注释）。
## 现在相位已经连续，迟滞是第二道保险：让瞬态减速（手电扫到、被击退、贴墙推挤）
## 根本不去碰段名。
func _locomotion_clip(clip: String, previous: String) -> String:
	var ratio := _speed_ratio()
	if ratio < 0.0:
		return clip
	var running_now := previous.contains("running")
	if clip == "walking":
		if running_now:
			return "walking" if ratio < RUN_EXIT_RATIO else "running"
		return "running" if ratio >= RUN_SPEED_RATIO else clip
	if clip == "idle" and _state in ["idle", "patrol"]:
		# 状态说"站着"，人却在位移 ⇒ 必须换成移动段，否则就是滑行。
		if running_now:
			return "running" if ratio >= RUN_EXIT_RATIO else "walking"
		if ratio >= RUN_SPEED_RATIO:
			return "running"
		if ratio >= RUN_SPEED_RATIO * 0.5:
			return "walking"
	return clip


## 循环段的播放速率 = 实际速度 ÷ 进段时的标称速度。
##
## 业主："受到光照正常来说只会缩短角色的移动速度和动画播放速度"。
## 手电照到会让移速掉到 0.40×，位移变慢而动画照旧全速播 = 脚往前滑。
## 所以减速时按比例把动画也放慢，速度回到标称值就回到 1.0。
## 上下钳制防止极端值把相位推飞（0.25× 仍能看出在动，2.0× 不至于抽搐）。
func _playback_rate() -> float:
	if _nominal_speed <= 0.01:
		return 1.0
	return clampf(_locomotion_speed / _nominal_speed, PLAYBACK_RATE_MIN, PLAYBACK_RATE_MAX)


## 实际速度 / 满速。满速缺失（调用方没传）时按绝对阈值兜底，
## 阈值 1.4 m/s 是"小僵尸巡逻 1.0 / 追击 2.0"的中点。
func _speed_ratio() -> float:
	if _base_speed > 0.01:
		return _locomotion_speed / _base_speed
	if _locomotion_speed <= 0.01:
		return 0.0
	return _locomotion_speed / 1.4


## 满速要**跟着实际速度一起衰减**，不能阶跃。
##
## ## 业主："好像是在阴影下，受到手电光照的情况下，表现会有异常"
##
## 手电照到怪物会让 `Enemy3D.get_effective_move_speed()` 立刻乘上
## `ARTIFICIAL_LIGHT_MOVE_MULTIPLIER = 0.40`。那是**阶跃**；
## 而真实速度由 `_steer_planar()` 以 `delta * 3.2~5.5` 的权重指数衰减，
## 要走 0.13 s（巡逻）到 0.5 s（半速档）才跟上。
##
## 两者不同步时，比值 `_locomotion_speed / _base_speed` 会在光扫到的那几帧里
## **冲过 0.62 阈值再落回来**（实测：0.32 → 0.77 → 0.61），于是段名在
## 走路/跑步之间翻两次。而换段时 `_sample = fmod(_clock, 新段长)` ——
## 1.6 s 的走路段与 0.8 s 的跑步段把同一个绝对时刻映射到完全不同的姿势，
## 且没有混合 ⇒ **一帧内骨骼被硬拽 34~83°**（中位 1.6°，即 21~50 倍），
## 读起来就是"走路走着突然抽一下"。15 秒内实测 8 次，全部发生在手电扫到的瞬间。
##
## 让分母用同一个时间常数指数跟随即可：比值在手电扫到的整个过渡期里
## 稳定等于真实档位（0.32 / 1.0），稳态读数与改前逐字相同。
func _smooth_base_speed(base_speed: float) -> void:
	if base_speed <= 0.0:
		return
	if _base_speed <= 0.0:
		_base_speed = base_speed
		_base_speed_clock = _clock
		return
	var step := clampf(_clock - _base_speed_clock, 0.0, 0.25)
	_base_speed_clock = _clock
	if step <= 0.0:
		return
	var weight := 1.0 - exp(-step / BASE_SPEED_SMOOTH_SEC)
	_base_speed = lerpf(_base_speed, base_speed, weight)


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
		"locomotion_speed": _locomotion_speed,
		# 平滑后的归一化满速。验收要判"手电扫到时比值不冲阈值"，必须能看到分母。
		"base_speed": _base_speed,
		"speed_ratio": _speed_ratio(),
		"phase": _phase,
		"playback_rate": _playback_rate()}
