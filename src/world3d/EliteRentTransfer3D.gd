class_name EliteRentTransfer3D
extends Node3D
## 收租成功后的纯视觉转移实体。
## 它不加入 ground_loot_3d，不碰 InventoryModule，也不参与任何拾取事务。

const TRAIL_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_elite_rent_transfer_trail_root_top3d.tscn")
const TRANSFER_ASSET_ID := "VFX-ELITE-RENT-TRANSFER-3D"
const TRAIL_ASSET_ID := "VFX-ELITE-RENT-TRANSFER-TRAIL-3D"
const TRANSFER_DURATION_S := 0.92
const DROP_DURATION_S := 0.34
const DROP_HEIGHT_M := 0.82
const ARC_HEIGHT_M := 1.15
const VISUAL_SCALE := 0.70

var item_data: Dictionary = {}
var source_position := Vector3.ZERO
var collector_position := Vector3.ZERO
var _visual: Node3D
var _trail: Node3D
var _elapsed := 0.0
var _drop_start := Vector3.ZERO
var _drop_end := Vector3.ZERO
var _flight_start := Vector3.ZERO
var _flight_end := Vector3.ZERO
var _phase := 0

func configure(data: Dictionary, from_position: Vector3, to_position: Vector3) -> void:
	item_data = WeaponInstance.ensure_weapon_item(data)
	source_position = from_position
	collector_position = to_position
	_drop_start = source_position
	_drop_end = source_position
	_flight_start = source_position
	_flight_end = collector_position
	set_meta("asset_id", TRANSFER_ASSET_ID)
	set_meta("item_asset_id", "")
	set_meta("runtime_save_excluded", true)
	_build_visual()
	_build_trail()

func _ready() -> void:
	set_process(false)
	set_meta("asset_id", TRANSFER_ASSET_ID)
	set_meta("runtime_save_excluded", true)

func begin() -> void:
	if _visual == null:
		queue_free()
		return
	_elapsed = 0.0
	_phase = 0
	set_process(true)
	_visual.global_position = _drop_start
	_trail.global_position = _drop_start
	_trail.call("set_tint", ItemModelFactory3D.get_item_color(item_data))

func _process(delta: float) -> void:
	_elapsed += delta
	if _phase == 0:
		var drop_t := clampf(_elapsed / DROP_DURATION_S, 0.0, 1.0)
		var dropped := _drop_start.lerp(_drop_end + Vector3.UP * 0.05, drop_t)
		dropped.y += DROP_HEIGHT_M * 4.0 * drop_t * (1.0 - drop_t)
		_visual.global_position = dropped
		_trail.global_position = dropped
		_visual.rotation.y += delta * 4.5
		if drop_t >= 1.0:
			_phase = 1
			_elapsed = 0.0
			_flight_start = _visual.global_position
			_trail.global_position = _flight_start
		return
	var flight_t := clampf(_elapsed / TRANSFER_DURATION_S, 0.0, 1.0)
	var flight := _flight_start.lerp(_flight_end, _ease_out_cubic(flight_t))
	flight.y += ARC_HEIGHT_M * 4.0 * flight_t * (1.0 - flight_t)
	_visual.global_position = flight
	_trail.global_position = flight
	_visual.rotation.y += delta * TAU * 2.5
	_visual.scale = Vector3.ONE * VISUAL_SCALE * lerpf(1.0, 0.08, flight_t)
	if flight_t >= 1.0:
		queue_free()

func _build_visual() -> void:
	_visual = ItemModelFactory3D.create_model(
		item_data,
		ItemModelFactory3D.get_item_color(item_data),
		ItemModelFactory3D.MODEL_ROLE_GROUND
	)
	if _visual == null:
		return
	_visual.name = "TransferredItemModel"
	_visual.scale = Vector3.ONE * VISUAL_SCALE
	_visual.set_meta("asset_id", str(_visual.get_meta("asset_id", "")))
	set_meta("item_asset_id", str(_visual.get_meta("asset_id", "")))
	add_child(_visual)

func _build_trail() -> void:
	_trail = TRAIL_SCENE.instantiate()
	_trail.name = "PrivateRentTransferTrail"
	add_child(_trail)
	_trail.call("set_tint", ItemModelFactory3D.get_item_color(item_data))

func _ease_out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - value, 3.0)

func get_visual_snapshot() -> Dictionary:
	return {
		"asset_id": TRANSFER_ASSET_ID,
		"item_asset_id": str(get_meta("item_asset_id", "")),
		"item_id": str(item_data.get("id", "")),
		"model_kind": ItemModelFactory3D.get_model_kind(item_data),
		"uses_shared_item_model_factory": true,
		"trail_asset_id": TRAIL_ASSET_ID,
		"is_pure_visual": true,
		"uses_ground_loot_transaction": false,
	}
