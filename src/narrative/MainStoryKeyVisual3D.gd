class_name MainStoryKeyVisual3D
extends Node3D
## 同一永久钥匙的临时表现；不领取、不转移库存、不写存档。

var _player: Node3D
var _npc: Node3D
var _player_hand: Node3D
var _npc_hand: Node3D
var _phase := "display"
var _elapsed := 0.0
var _duration := 0.0
var _from := Transform3D.IDENTITY
var _slot := Vector3.ZERO
var _slot_basis := Basis.IDENTITY
## 嵌入孔是斜的：孔心只是参照点，真正插到位的钥匙柄沿孔轴抬到台面上方。
var _slot_origin_offset := Vector3.ZERO
var _handoff_contact := Vector3.ZERO
var _handoff_done := false
var _inserted := false
var _player_hand_before := Transform3D.IDENTITY
var _npc_hand_before := Transform3D.IDENTITY
var _hand_height := 0.5
var _projection_root: Node

func setup_performance(player: Node3D, npc: Node3D) -> void:
	_projection_root = get_parent()
	_player = player
	_npc = npc
	_player_hand = _hand(player, false)
	_npc_hand = _hand(npc, true)
	if _player_hand != null:
		_player_hand_before = _player_hand.transform
	if _npc_hand != null:
		_npc_hand_before = _npc_hand.transform
		_hand_height = _npc_hand.global_position.y - npc.global_position.y + 0.12
	process_priority = 200
	hide()

func _hand(actor: Node3D, npc: bool) -> Node3D:
	if actor == null:
		return null
	if npc:
		return actor.get("_hand_r") as Node3D
	var avatar := actor.get("avatar") as Node3D
	return avatar.get("bunny_hand_r") as Node3D if avatar != null else null

func perform(action: String, params: Dictionary) -> bool:
	if not is_instance_valid(_player_hand) or not is_instance_valid(_npc_hand):
		return false
	_elapsed = 0.0
	match action:
		"present":
			_face_npc(_player.global_position)
			_phase = "present"
			_duration = 0.8
			_from = _player_hand.global_transform
			reparent(_player_hand, false)
			transform = Transform3D.IDENTITY
			scale = Vector3.ONE * 1.2
			show()
		"handoff":
			if _phase != "player_hold":
				return false
			_phase = "handoff"
			_duration = 1.15
			_from = global_transform
			_handoff_contact = (_player.global_position + _npc.global_position) * 0.5 + Vector3.UP * _hand_height
			_npc.call("scripted_gesture", "receive_key")
		"insert":
			if not _handoff_done or not params.get("slot") is Vector3:
				return false
			_phase = "insert"
			_duration = 1.2
			_from = global_transform
			_slot = params["slot"]
			_slot_basis = params.get("basis", Basis.IDENTITY)
			# 斜孔：孔心 → 钥匙柄的偏移由嵌件给出，动画不得写死竖直插入。
			_slot_origin_offset = params.get("origin_offset", Vector3.ZERO)
			_face_npc(_slot)
			_npc.call("scripted_gesture", "insert_key")
		_:
			return false
	return true

func _process(delta: float) -> void:
	if _phase == "display" or _phase == "inserted":
		return
	if not is_instance_valid(_player_hand) or not is_instance_valid(_npc_hand):
		return
	_elapsed += delta
	var weight := smoothstep(0.0, 1.0, clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0))
	var forward := (_npc.global_position - _player.global_position).normalized()
	match _phase:
		"present", "player_hold":
			var target := _player.global_position + forward * 0.45 + Vector3.UP * _hand_height
			_player_hand.global_position = _from.origin.lerp(target, weight) if _phase == "present" else target
			global_basis = Basis(Vector3.UP, atan2(-forward.x, -forward.z)).scaled(Vector3.ONE * 1.2)
			global_position = _player_hand.global_position
			if weight >= 1.0:
				_phase = "player_hold"
		"handoff":
			var contact_weight := smoothstep(0.0, 0.6, clampf(_elapsed / _duration, 0.0, 1.0))
			_player_hand.global_position = _from.origin.lerp(_handoff_contact, contact_weight)
			_npc_hand.global_position = _npc_hand.global_position.lerp(_handoff_contact, contact_weight)
			global_position = _from.origin.lerp(_handoff_contact, contact_weight)
			if contact_weight >= 1.0 and not _handoff_done:
				reparent(_npc_hand, true)
				_handoff_done = true
			if weight >= 1.0:
				_player_hand.transform = _player_hand_before
				_phase = "npc_hold"
		"npc_hold":
			var carry := _npc.global_position - _npc.global_basis.z.normalized() * 0.35 + Vector3.UP * _hand_height
			_npc_hand.global_position = carry
			global_position = carry
		"insert":
			var target := _slot + _slot_origin_offset
			var approach := target + (_slot_basis.z * 0.16) * (1.0 - weight)
			var position_now := _from.origin.lerp(approach, weight)
			# 手跟着握把抬起来；但绿苔只有 1.2 m 高、孔口在 1.5 m 台面上，
			# 手臂最多再抬 0.45 m —— 剩下的行程是钥匙被吸进孔里，不是手继续伸长。
			var hand_target := position_now
			if is_instance_valid(_npc):
				var reach_limit: float = _npc.global_position.y + _hand_height + 0.45
				hand_target.y = minf(position_now.y, reach_limit)
			_npc_hand.global_position = hand_target
			global_position = position_now
			global_basis = _from.basis.orthonormalized().slerp(_slot_basis.orthonormalized(), weight).scaled(Vector3.ONE * lerpf(1.2, 0.72, weight))
			if weight >= 1.0:
				reparent(_projection_root, true)
				_phase = "inserted"
				_inserted = true

func _face_npc(point: Vector3) -> void:
	var direction := point - _npc.global_position
	_npc.call("set_scripted_facing", atan2(-direction.x, -direction.z))

func is_busy() -> bool:
	return _phase in ["present", "handoff", "insert"]

func is_insertion_complete() -> bool:
	return _inserted

func get_snapshot() -> Dictionary:
	return {"phase": _phase, "busy": is_busy(), "handoff_done": _handoff_done,
		"inserted": _inserted, "position": global_position, "parent": str(get_parent().name) if get_parent() != null else "",
		"asset_id": "ITM-MAIN-STORY-RARE-EARTH-KEY", "ownership": "visual_projection_only"}

func cleanup_performance() -> void:
	if is_instance_valid(_player_hand):
		_player_hand.transform = _player_hand_before
	if is_instance_valid(_npc_hand):
		_npc_hand.transform = _npc_hand_before
	_phase = "display"
	hide()
