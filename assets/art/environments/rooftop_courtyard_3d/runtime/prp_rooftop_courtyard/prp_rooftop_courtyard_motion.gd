extends Node3D
# Presentation-only micromotion. No inventory, service, save or gameplay dependency.
var elapsed := 0.0
var _moving: Array[Node3D] = []
var _base: Array[Transform3D] = []
func _ready() -> void:
    for c in get_children():
        if c is Node3D and c.has_meta("motion_spec"):
            _moving.append(c)
            _base.append(c.transform)
    for node in find_children("*", "AnimationPlayer", true, false):
        var ap := node as AnimationPlayer
        for animation in ap.get_animation_list():
            if animation != "RESET":
                ap.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
                ap.play(animation)
                break
func _process(delta: float) -> void:
    elapsed += delta
    for i in _moving.size():
        var c := _moving[i]
        var spec := JSON.parse_string(str(c.get_meta("motion_spec"))) as Array
        c.transform = _base[i]
        for item in spec:
            var kind := str(item.get("type", ""))
            if kind == "rotation":
                var axis := int(item["axis"])
                var vector := Vector3.RIGHT if axis == 0 else (Vector3.BACK if axis == 1 else Vector3.UP)
                c.rotate_object_local(vector, elapsed * TAU * float(item["turns_per_10s"]) / 10.0)
            elif kind == "sway":
                var axis := int(item["axis"])
                var vector := Vector3.RIGHT if axis == 0 else (Vector3.BACK if axis == 1 else Vector3.UP)
                c.rotate_object_local(vector, float(item["amplitude_rad"]) * sin(elapsed * TAU * 24.0 / float(item["period_frames"])))
            elif kind == "tuning":
                c.position.x += float(item["amplitude_m"]) * sin(elapsed * TAU / 10.0)
            elif kind == "breathing_indicator":
                c.scale = Vector3.ONE * (1.0 + float(item["amplitude"]) * sin(elapsed * TAU / 5.0))
            elif kind == "water_ripple":
                var k := 1.0 + float(item["amplitude"]) * sin(elapsed * TAU / 5.0)
                c.scale = Vector3(k,1.0,k)
            elif kind == "tv_static":
                c.position.y += 0.004 * sin(floor(elapsed * 6.0) * 12.31)
    for light in find_children("*", "OmniLight3D", true, false):
        if light.has_meta("base_energy"):
            light.light_energy = float(light.get_meta("base_energy")) * (1.0 + 0.06 * sin(elapsed * 3.7) + 0.02 * sin(elapsed * 11.1))
