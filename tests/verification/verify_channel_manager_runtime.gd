extends SceneTree
const PREFAB = preload("res://assets/art/characters/npc/channel_manager/runtime/channel_manager_runtime.tscn")
var errors: Array[String] = []
var checks := 0
var npc: Node3D
var released := 0
var finished := 0
var locked: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		errors.append(why)
		printerr(why)

func frame(seconds: float) -> void:
	var remaining := seconds
	while remaining >= 0.0001:
		var delta := minf(1.0 / 60.0, remaining)
		var anim := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim != null:
			anim.advance(delta)
		npc.step_presentation(delta)
		remaining -= delta

func snap() -> Dictionary:
	return npc.get_snapshot()

func _run() -> void:
	npc = PREFAB.instantiate()
	npc.rng_seed = 7654
	root.add_child(npc)
	npc.set_process(false)
	check(snap().ready, "formal model, mount resource, and animation names/lengths")
	if not snap().ready:
		quit(1)
		return
	var base := npc.find_child("BaseFixed", true, false) as Node3D
	check(base != null, "base mesh imported")
	if base == null:
		quit(1)
		return
	var base_transform := base.global_transform
	var root_transform := npc.global_transform
	check(snap().bone_count == 20 and snap().displays.size() == 13, "20 bones / 13 screens")
	check(snap().state == "sleep" and snap().displays.all(func(d): return d.mode == 1 and d.snow == 1.0), "no glyphs in sleep")
	check(not npc.begin_talk("happy") and not npc.trigger_skill("识别"), "sleep rejects actions")
	var observer := Node3D.new()
	root.add_child(observer)
	observer.position = Vector3(0, 1.2, 7.0)
	npc.set_observer(observer)
	frame(0.1)
	check(snap().state == "sleep", "far observer does not wake")
	observer.position.z = 4.5
	frame(0.36)
	check(snap().state == "activate" and snap().displays[0].mode == 2 and snap().displays[0].snow < 0.4 and snap().displays[1].snow > 0.9, "main eye lights up before other screens")
	frame(2.28)
	frame(0.4)
	check(snap().state == "active_idle" and snap().displays[0].eye_aim and not snap().displays[8].eye_aim, "45 degrees filters facing and rear displays")
	observer.position = Vector3(-1.3, 4.8, 4.5)
	frame(0.4)
	var gaze_left: float = snap().displays[0].gaze.x
	observer.position.x = 1.7
	frame(0.5)
	var gaze_right: float = snap().displays[0].gaze.x
	check(gaze_left < -0.04 and gaze_right > 0.04 and snap().displays[0].eye_aim, "pupil follows across screen: %s -> %s" % [gaze_left, gaze_right])
	npc.set_observer(null)
	frame(0.4)
	var changed := false
	var saw_snow := false
	var last_slot: int = snap().displays[0].slot
	for i in range(300):
		frame(1.0 / 60.0)
		var d: Dictionary = snap().displays[0]
		if d.snow > 0.6:
			saw_snow = true
		if d.slot != last_slot:
			changed = true
			check(d.snow > 0.65 and saw_snow, "switch mid-snow")
			break
	check(changed, "background channel eventually changes")
	var expected := {"normal": 6, "happy": 7, "angry": 8, "scheme": 9}
	for emotion: String in expected:
		check(npc.begin_talk(emotion, 0.45), "start speech " + emotion)
		frame(0.2)
		check(snap().state == "talk_" + emotion and snap().displays[0].mode == expected[emotion], "animation and type style " + emotion)
		frame(0.3)
		check(snap().state == "active_idle", "speech returns to active_idle")
	check(not npc.trigger_skill("无效"), "reject unknown card")
	npc.release_started.connect(func(): released += 1)
	npc.release_finished.connect(func(): finished += 1)
	npc.skill_result_locked.connect(func(card: String): locked.append(card))
	var cards := {"识别": [6, Color("#f4f5ff")], "监听": [9, Color("#a572ed")], "中继": [10, Color("#468be2")]}
	for card: String in cards:
		check(npc.trigger_skill(card) and not npc.trigger_skill(card), "per-invocation result and no reentrancy")
		frame(0.21)
		check(snap().displays.all(func(d): return d.mode == 3) and not snap().beam_visible, "all screens warn together")
		frame(0.5)
		check(snap().displays.all(func(d): return d.mode == 4) and snap().displays[0].slot != snap().displays[1].slot, "reels move independently")
		frame(0.75)
		check(snap().state == "skill_lock" and snap().result == card, "state locks result " + card)
		var wanted: Array = cards[card]
		check(snap().displays.all(func(d): return d.mode == 5 and d.slot == wanted[0] and d.card_color == wanted[1]), "all screens use precise lock glyph and color")
		frame(0.7)
		check(snap().state == "skill_release" and not snap().beam_visible, "main screen leans before beam")
		frame(0.2)
		check(snap().beam_visible, "beam only in release window")
		frame(0.8)
		check(snap().state == "active_idle" and not snap().beam_visible and snap().result == "", "beam cleaned and active restored")
	check(released == 3 and finished == 3 and locked == cards.keys(), "single cue, completion and lock for all results")
	check(npc.begin_talk("scheme"), "talk before cancel test")
	check(npc.trigger_skill("中继") and npc.cancel_skill(), "skill preempts talk and can cancel before release")
	frame(0.3)
	check(snap().state == "active_idle" and not snap().beam_visible and finished == 3, "cancel has no beam or finish")
	check(base.global_transform.is_equal_approx(base_transform) and npc.global_transform.is_equal_approx(root_transform), "anchor and root never moved")
	print("CHANNEL_MANAGER_TESTS ", checks, " checks; ", errors.size(), " failures")
	quit(0 if errors.is_empty() else 1)
