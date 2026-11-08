class_name EliteRentTransferTrail3D
extends Node3D
## 收租转移专用拖尾。它是转移实体的私有长命子节点，不进入 VfxPool3D。
## AssetID 是稳定内容身份，供验收、日志和后续美术替换使用。

const TRAIL_ASSET_ID := "VFX-ELITE-RENT-TRANSFER-TRAIL-3D"
const SEGMENT_COUNT := 8
const TRAIL_LENGTH_M := 0.72

var _points: Array[Vector3] = []
var _segments: Array[MeshInstance3D] = []
var _segment_mesh: SphereMesh

func _ready() -> void:
	set_meta("asset_id", TRAIL_ASSET_ID)
	set_meta("runtime_save_excluded", true)
	_segment_mesh = SphereMesh.new()
	_segment_mesh.radius = 0.055
	_segment_mesh.height = 0.11
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.72, 0.18, 0.92)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.34, 0.05)
	material.emission_energy_multiplier = 2.8
	_segment_mesh.material = material
	for index in range(SEGMENT_COUNT):
		var segment := MeshInstance3D.new()
		segment.name = "RentTrailSegment%02d" % index
		segment.mesh = _segment_mesh
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(segment)
		_segments.append(segment)
	_points.resize(SEGMENT_COUNT)
	for index in range(_points.size()):
		_points[index] = global_position

func set_tint(tint: Color) -> void:
	if _segment_mesh == null or _segment_mesh.material == null:
		return
	var material := _segment_mesh.material as StandardMaterial3D
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.92)
	material.emission = tint

func _process(_delta: float) -> void:
	if _points.is_empty():
		return
	_points[0] = global_position
	for index in range(1, _points.size()):
		_points[index] = _points[index - 1].lerp(_points[index], 0.68)
	for index in range(_segments.size()):
		var segment := _segments[index]
		segment.global_position = _points[index]
		var fade := 1.0 - float(index) / float(maxi(1, _segments.size()))
		segment.scale = Vector3.ONE * lerpf(0.34, 0.95, fade)
		segment.transparency = 1.0 - fade * 0.82

func get_asset_id() -> String:
	return TRAIL_ASSET_ID
