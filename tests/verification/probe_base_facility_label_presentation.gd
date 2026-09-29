extends Node

## 99F 基地设施头顶文字的呈现探针。
##
## 回答一个问题：设施进树跑完 `_ready()` 之后，头顶两个 Label3D 的真实状态。
##   - NameLabel（常驻名字牌）必须**不显示**，但快照文字仍要维护；
##   - PromptLabel（黄色交互提示）必须**放大到 34**并**比素材锚点抬高 0.6 米**，
##     且只在「玩家在范围内 + 被聚焦」时可见。
##
## 校验基线来自**不进树**的同场景实例（不跑 _ready，读到的就是素材原值）。
## 只读：不写存档、不改场景文件。

const REMAINING_ROOT := (
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/"
	+ "env_base99_remaining_facilities_root_top3d.tscn"
)
const WEAPON_WORKSHOP := (
	"res://assets/art/props/base_world_3d/runtime/weapon_workshop/"
	+ "prp_base_weapon_workshop_root_top3d.tscn"
)

const EXPECTED_FACILITY_COUNT := 8
const EXPECTED_PROMPT_FONT_SIZE := 34
const EXPECTED_HEIGHT_LIFT_M := 0.6


func _ready() -> void:
	var failures: Array[String] = []
	var authored: Dictionary = {}
	for path in [REMAINING_ROOT, WEAPON_WORKSHOP]:
		var baseline := (load(path) as PackedScene).instantiate()
		_collect_baseline(baseline, authored)
		baseline.free()

	var facilities: Array[BaseFacility3D] = []
	var remaining := (load(REMAINING_ROOT) as PackedScene).instantiate() as Node3D
	add_child(remaining)
	var workshop := (load(WEAPON_WORKSHOP) as PackedScene).instantiate() as BaseFacility3D
	add_child(workshop)
	await get_tree().process_frame

	for node in remaining.find_children("*", "Area3D", true, false):
		if node is BaseFacility3D:
			facilities.append(node as BaseFacility3D)
	facilities.append(workshop)

	if facilities.size() != EXPECTED_FACILITY_COUNT:
		failures.append(
			"expected %d facilities, got %d" % [EXPECTED_FACILITY_COUNT, facilities.size()]
		)

	for facility in facilities:
		_report(facility, authored, failures)

	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PROBE_FACILITY_LABEL_PRESENTATION_OK: %d facilities" % facilities.size())
	get_tree().quit(0 if failures.is_empty() else 1)


## 不进树实例化一遍：此时 _ready 没跑，读到的 Label3D 数值就是素材原值。
func _collect_baseline(node: Node, out: Dictionary) -> void:
	if node is BaseFacility3D:
		var name_label := node.get_node_or_null("NameLabel") as Label3D
		var prompt_label := node.get_node_or_null("PromptLabel") as Label3D
		if name_label != null and prompt_label != null:
			out[node.name] = {
				"prompt_y": prompt_label.position.y,
				"prompt_font": prompt_label.font_size,
				"name_y": name_label.position.y,
			}
	for child in node.get_children():
		_collect_baseline(child, out)


func _report(facility: BaseFacility3D, authored: Dictionary, failures: Array[String]) -> void:
	var name_label := facility.get_node_or_null("NameLabel") as Label3D
	var prompt_label := facility.get_node_or_null("PromptLabel") as Label3D
	if name_label == null or prompt_label == null:
		failures.append("%s: missing label node" % facility.name)
		return
	if not authored.has(facility.name):
		failures.append("%s: authored baseline not found" % facility.name)
		return
	var baseline: Dictionary = authored[facility.name]

	var expected_y := float(baseline["prompt_y"]) + EXPECTED_HEIGHT_LIFT_M
	if not is_equal_approx(prompt_label.position.y, expected_y):
		failures.append(
			"%s: prompt y %.4f != %.4f (authored %.4f + %.2f)"
			% [
				facility.name, prompt_label.position.y, expected_y,
				float(baseline["prompt_y"]), EXPECTED_HEIGHT_LIFT_M,
			]
		)
	if prompt_label.font_size != EXPECTED_PROMPT_FONT_SIZE:
		failures.append(
			"%s: prompt font_size %d != %d (authored %d)"
			% [
				facility.name, prompt_label.font_size, EXPECTED_PROMPT_FONT_SIZE,
				int(baseline["prompt_font"]),
			]
		)
	if prompt_label.visible:
		failures.append("%s: prompt label visible before player enters range" % facility.name)
	if name_label.visible:
		failures.append("%s: retired name label is still visible" % facility.name)
	if name_label.text.is_empty():
		failures.append("%s: name label snapshot contract lost (empty text)" % facility.name)
	# 提示牌必须真的抬到了退役名字牌之上（业主口径：位置更高）。
	if prompt_label.position.y <= float(baseline["name_y"]):
		failures.append(
			"%s: prompt y %.4f is not above retired name anchor %.4f"
			% [facility.name, prompt_label.position.y, float(baseline["name_y"])]
		)

	# 玩家进范围 + 聚焦后，黄色提示必须真的出现。
	facility.set("_player_in_range", true)
	facility.set_interaction_focus({}, true)
	var focused_visible := prompt_label.visible
	if not focused_visible:
		failures.append("%s: prompt label does not appear when focused" % facility.name)
	facility.set_interaction_focus({}, false)

	print(
		"PROBE\t%s\tid=%s\tname_visible=%s\tprompt_on_focus=%s\tfont=%d\ty=%.4f\tauthored_y=%.4f\tauthored_name_y=%.4f\tauthored_font=%d"
		% [
			facility.name, facility.facility_id, name_label.visible, focused_visible,
			prompt_label.font_size, prompt_label.position.y,
			float(baseline["prompt_y"]), float(baseline["name_y"]),
			int(baseline["prompt_font"]),
		]
	)
