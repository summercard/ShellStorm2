class_name ClipMotionLibrary3D
extends CharacterMotionLibrary3D
## Clip-driven motion library for whole-skinned characters (maid01 / chuck201).
## Same shape as CharacterMotionLibrary3D: bind(avatar) / apply(avatar, delta).
## Loop flags are copied from the Blender JSON library because GLB import marks every clip LOOP_NONE.
## Presentation-only: reads player state, writes presentation nodes.
const CLIP_LIBRARY_VERSION := "clip_v001"
## Loop corrections: clips the JSON marks non-looping but the player holds as a sustained state.
## Evidence: measured first/last frame seam <= 0.1 deg, so looping cannot snap.
const LOOP_OVERRIDES := {
	
"falling": true,
}
const LOOP_SOURCE_LIBRARY := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.json"
const GRIP_LOCAL_ROTATION := Vector3.ZERO
const SYNC_BONES := {
	"body": "mixamorig_Hips",
	"head": "mixamorig_Head",
	"hand_l": "mixamorig_LeftHand",
	"hand_r": "mixamorig_RightHand",
	"foot_l": "mixamorig_LeftFoot",
	"foot_r": "mixamorig_RightFoot",
}

var _anim_player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _model_root: Node3D = null
var _rig: Node3D = null
var _bone_index: Dictionary = {}
var _current_clip := ""
var _planar_speed := 0.0
## 褰撳墠琚彊浜嬮拤甯ч拤浣忕殑鍓緫鍚嶏紙绌?= 涓嶅湪閽夊抚锛夈€傜敤浜庨伩鍏嶆瘡甯ч噸澶?seek銆
var _pose_locked_clip := ""
## 寰幆鏍囪绉绘缁撴灉锛堣瘖鏂敤锛屼緵楠屾敹璇诲彇锛夈€
## `loop_flags_total` = JSON 涓?GLB 鍚嶅瓧瀵逛笂鐨勫壀杈戞暟锛
## `loop_flags_applied` = 瀹為檯鍐欒繘 Animation 鐨勬暟閲忥紙鐞嗚涓婁袱鑰呯浉绛夛級锛
## `loop_source` = "bunny_json" / "missing_library" / "none"銆
var loop_flags_total := 0
var loop_flags_applied := 0
var loop_source := "none"
## 鍓緫鍚?鈫?鏄惁搴斿惊鐜紙鏉ヨ嚜 JSON 搴擄級銆
var _loop_flags: Dictionary = {}


static func _find_first(root: Node, cls: String) -> Node:
	if root == null:
		return null
	if root.is_class(cls):
		return root
	for child in root.get_children():
		var found := _find_first(child, cls)
		if found != null:
			return found
	return null


func bind(avatar: Node3D) -> void:
	_version = "clip"
	library_version = CLIP_LIBRARY_VERSION
	_rig = avatar.get_node_or_null("VisualRoot/BunnyRig") as Node3D
	_model_root = avatar.get_node_or_null("VisualRoot/BunnyRig/Model") as Node3D
	_anim_player = _find_first(_model_root, "AnimationPlayer") as AnimationPlayer
	_skeleton = _find_first(_model_root, "Skeleton3D") as Skeleton3D
	_bone_index.clear()
	if _skeleton != null:
		for index in range(_skeleton.get_bone_count()):
			_bone_index[_skeleton.get_bone_name(index)] = index
	_nodes = {
		"root": avatar.visual_root,
		"body": avatar.body,
		"head": avatar.head,
		"feet": avatar.feet,
		"hand_l": avatar.bunny_hand_l,
		"hand_r": avatar.bunny_hand_r,
		"foot_l": avatar.foot_l,
		"foot_r": avatar.foot_r,
		"ear_l": avatar.ear_socket_l,
		"ear_r": avatar.ear_socket_r,
		"weapon_socket": avatar.weapon_socket,
	}
	_weapon_socket_rest = avatar.weapon_socket.transform
	_current_clip = ""
	_apply_loop_flags()
	if _anim_player != null and _anim_player.has_animation("idle"):
		_anim_player.play("idle")
		_current_clip = "idle"


## 浠庤€侀€氶亾 JSON 搴撴妸 `loop` 鏍囪鎶勫埌 GLB 鐨?Animation 涓娿€
##
## 蹇呴』鍦?*浠讳綍 `play()` 涔嬪墠**璋冪敤锛歚loop_mode` 鏄?Animation 璧勬簮鑷韩鐨勫睘鎬э紝
## 鏀逛簡绔嬪埢瀵逛笅涓€娆?play 鐢熸晥锛涗絾姝ｅ湪鎾殑鍓緫鑻ヨ鏀规垚 LOOP_NONE 浼氬綋鍦哄畾鏍硷紝
## 鎵€浠ラ『搴忔槸鍏堣鏍囪銆佸啀璧锋挱銆
##
## 鍙銆孞SON 閲屾湁杩欐鍓緫銆嶇殑锛汮SON 涓?GLB 鍚嶅瓧涓嶄竴鑷存椂**璺宠繃骞惰鏁?*锛
## 鐢?`loop_flags_applied` / `loop_flags_total` 涓婃姤锛屼笉闈欓粯鎴愬姛銆
func _apply_loop_flags() -> void:
	loop_flags_applied = 0
	loop_flags_total = 0
	loop_source = "none"
	_loop_flags.clear()
	if _anim_player == null:
		return
	var library := _load_loop_library()
	var clips: Dictionary = library.get("clips", {})
	if clips.is_empty():
		loop_source = "missing_library"
		return
	loop_source = "bunny_json"
	for clip_name in _anim_player.get_animation_list():
		var key := str(clip_name)
		if not clips.has(key):
			continue
		loop_flags_total += 1
		var wants_loop := bool((clips[key] as Dictionary).get("loop", false))
		_loop_flags[key] = wants_loop
		if LOOP_OVERRIDES.has(key):
			wants_loop = bool(LOOP_OVERRIDES[key])
			_loop_flags[key] = wants_loop
		var animation := _anim_player.get_animation(key)
		if animation == null:
			continue
		## 淇敼 Animation 璧勬簮浼?*褰卞搷鎵€鏈夊紩鐢ㄥ畠鐨勫疄渚?*锛圙LB 鏄叡浜祫婧愶級銆
		## 杩欓噷鏄湁鎰忕殑锛氬悓涓€浠?GLB 鐨勫惊鐜涔夋湰灏辫涓€鑷淬€
		## 鑻ュ皢鏉ュ嚭鐜般€屽悓涓€瑙掕壊涓嶅悓鍓緫闇€瑕佷笉鍚屽惊鐜€嶇殑闇€姹傦紝蹇呴』鍏?duplicate()銆?		animation.loop_mode = Animation.LOOP_LINEAR if wants_loop else Animation.LOOP_NONE
		loop_flags_applied += 1


## 璇诲惊鐜湡婧愩€傜紦瀛樺埌闈欐€佸瓧鍏?鈥斺€?`load()` 涓嶆槸绋冲畾寮曠敤锛堣祫婧愮紦瀛樻槸寮卞紩鐢級锛
## 姣忎釜瑙掕壊瀹炰緥閮介噸璇讳竴娆＄洏浼氱櫧鑺卞嚑鍗佹绉掋€
static var _loop_library_cache: Dictionary = {}


func _load_loop_library() -> Dictionary:
	if not _loop_library_cache.is_empty():
		return _loop_library_cache
	var file := FileAccess.open(LOOP_SOURCE_LIBRARY, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	_loop_library_cache = parsed as Dictionary
	return _loop_library_cache


## 璇ュ壀杈戞槸鍚﹁鏍囪涓哄惊鐜紙渚涙帰閽堜笌楠屾敹璇诲彇锛涙棤鏁版嵁鏃惰繑鍥?false锛夈€
func clip_wants_loop(clip_name: String) -> bool:
	return bool(_loop_flags.get(clip_name, false))


func _has_anim(clip_name: String) -> bool:
	return _anim_player != null and _anim_player.has_animation(clip_name)


func apply(avatar: Node3D, delta: float) -> void:
	if _anim_player == null or _skeleton == null or _rig == null:
		return
	var wanted := _resolve_clip_name(avatar, delta)
	var played := _play_clip(wanted)
	active_clip = played
	if pose_lock_enabled:
		_apply_pose_lock(avatar)
	_sync_joints(avatar)
	_sync_weapon_socket(avatar)


## 鍙欎簨閽夊抚锛氭妸褰撳墠鍓緫**纭仠鍦?* `pose_lock_phase` 鎸囧畾鐨勪竴甯т笂銆
##
## 涓轰粈涔堝繀椤绘湁杩欎竴鏉★細寮€鍦哄墽鏈?`nar_tower_opening_01_wake` 鐢
## `{clip: "dead", phase: 1.0, frozen: true}` 璁╄鑹层€岃洞鍦ㄥ湴涓娿€嶏紝7 绉掑悗
## `to_phase: 0.0` 鍙嶅悜鎺ㄥ洖 0 瀹炵幇銆岃捣韬€嶃€傝€侀€氶亾
## (`CharacterMotionLibrary3D`) 鍦ㄩ噰鏍峰惊鐜噷璇?`pose_lock_phase`锛
## 鍓緫閫氶亾璧扮殑鏄?`AnimationPlayer`锛?*娌℃湁鐩镐綅鍙傛暟鍙啓** 鈥斺€
## 棣栫増婕忎簡杩欐潯 鈬?鎹㈣鑹插悗寮€鍦鸿鑹蹭細**绔欑潃鎾浜″姩鐢?*锛岃€屼笉鏄洞鐫€銆
##
## 鍋氭硶锛歚seek` 鍒般€屽綊涓€鍖栫浉浣?脳 鍓緫闀垮害銆嶇殑浣嶇疆鍚?*鍋滀綇鎾斁**锛坰peed_scale = 0锛夈€
## 涓嶈兘鐢?`pause()`锛氶偅浼氭妸鏁翠釜 AnimationPlayer 鍐讳綇锛岃В闄ら拤甯ф椂杩樺緱璁板緱 play 鍥炴潵锛
## `speed_scale = 0` 涓?`play()` 缁勫悎鏄箓绛夌殑 鈥斺€?瑙ｉ櫎鍚庝笅涓€甯ф甯?`play(clip)` 鍗冲彲鎭㈠锛
## 涓嶉渶瑕侀澶栫殑鐘舵€佸浣嶃€
func _apply_pose_lock(avatar: Node3D) -> void:
	var clip_name := active_clip
	if clip_name.is_empty() or not _anim_player.has_animation(clip_name):
		return
	var animation := _anim_player.get_animation(clip_name)
	if animation == null:
		return
	var clip_length := maxf(0.001, animation.length)
	var target := clampf(pose_lock_phase, 0.0, 1.0) * clip_length
	# 娣″寲鏈熶笉鑳?seek锛堜細鎵撴柇娣″寲锛夛紱鍏堣 advance 璧板畬杩欎竴甯х殑娣″寲锛屼笅涓€甯у啀閽夈€
	if _anim_player.is_playing() and _anim_player.current_animation != clip_name:
		return
	_anim_player.speed_scale = 0.0
	_anim_player.seek(target, true)
	_pose_locked_clip = clip_name


# 鈥斺€?鍓緫鍚嶈В鏋愶細瑙勫垯涓?CharacterMotionLibrary3D.apply 涓€鑷达紝鍙槸銆屾湁杩欐鍓緫鍚椼€
#    鐢?AnimationPlayer 鑰屼笉鏄?JSON 搴撳洖绛斻€?鈥斺€
func _resolve_clip_name(avatar: Node3D, delta: float) -> String:
	var state: String = avatar.get("_state")
	var family := str(avatar.get("_weapon_class"))
	var armed := bool(avatar.get("_weapon_grip_pose_active")) and family in ["sidearm", "longgun", "machinegun"]
	var locomotion_name := state
	_planar_speed = 0.0
	var world_velocity := Vector3.ZERO
	if state == "moving" and avatar.get("_player") != null:
		var owner: Node = avatar.get("_player")
		var parameters: Dictionary = owner.call("get_locomotion_presentation_snapshot") if owner.has_method("get_locomotion_presentation_snapshot") else {}
		var velocity: Variant = parameters.get("world_velocity", owner.get("velocity"))
		if velocity is Vector3:
			world_velocity = velocity
			_planar_speed = Vector2(velocity.x, velocity.z).length()
			if _planar_speed > 0.05 and _planar_speed < 3.2 and _has_anim("walking"):
				locomotion_name = "walking"
	speed_role = locomotion_name
	fallback_reason = "none"
	var weapon_id := str(avatar.get("_equipped_gun_id"))
	var firing := armed and bool(avatar.get("_firing_animation_active"))
	if not armed or state not in ["idle", "moving"] or bool(avatar.get("_reload_animation_active")) or weapon_id != _fire_weapon_id:
		_fire_hold_remaining = 0.0
	_fire_weapon_id = weapon_id
	if armed and state in ["idle", "moving"] and not bool(avatar.get("_reload_animation_active")):
		_fire_hold_remaining = FIRE_HOLD_DURATION_S if firing else maxf(0.0, _fire_hold_remaining - delta)
	var reload_now := armed and bool(avatar.get("_reload_animation_active")) and state in ["idle", "moving", "seated"]
	var switch_snapshot: Dictionary = {}
	if avatar.get("_player") != null and avatar.get("_player").has_method("get_weapon_transition_snapshot"):
		switch_snapshot = avatar.get("_player").call("get_weapon_transition_snapshot")
	var switch_now := bool(switch_snapshot.get("active", false))
	# 鈥斺€?鍩虹浣嶅Э 鈥斺€
	var clip_name := locomotion_name
	if state in ["idle", "moving", "walking", "locked"]:
		var pose_family := family if armed else "unarmed"
		if state == "moving" or state == "walking":
			var local_velocity: Vector3 = avatar.visual_root.global_basis.orthonormalized().inverse() * world_velocity
			movement_direction = select_direction(local_velocity, movement_direction)
			clip_name = "%s_%s_%s" % [pose_family, locomotion_name, movement_direction]
		elif state == "locked" and not armed:
			clip_name = "locked"
		elif armed:
			clip_name = family + "_idle"
		else:
			clip_name = "idle"
		if armed and _fire_hold_remaining > 0.0 and not reload_now:
			var fire_clip := (
				"%s_fire_%s_%s" % [family, locomotion_name, movement_direction]
				if state in ["moving", "walking"]
				else family + "_fire_idle"
			)
			if _has_anim(fire_clip):
				clip_name = fire_clip
			else:
				fallback_reason = "missing_" + fire_clip
	# 鈥斺€?鎹㈡灙锛堟嫈/鏀讹級浼樺厛浜庣珯绔嬩綅濮?鈥斺€
	if not switch_now:
		pass
	elif state in ["idle", "moving", "seated"]:
		var switch_name := "%s_%s_slot%d" % [
			str(switch_snapshot.get("family", family)),
			str(switch_snapshot.get("phase", "draw")),
			int(switch_snapshot.get("slot", 0)),
		]
		if _has_anim(switch_name):
			clip_name = switch_name
		else:
			fallback_reason = "missing_" + switch_name
	# 鈥斺€?鎹㈠脊鏁存鎾斁锛堜笉鍋氬彔鍔狅紝鍓緫鏈綋灏辨槸鎹㈠脊锛夆€斺€
	## `active_overlay` / `overlay_progress` 鏄?*璺ㄩ€氶亾濂戠害**锛氳€侀€氶亾鐢ㄥ畠涓婃姤
	## 銆屽綋鍓嶆鍦ㄦ挱鐨勬槸鍝瑕嗙洊鍔ㄤ綔銆佽蛋鍒板嚑鎴愩€嶏紝楠屾敹鐢ㄤ緥涓
	## `PlayerAvatar3D._get_missing_authored_action()` 閮借杩欎袱涓瓧娈点€
	## 鍓緫閫氶亾鏃╂湡鐗堟湰鍙浜?`overlay_progress` 灏辨妸 `active_overlay` 娓呯┖锛
	## 浜庢槸銆屾崲寮瑰壀杈戠‘瀹炲湪鎾€嶈繖浠朵簨**鍦ㄥ揩鐓ч噷璇讳笉鍑烘潵**锛堥獙鏀跺叏绾級銆?	active_overlay = ""
	overlay_progress = 0.0
	if reload_now and _has_anim(family + "_reload"):
		clip_name = family + "_reload"
		overlay_progress = clampf(float(avatar.get("_reload_progress")), 0.0, 1.0)
		active_overlay = family + "_reload"
	elif reload_now:
		fallback_reason = "missing_" + family + "_reload"
	# 鈥斺€?杩戞垬 鈥斺€
	var melee_family := str({"bp_baseball_bat": "bat", "bp_greatblade": "blade", "bp_waraxe": "axe"}.get(weapon_id, ""))
	var melee_now := family == "heavy_melee" and bool(avatar.get("_melee_animation_active")) and state in ["idle", "moving"]
	var melee_hold := family == "heavy_melee" and state in ["idle", "moving", "locked"] and not melee_family.is_empty()
	if melee_now:
		var melee_phase := str(avatar.get("_melee_phase"))
		var mode := "normal"
		var owner: Node = avatar.get("_player")
		if owner != null and owner.get("melee_combat") != null:
			mode = str((owner.get("melee_combat").get_snapshot() as Dictionary).get("attack_mode", "normal"))
		if melee_phase == "charging":
			clip_name = "melee_%s_charge" % melee_family
		elif mode == "spin":
			clip_name = "melee_blade_spin" if melee_phase == "spinning" else "melee_blade_spin_recovery"
		elif mode == "charged":
			clip_name = "melee_%s_charged_%s" % [melee_family, melee_phase]
		else:
			clip_name = "melee_%s_%d_%s" % [melee_family, int(avatar.get("_melee_combo_step")), melee_phase]
	elif melee_hold and state != "moving":
		clip_name = "melee_%s_idle" % melee_family
	# 鈥斺€?缂哄壀杈戝氨鍥炶惤锛屽苟璁板師鍥?鈥斺€
	if not _has_anim(clip_name):
		if fallback_reason == "none":
			fallback_reason = "missing_" + clip_name
		if _has_anim(locomotion_name):
			clip_name = locomotion_name
		elif _has_anim("idle"):
			clip_name = "idle"
	if state == "moving" and _planar_speed > 0.0:
		var walking_clip := locomotion_name == "walking"
		var rate := clampf(_planar_speed / (2.4 if walking_clip else 5.0), 0.72, 1.18)
		if not walking_clip:
			rate *= RUN_CLIP_RATE_SCALE
		playback_rate = rate * ANIMATION_RATE_MULTIPLIER
	else:
		playback_rate = ANIMATION_RATE_MULTIPLIER
	reference_speed_mps = 0.0
	return clip_name


func _play_clip(wanted: String) -> String:
	var resolved := wanted
	if resolved == "longgun_idle":
		resolved = "armed_idle"
	## 2026-11-08: sidearm_fire_idle whips head 84.3deg; sidearm_idle is 12.5deg and same pistol pose.
	if resolved == "sidearm_fire_idle":
		resolved = "sidearm_idle"
	if resolved.is_empty() or not _anim_player.has_animation(resolved):
		var fallback := "idle"
		if not _anim_player.has_animation(fallback):
			var list := _anim_player.get_animation_list()
			return list[0] if not list.is_empty() else ""
		if fallback_reason == "none":
			fallback_reason = "missing_" + resolved
		resolved = fallback
	## 閽夊抚鏈熼棿**涓嶈**鏀?speed_scale锛歚_apply_pose_lock()` 鐢ㄥ畠鍋氥€屽仠浣忋€嶏紝
	## 杩欓噷姣忓抚閲嶅啓浼氭妸瑙掕壊浠庨拤浣忕殑閭ｄ竴甯т笂鏀惧紑锛堣〃鐜颁负寮€鍦?瓒翠笅"鎶栦竴涓嬪張绔欒捣鏉ワ級銆
	if not pose_lock_enabled:
		_anim_player.speed_scale = maxf(0.05, playback_rate)
	if resolved != _current_clip:
		var blend := 0.05 if "_fire_" in resolved else 0.15
		# 閽夊抚鏃朵笉鍋氭贰鍖栧垏鎹細娣″寲浼氳瑙掕壊浠庡綋鍓嶅Э鍔挎粦鍚戞柊鍓緫鐨勭 0 甯э紝
		# 銆岃洞鐫€銆嶈繖涓叆鐐瑰氨娌′簡銆傜洿鎺ュ垏銆侀殢鍚庣敱 `_apply_pose_lock()` 閽変綇鐩爣甯с€
		if pose_lock_enabled:
			blend = 0.0
		_current_clip = resolved
		_anim_player.play(resolved, blend)
	return resolved


# 鈥斺€?琛ㄧ幇鎸傜偣 鈫?楠ㄩ 鈥斺€
func _bone_world(bone_name: String) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(int(_bone_index[bone_name]))


func _sync_joints(avatar: Node3D) -> void:
	var rig_inverse := _rig.global_transform.affine_inverse()
	for node_key in SYNC_BONES:
		var target: Node3D = _nodes.get(node_key)
		if target == null:
			continue
		var bone_name: String = SYNC_BONES[node_key]
		if not _bone_index.has(bone_name):
			continue
		target.transform = rig_inverse * _bone_world(bone_name)


func _sync_weapon_socket(avatar: Node3D) -> void:
	var socket: Marker3D = avatar.weapon_socket
	if socket == null or not _bone_index.has("mixamorig_RightHand"):
		return
	var rig_inverse := _rig.global_transform.affine_inverse()
	var palm := (rig_inverse * _bone_world("mixamorig_RightHand")).origin
	# 鎸傜偣鍙彇鎵嬫帉浣嶇疆锛涙湞鍚戜繚鎸佽鑹叉鍓嶆柟锛岃鏋彛绋冲畾鎸囧悜姝ｉ潰銆?	socket.transform = Transform3D(Basis.from_euler(GRIP_LOCAL_ROTATION), palm)
	# 涓庤€侀€氶亾涓€鑷达細鎸佹墜鏋?闀挎灙鏃跺彸鎵嬬洿鎺ュ帇鍦ㄦ寕鐐逛笂锛屾崲寮圭幆闅忎箣瀵归綈銆
	if str(avatar.get("_weapon_class")) in ["sidearm", "longgun"] and avatar.bunny_hand_r != null:
		avatar.bunny_hand_r.global_position = socket.global_position
