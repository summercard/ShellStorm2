class_name VfxEnvBirdsPlayback
extends RefCounted
## 鸟群动画播放工具（两套鸟群共用）。
##
## 【问题一】两套鸟群 GLB 都是「每只鸟一条 Action」—— 7 只鸟 = 同一个 AnimationPlayer
## 上的 7 条动画（`flyby_bird_01..07` / `ground_bird_01..07`）。而 Godot 的
## AnimationPlayer **同一时刻只能播一条**。早期接入代码「找到第一条可播动画就 play
## 并 break」⇒ 实际只有 01 号鸟在动，其余 6 只冻结在 glTF 静止姿势（悬在半空）。
##
## 【问题二】直接给 7 条动画各建一个播放器并行播**也不行**：实测每条动画里都含有
## **全部 7 只鸟**的轨道（147 条轨道 = 7 鸟 × 21 通道），其中只有自己那只鸟有位移、
## 其余 6 只是静止关键帧。7 个播放器并行时，每只鸟被 7 条动画同时写入 ⇒ 后写的覆盖
## 先写的，最终只有最后一条动画对应的那只鸟在动。
##
## 【解决】两步缺一不可：
##   1. **裁剪**：把每条动画裁成「只保留自己那只鸟的轨道」——按「哪只鸟的位移轨跨度
##      最大」自动判定归属，不依赖命名序号；
##   2. **并行**：第 1 条用原播放器，其余每条各建一个同 `root_node` 的播放器。
## 裁剪后的动画放进各自的 **独立命名动画库**（`birds/`），绝不改写 GLB 自带的默认库，
## 因此不会污染被缓存的导入资源。

const EXTRA_PLAYER_PREFIX := "BirdAnimPlayer_"
## 裁剪后动画所放的动画库名。刻意不用默认库（`""`），避免改写导入资源。
const PRUNED_LIBRARY := "birds"
## 判定「鸟分组有位移」的最小跨度（米）。低于此值视为静止关键帧，不认。
const MOTION_EPSILON_M := 0.01


## 播放全部鸟的动画；返回是否至少播成一条。
static func play_all(host: Node) -> bool:
	return _apply(host, true)


## 停止全部鸟的动画（用于单次演出重播前归零）。
static func stop_all(host: Node) -> void:
	_apply(host, false)


static func _apply(host: Node, should_play: bool) -> bool:
	var primary := _primary_player(host)
	if primary == null:
		return false
	var source_names := _source_animation_names(primary)
	if source_names.is_empty():
		return false
	var players := _ensure_players(primary, source_names.size())
	var played := false
	for index in players.size():
		var player := players[index]
		var playable := _prepare_track(primary, player, source_names[index])
		if playable == "":
			continue
		player.stop()
		if should_play:
			player.play(playable)
			played = true
	return played


static func _primary_player(host: Node) -> AnimationPlayer:
	for child in host.find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null


## 只取 GLB 自带默认库里的动画名，排除我们自己加的裁剪库。
static func _source_animation_names(primary: AnimationPlayer) -> Array[String]:
	var names: Array[String] = []
	if not primary.has_animation_library(""):
		return names
	var library := primary.get_animation_library("")
	if library == null:
		return names
	for candidate in library.get_animation_list():
		if candidate != "RESET":
			names.append(candidate)
	names.sort()
	return names


static func _ensure_players(primary: AnimationPlayer, count: int) -> Array[AnimationPlayer]:
	var parent := primary.get_parent()
	var players: Array[AnimationPlayer] = [primary]
	if parent == null:
		return players
	for index in range(1, count):
		var node_name := "%s%02d" % [EXTRA_PLAYER_PREFIX, index]
		var extra := parent.get_node_or_null(NodePath(node_name)) as AnimationPlayer
		if extra == null:
			extra = AnimationPlayer.new()
			extra.name = node_name
			parent.add_child(extra)
			# root_node 必须与主播放器一致，动画里的相对路径才能解析到同一批鸟。
			extra.root_node = primary.root_node
		players.append(extra)
	return players


## 从 `source_player` 取原始动画，裁剪成「只含本播放器那只鸟」后放进 `player` 自己的
## 裁剪库（`birds/`），返回可直接 `play()` 的完整名；失败返回空串。
## 注意源动画一律从 primary 取 —— 新建的播放器不持有 GLB 默认库。
static func _prepare_track(
	source_player: AnimationPlayer, player: AnimationPlayer, source_name: String
) -> String:
	var playable := "%s/%s" % [PRUNED_LIBRARY, "%s__pruned" % source_name]
	if player.has_animation(playable):
		return playable
	var source := source_player.get_animation(source_name)
	if source == null:
		return ""
	var library: AnimationLibrary = null
	if player.has_animation_library(PRUNED_LIBRARY):
		library = player.get_animation_library(PRUNED_LIBRARY)
	else:
		library = AnimationLibrary.new()
		player.add_animation_library(PRUNED_LIBRARY, library)
	library.add_animation("%s__pruned" % source_name, _prune_to_own_bird(source))
	return playable


## 找出动画里「位移跨度最大」的鸟分组，删掉不属于它的全部轨道。
## 判定靠实测位移而非命名序号，因此换源动画也不会错配。
static func _prune_to_own_bird(source: Animation) -> Animation:
	var group := _dominant_moving_group(source)
	var pruned := source.duplicate(true) as Animation
	if group == "":
		# 找不到有明显位移的分组（例如全静止演出）⇒ 原样保留，不做破坏性裁剪。
		return pruned
	for index in range(pruned.get_track_count() - 1, -1, -1):
		if not str(pruned.track_get_path(index)).contains(group):
			pruned.remove_track(index)
	return pruned


static func _dominant_moving_group(animation: Animation) -> String:
	var spans: Dictionary = {}
	for index in animation.get_track_count():
		if animation.track_get_type(index) != Animation.TYPE_POSITION_3D:
			continue
		var key_count := animation.track_get_key_count(index)
		if key_count < 2:
			continue
		var group := _bird_group_of(str(animation.track_get_path(index)))
		if group == "":
			continue
		var first := animation.track_get_key_value(index, 0) as Vector3
		var last := animation.track_get_key_value(index, key_count - 1) as Vector3
		var span := first.distance_to(last)
		spans[group] = maxf(float(spans.get(group, 0.0)), span)
	var best_group := ""
	var best_span := MOTION_EPSILON_M
	for key in spans:
		if float(spans[key]) > best_span:
			best_span = float(spans[key])
			best_group = str(key)
	return best_group


## 轨道路径形如 `鸟群_整体移动缩放控制/鸟01_动作控制/Skeleton3D:body`，
## 取第二段（每只鸟的根节点）作为分组键。
static func _bird_group_of(track_path: String) -> String:
	var parts := track_path.split("/")
	if parts.size() < 2:
		return ""
	return parts[1]
