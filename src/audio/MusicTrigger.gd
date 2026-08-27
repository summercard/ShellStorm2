class_name MusicTrigger
extends Node
## 触发点抽象组件。挂场景任意节点上即可，无需关心播放细节。
##
## 用法 1（节点触发）：在 _ready() / 流程节点里调用 `trigger.play("base_passion")`
## 用法 2（自动触发）：把本节点挂到场景任意位置，配合 autoplay_on_ready=true，
##                    场景 ready 时自动 MusicManager.play(self.music_id)
##
## 触发器**只负责发指令**，不持有 AudioStreamPlayer，不持有 fade 状态。

@export var music_id: String = ""
## 是否在节点进入场景树时自动 play()
@export var autoplay_on_ready: bool = false
## 是否在节点离开场景树时 restore()（仅当此前由本触发器压栈时生效）
@export var restore_on_exit: bool = false

const ManagerScript = preload("res://src/audio/MusicManager.gd")

var _pushed: bool = false


func _ready() -> void:
	if autoplay_on_ready and music_id != "":
		play(music_id)


func play(p_music_id: String = "") -> bool:
	var target := p_music_id if p_music_id != "" else music_id
	if target == "":
		push_warning("[MusicTrigger] music_id 为空，跳过触发")
		return false
	var mgr := _get_manager()
	if mgr == null:
		push_warning("[MusicTrigger] MusicManager 不存在（autoload 未注册）")
		return false
	# 压栈语义：让 restore_on_exit 能在退出时回到原曲
	if not _pushed:
		mgr.push_and_play(target)
		_pushed = true
	else:
		mgr.play(target)
	return true


func stop() -> void:
	var mgr := _get_manager()
	if mgr != null:
		mgr.stop()


func restore() -> void:
	var mgr := _get_manager()
	if mgr == null:
		return
	if _pushed:
		mgr.restore()
		_pushed = false


func _exit_tree() -> void:
	if restore_on_exit:
		restore()


func _get_manager() -> Node:
	return get_node_or_null("/root/MusicManager")