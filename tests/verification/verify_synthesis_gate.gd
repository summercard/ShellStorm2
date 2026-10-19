extends Node
## verify_synthesis_gate — 合成表现层（兔子闸门）专项验收。
##
## 设计口径：业主 2026-10-19「点击合成后 一个带有兔子 logo 的闸门关下，遮住中间的界面，
## 这个闸门就在中间界面范围里，然后兔子眼睛发红，过了约 3 秒 闸门打开，
## 里头的东西被替换成合成的东西」。
##
## 这里验的是**能用判据量的部分**：几何范围、时间轴、状态推进、台上内容。
## 「看起来像不像一道带兔子的闸门」只能靠真渲染截图，本场景不代签那个结论。
##
## 时间用**手动驱动** `_process`，不真等 3.6 秒：
## 动画的全部时间来源是 `_time`，所以 `set_process(false)` 之后逐帧调
## `_process(dt)` 就能把整条时间轴压进几十毫秒，且完全确定性。

const PANEL := preload("res://src/ui/WorkbenchPanel.gd")
const VEIL := preload("res://src/ui/SynthesisGateVeil.gd")
const INVENTORY := preload("res://src/game/InventoryModule.gd")
const FORGE := preload("res://src/weapons/WeaponForge.gd")

## 驱动步长。事件的判定点都取在段中，不贴边界 —— 浮点累加不会因为 0.05 的粒度翻面。
const STEP := 0.05

var _failures: Array[String] = []


class _StubRef:
	extends Node
	var inventory: InventoryModule = null
	func get_inventory_module() -> InventoryModule:
		return inventory


func _ready() -> void:
	var stub := _StubRef.new()
	stub.inventory = INVENTORY.new(40)
	add_child(stub)
	GameManager.currency = 2000

	var panel = PANEL.new()
	panel.set_workbench_ref(stub)
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var veil := panel.find_child("SynthesisGateVeil", true, false) as SynthesisGateVeil
	_expect(veil != null, "改造台必须挂上兔子闸门（SynthesisGateVeil）")
	if veil == null:
		_panic(panel, stub)
		return

	# ——— ① 几何：闸门必须**只在中间那一栏**里 ———
	var tray_column := panel.get("_body_tray_column") as Control
	var bag_column := panel.get("_body_bag_column") as Control
	var body := tray_column.get_parent() as Control if tray_column != null else null
	_expect(tray_column != null and bag_column != null, "炼炉栏与背包栏必须存在")
	if tray_column != null:
		_expect(
			veil.position.is_equal_approx(tray_column.position)
			and veil.size.is_equal_approx(tray_column.size),
			"闸门矩形必须与炼炉栏逐像素重合（业主：闸门就在中间界面范围里），实际 %s/%s vs %s/%s"
			% [str(veil.position), str(veil.size), str(tray_column.position), str(tray_column.size)]
		)
		_expect(veil.size.x > 0.0 and veil.size.y > 0.0, "闸门必须有非零尺寸，否则等于不存在")
	if bag_column != null:
		var veil_rect := Rect2(veil.position, veil.size)
		var bag_rect := Rect2(bag_column.position, bag_column.size)
		_expect(
			not veil_rect.intersects(bag_rect),
			"闸门不得盖到背包（两矩形相交：%s × %s）" % [str(veil_rect), str(bag_rect)]
		)
	if body != null:
		var body_rect := Rect2(Vector2.ZERO, body.size)
		var gate_rect := Rect2(veil.position, veil.size)
		_expect(
			body_rect.encloses(gate_rect),
			"闸门必须完整落在主体区里（不得探到页头/页脚），实际 %s ⊄ %s" % [str(gate_rect), str(body_rect)]
		)
	# 棋盘把物品画布提到 z_index=4，闸门低于它就会被枪械图标穿透。
	_expect(int(veil.z_index) > 4, "闸门层级必须高于棋盘物品（z_index=%d）" % int(veil.z_index))

	# ——— ② 初始态：不播、不可见 ———
	var initial := veil.get_snapshot()
	_expect(not bool(initial["playing"]), "未熔炼时不得播放闸门")
	_expect(not bool(initial["visible"]), "未熔炼时闸门必须不可见")

	# ——— ③ 时间轴：闭合 → 眼睛 → 开闸 → 结束 ———
	var outputs := [_item("weapon_pistol"), _item("weapon_shotgun")]
	var finished_count := {"n": 0}
	veil.finished.connect(func(): finished_count["n"] = int(finished_count["n"]) + 1)
	veil.set_process(false)
	veil.play(outputs)

	var at_start := veil.get_snapshot()
	_expect(str(at_start["phase"]) == "closing", "play 之后必须立刻进入关闸段")
	_expect(float(at_start["progress"]) <= 0.01, "关闸起步时闭合度必须还是 0")

	_advance(veil, 0.30)
	var mid := veil.get_snapshot()
	_expect(
		str(mid["phase"]) == "closing" and float(mid["progress"]) > 0.2 and float(mid["progress"]) < 0.95,
		"0.30s 时闸门应该正在下降（count=%s / progress=%.2f）" % [str(mid["phase"]), float(mid["progress"])]
	)
	_expect(float(mid["eyes"]) <= 0.01, "闸门没落到底之前眼睛不得发红")

	_advance(veil, 0.35)
	var shut := veil.get_snapshot()
	_expect(str(shut["phase"]) == "hold", "0.65s 时闸门必须已经落到底")
	_expect(is_equal_approx(float(shut["progress"]), 1.0), "闸门落底时闭合度必须是 1（完全盖住中间）")

	_advance(veil, 0.35)
	var lit := veil.get_snapshot()
	_expect(
		is_equal_approx(float(lit["eyes"]), 1.0),
		"落底后约 0.35s 兔子眼睛必须全红，实际 %.2f" % float(lit["eyes"])
	)

	# 台上（闸门后面）必须是刚合成的那些东西。
	var plates: Array = lit["plates"]
	_expect(plates.size() == outputs.size(), "台上必须摆出全部产物（%d），实际 %d" % [outputs.size(), plates.size()])
	for index in range(mini(plates.size(), outputs.size())):
		_expect(
			str(plates[index]) == str((outputs[index] as Dictionary).get("name", "")),
			"台上第 %d 件必须是产物「%s」，实际「%s」" % [
				index + 1, str((outputs[index] as Dictionary).get("name", "")), str(plates[index]),
			]
		)

	# 「约 3 秒后开闸」：闭合 + 保持 = 3.00s。
	var open_at := float(VEIL.CLOSE_SECONDS) + float(VEIL.HOLD_SECONDS)
	_expect(
		is_equal_approx(open_at, 3.0),
		"闸门必须在 3.0s 处开始上升（业主说约 3 秒），实际 %.2f" % open_at
	)

	# 把时间推到 3.25s：闸门已经上升了一小段。
	# 上面已经手动推进了 0.30 + 0.35 + 0.35 = 1.00s。
	var elapsed := 0.30 + 0.35 + 0.35
	_advance(veil, maxf(0.0, open_at + 0.25 - elapsed))
	var opening := veil.get_snapshot()
	_expect(str(opening["phase"]) == "opening", "3.25s 时闸门必须开始上升，实际 '%s'" % str(opening["phase"]))
	_expect(
		float(opening["progress"]) < 0.99,
		"开闸后闭合度必须开始下降，实际 %.2f" % float(opening["progress"])
	)

	# 升到底之后要**停留**：产物得有时间被看清，不能升起就收摊。
	var open_done := open_at + float(VEIL.OPEN_SECONDS)
	_advance(veil, maxf(0.0, open_done + 0.10 - (open_at + 0.25)))
	var linger := veil.get_snapshot()
	_expect(
		str(linger["phase"]) == "linger",
		"闸门升到底后必须进入停留段让玩家看清产物，实际 '%s'" % str(linger["phase"])
	)
	_expect(
		bool(linger["visible"]) and float(linger["progress"]) <= 0.01,
		"停留段：闸门必须已收起、但整个控件仍可见（台面还在）"
	)
	_expect(
		(linger["plates"] as Array).size() == outputs.size(),
		"停留段台上仍必须摆着产物"
	)
	_expect(
		float(VEIL.LINGER_SECONDS) >= 1.0,
		"停留段至少 1 秒，否则玩家来不及看清换来的是哪把枪（实际 %.2f）" % float(VEIL.LINGER_SECONDS)
	)

	_advance(veil, float(VEIL.LINGER_SECONDS))
	var done := veil.get_snapshot()
	_expect(str(done["phase"]) == "idle", "整段动画结束必须回到 idle，实际 '%s'" % str(done["phase"]))
	_expect(float(done["progress"]) <= 0.01, "结束后闸门必须完全收起")
	_expect(not bool(done["visible"]), "结束后必须隐藏（否则盘面永远被盖着）")
	_expect(int(finished_count["n"]) == 1, "`finished` 必须恰好发一次，实际 %d" % int(finished_count["n"]))

	# ——— ④ 保持段点击可提前开闸；关闸段不给跳 ———
	veil.play(outputs)
	_advance(veil, 0.20)
	veil._gui_input(_click())
	_expect(
		str(veil.get_snapshot()["phase"]) == "closing",
		"关闸段点击不得跳过 —— 那一瞬间画面还没被盖住，跳过会露出揭底的半帧"
	)
	_advance(veil, 0.60)
	veil._gui_input(_click())
	_expect(
		str(veil.get_snapshot()["phase"]) == "opening",
		"保持段点击必须立刻进入开闸段"
	)

	# ——— ⑤ abort：立刻收起，且不当成"播完了" ———
	var finished_before := int(finished_count["n"])
	veil.play(outputs)
	_advance(veil, 0.40)
	veil.abort()
	var aborted := veil.get_snapshot()
	_expect(not bool(aborted["playing"]), "abort 之后不得仍在播放")
	_expect(not bool(aborted["visible"]), "abort 之后闸门必须隐藏")
	_expect(
		int(finished_count["n"]) == finished_before,
		"abort 不得发 `finished` —— 它表示'播完了'，不是'收掉了'"
	)

	# ——— ⑥ 端到端：真的熔炼一次，闸门必须自己起来，台上是那把枪 ———
	veil.abort()
	var panel_veil := panel.find_child("SynthesisGateVeil", true, false) as SynthesisGateVeil
	panel.call("_tray_append", _item("bp_pistol"), 2, 0, 0)
	panel.call("_tray_append", _item("mod_bullet_standard"), 4, 2, 0)
	var plan := FORGE.classify(panel.call("_tray_probe_items"))
	_expect(
		str(plan["recipe"]) == FORGE.RECIPE_DIRECTED,
		"端到端：盘面必须判为 R0 定向合成，实际 '%s'" % str(plan["recipe"])
	)
	panel.call("_execute_forge", plan)
	await get_tree().process_frame
	_expect(
		bool(panel_veil.get_snapshot()["playing"]),
		"端到端：熔炼成功后闸门必须自己开始播放"
	)
	_expect(
		bool(panel.get("_busy")),
		"端到端：闸门播放期间必须保持 busy（否则玩家能对着空盘面再点一次）"
	)
	# 防剧透：闸门关着时背包里那把枪**已经真的进包了**，必须被封条挡住，
	# 否则玩家在门旁边就能看到答案，3 秒等待变成空转。
	var bag_seal := panel.get("_bag_seal") as Control
	_expect(bag_seal != null, "改造台必须有背包封条（防剧透）")
	if bag_seal != null:
		_expect(bool(bag_seal.visible), "闸门播放期间背包封条必须可见 —— 否则产物提前剧透")
		_expect(
			bag_seal.z_index >= int(veil.z_index),
			"封条层级不得低于闸门（否则会被棋盘物品穿透）"
		)
	# 状态栏也不能写出结果 —— 那句话本身就是剧透。
	_expect(
		not str((panel.get("_status") as Label).text).contains("熔炼完成"),
		"闸门播放期间状态栏不得提前写出「熔炼完成」，实际「%s」"
		% str((panel.get("_status") as Label).text)
	)
	var produced := _latest_weapon(stub.inventory)
	_expect(not produced.is_empty(), "端到端：背包必须产出一把枪")
	var plates_after: Array = panel_veil.get_snapshot()["plates"]
	_expect(
		plates_after.size() == 1,
		"端到端：台上必须只摆这一件产物，实际 %d 件" % plates_after.size()
	)
	if plates_after.size() == 1 and not produced.is_empty():
		_expect(
			str(plates_after[0]) == str(produced.get("name", "")),
			"端到端：台上显示的东西必须就是背包里那把枪（「%s」vs「%s」）" % [
				str(plates_after[0]), str(produced.get("name", "")),
			]
		)
	# 播完自动放开 busy。注意顺序：`play` 内部会 `set_process(true)`，
	# 必须先 play 再关掉引擎推进，否则手动推进与引擎滴答会叠加，时间轴翻倍。
	panel_veil.play([_item("weapon_pistol")])
	panel_veil.set_process(false)
	_advance(panel_veil, 0.7 + 2.4 + 0.7 + float(VEIL.LINGER_SECONDS))
	await get_tree().process_frame
	_expect(not bool(panel.get("_busy")), "闸门播完后必须放开 busy，否则熔炼按钮从此点不动")
	if bag_seal != null:
		_expect(not bool(bag_seal.visible), "闸门播完后背包封条必须撤掉")
	_expect(
		str((panel.get("_status") as Label).text).contains("熔炼完成"),
		"揭晓之后状态栏必须写出结果，实际「%s」" % str((panel.get("_status") as Label).text)
	)

	_panic(panel, stub)


func _panic(panel: Node, stub: Node) -> void:
	GameManager.currency = 0
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	if stub != null and is_instance_valid(stub):
		stub.queue_free()
	if _failures.is_empty():
		print(
			"SYNTHESIS_GATE_OK: 闸门只覆盖中间炼炉栏 / 关闸0.60s→落底 → 眼睛全红 → 3.00s 处上升 → 3.60s 升到底 → 停留 1.40s 展示产物；"
			+ "保持段与停留段可点掉、关闸段不可跳；abort 不冒充播完；播放期背包与状态栏都不剧透；熔炼后台面换成刚产出的那把枪"
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _advance(veil: Node, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0001:
		var step := minf(STEP, remaining)
		veil.call("_process", step)
		remaining -= step


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


## 背包里最后一把武器。用来确认"台上显示的就是背包里那把"，而不是只看字数对不对。
func _latest_weapon(inventory: InventoryModule) -> Dictionary:
	var found: Dictionary = {}
	for entry in inventory.get_occupied_slots():
		var item: Dictionary = entry.get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			found = item
	return found


func _item(item_id: String, count: int = 1) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id).duplicate(true)
	if item.is_empty():
		_expect(false, "物品缺失：%s" % item_id)
		return {}
	item["count"] = count
	return item


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
