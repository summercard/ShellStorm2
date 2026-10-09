class_name VfxEnvBirdsFlyby3D
extends Node3D
## 一次性环境鸟群：由跨塔吊桥拥有，不进入战斗特效池。
##
## 生命周期（2026-10-09 修正）：源动画是**单次完整演出**（首尾不闭环），因此不做
## 循环播放；但原实现「播完即 queue_free」会让玩家绝大多数时间看不到鸟（12 秒后
## 节点已被释放）。现改为**环境循环**：播完 → 隐藏 → 静默间隔 → 从头重播。
## 重置只发生在不可见期间，观众面前不会闪跳。
##
## 另修一处致命缺陷：7 只鸟各自一条动画，原代码只播第一条 ⇒ 只有 01 号鸟在动，
## 其余 6 只冻结在静止姿势。现由 VfxEnvBirdsPlayback 并行播放全部动画。
##
## 用 preload 而不是全局类名：headless 跑探针时编辑器类名缓存可能未刷新，
## 直接引全局类名会报 "Identifier not declared"。

const PLAYBACK := preload("res://assets/art/vfx/environment_3d/bird_flocks/runtime/vfx_env_birds_playback.gd")
const DURATION_SECONDS := 12.0
## 两次掠过之间的静默间隔（秒）。隐藏期间重置动画。
const AMBIENT_GAP_SECONDS := 20.0

var _cycling := false


func _ready() -> void:
	set_meta("asset_id", "VFX-ENV-BIRDS-FLYBY-3D")
	set_meta("asset_version", "v001")
	set_meta("lifecycle", "cross_tower_route_ambient_repeat")
	set_meta("cycle_seconds", DURATION_SECONDS + AMBIENT_GAP_SECONDS)
	set_meta("collision", "none")
	_start_cycling.call_deferred()


func _start_cycling() -> void:
	if _cycling:
		return
	_cycling = true
	while is_inside_tree():
		visible = true
		if not PLAYBACK.play_all(self):
			push_error("VFX-ENV-BIRDS-FLYBY-3D has no playable animation")
			return
		await get_tree().create_timer(DURATION_SECONDS).timeout
		if not is_inside_tree():
			return
		visible = false
		await get_tree().create_timer(AMBIENT_GAP_SECONDS).timeout
