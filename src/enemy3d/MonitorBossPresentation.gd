class_name MonitorBossPresentation
extends Node3D
## Baked Blender pose sampling, including spring stretch/constraints. No procedural limb poses.
const BASE := "res://assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/"
## ── 动画受击体积（2026-10-14 业主：子弹要打在模型实体上）────────────────────────
## 显示器 Boss 的动画幅度极大：屏幕总成会前倾、向前下方扑砸、绕着自身轴连转三圈，
## 底座与三段弹簧支撑还会伸缩。**根节点上那个固定圆柱跟不上这些位移**，
## 而且它比可见模型宽得多（半径 2.016 m，屏幕半宽只有 0.85 m）—— 实测子弹会在
## 屏幕**前方 1.0–1.3 m** 处就被那个圆柱拦下，命中特效落在模型前面的空气里
## （业主报的「隔空击中、没有打在实体上」）。
##
## 所以这里补一组**跟着骨走的受击盒**：盒子尺寸是「骨局部空间的冻结值」，
## 位置/朝向逐帧由对应骨的世界姿态决定，骨怎么动盒子就怎么动。
##
## 只覆盖**有体积的实体块**：屏幕总成 / 后轴 / 底座 / 两只手 / 三段弹簧支撑。
## 数据线、弹簧臂细段与手指**刻意不覆盖** —— 把盒子套在只有十几厘米粗的线圈上，
## 只会得到比可视几何粗一大圈的假命中，「打在空气里」的手感反而更严重。
##
## 盒子怎么量的（两条硬规矩，都是踩出来的）：
## · **只用「刚性顶点」定盒子** —— 即单骨、权重恰为 1.0 的顶点。它们在该骨局部空间里
##   是常量，盒子因此精确贴合。若把「权重被混合（如 0.6/0.4）」的顶点也算进来，
##   它们在骨局部空间里会随手臂弯曲漂移，把盒子撑胖：实测 hand.L 的体积会胀到几何的
##   **9.5 倍**，玩家打手部时就会命中盒子的空腔。三段弹簧支撑是唯一例外 ——
##   它们的顶点本来就会沿骨轴伸缩，取全动画并集才是真实占位。
## · **每根轴外扩 3 cm**。盒子若恰好等于实测 AABB，表面顶点就落在边界上，
##   浮点舍入会把它们判到盒外（实测残余 1.85%）；外扩后归零，且 3 cm 在 2.7 m 高的屏幕上不可见。
##
## 对模型实体顶点（16,473 个样本）的覆盖率 **100%**（10 个探针姿态）。
## 骨姿态已实测**无剪切**（正交误差 0、轴长 1.0），故可安全写入物理形状。
## 数值来源与复算入口：`scripts/probe_monitor_boss_hit_volumes.gd`。
const HIT_VOLUMES := [
	{"bone": "monitor_spin", "center": Vector3(0.0026, 0.4445, 0.0), "size": Vector3(1.7309, 0.647, 2.7658)},
	{"bone": "rear_axle", "center": Vector3(0.0, -0.0099, -0.1522), "size": Vector3(1.9941, 0.4299, 0.6393)},
	{"bone": "pedestal_motion", "center": Vector3(0.0, 0.1575, 0.0744), "size": Vector3(1.8212, 0.335, 0.8812)},
	{"bone": "support_01", "center": Vector3(0.0, 0.3845, -0.0283), "size": Vector3(0.2231, 0.799, 0.2831)},
	{"bone": "support_02", "center": Vector3(0.0, 0.3554, -0.0489), "size": Vector3(0.2243, 0.718, 0.3609)},
	{"bone": "support_03", "center": Vector3(0.0, 0.3886, 0.0378), "size": Vector3(0.2244, 0.6542, 0.3225)},
	{"bone": "hand.L", "center": Vector3(0.0208, 0.1132, 0.0001), "size": Vector3(0.4486, 0.5164, 0.4123)},
	{"bone": "hand.R", "center": Vector3(-0.0206, 0.1144, 0.0001), "size": Vector3(0.4483, 0.5189, 0.4123)},
]
const FACE_SHADER := preload("res://src/enemy3d/monitor_expression.gdshader")
const CODE_SHADER := preload("res://src/enemy3d/monitor_code.gdshader")
const ACTIVATION_FX := preload("res://src/enemy3d/MonitorBossActivationVfx.gd")
const FX_SCRIPT := preload("res://src/enemy3d/MonitorBossVfx.gd")
static var motion: Dictionary = {}
static var face_boxes: Dictionary = {}
static var face_rest: Dictionary = {}
var animation_player: AnimationPlayer
var pose_frame := 0.0
var skeleton: Skeleton3D
var fx: Node3D
var action_id := "idle"
var sample_time := 0.0
var expression := 0
var hit_timer := 0.0
var code_phase := 0.0
var _bone_map: Array[int] = []
var _faces: Dictionary = {}
var _code: ShaderMaterial
var _context: Dictionary = {}
var _blended: Array[Transform3D] = []
var _blend_from: Array[Transform3D] = []
var _blend_time := 1.0
var _emerging_meshes: Array[MeshInstance3D] = []
var activation_fx: Node3D

func _ready() -> void:
	if motion.is_empty():motion = JSON.parse_string(FileAccess.get_file_as_string(BASE+"monitor_motion.json")) as Dictionary
	if face_boxes.is_empty():face_boxes = JSON.parse_string(FileAccess.get_file_as_string(BASE+"expression_regions.json")) as Dictionary
	if face_rest.is_empty():face_rest = JSON.parse_string(FileAccess.get_file_as_string(BASE+"face_rest_scale.json")) as Dictionary
	skeleton = find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	animation_player = AnimationPlayer.new();animation_player.name = "AnimationPlayer";add_child(animation_player)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	for clip_name in motion.clips:
		var clip: Dictionary = motion.clips[clip_name]
		var animation := Animation.new();animation.length = float(clip.duration)
		animation.loop_mode = Animation.LOOP_LINEAR if clip.loop else Animation.LOOP_NONE
		var track := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(track,NodePath(".:pose_frame"))
		animation.track_insert_key(track,0.0,0.0);animation.track_insert_key(track,animation.length,animation.length*30.0)
		library.add_animation(str(clip_name),animation)
	animation_player.add_animation_library("",library)
	for name in motion.bones:
		var index := skeleton.find_bone(str(name))
		if index < 0:index = skeleton.find_bone(str(name)+"_2")
		assert(index >= 0,"Missing authored bone: "+str(name))
		_bone_map.append(index)
	for node in find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		mesh.extra_cull_margin = 12.0
		var label := str(mesh.name)
		if label.begins_with("Continuous spring") or label.begins_with("Sculpted glove") or label.begins_with("White cuff") or label.begins_with("Behind monitor cable") or label.begins_with("Plug contact") or label in ["Long data cable whip","Cable strain relief","Connector alloy collar","Connector front inset","Data connector body","Luminous data plug"]:
			_emerging_meshes.append(mesh)
		if mesh.name.begins_with("Texture"):
			var slot := "large_eye" if "large_eye" in str(mesh.name) else "round_eye" if "round_eye" in str(mesh.name) else "mouth"
			var mat := ShaderMaterial.new();mat.shader = FACE_SHADER
			mat.set_shader_parameter("atlas",load(BASE+"expressions_atlas.png"))
			mat.set_shader_parameter("face_center",Vector2(mesh.get_aabb().get_center().x,mesh.get_aabb().get_center().y))
			mesh.material_override = mat
			_faces[slot] = {"mesh":mesh,"material":mat,"rest_scale":mesh.scale}
		elif str(mesh.name) == "Screen code texture":
			_code = ShaderMaterial.new();_code.shader = CODE_SHADER
			_code.set_shader_parameter("code_texture",load(BASE+"screen_code.png"));mesh.material_override = _code
	# Logical markers attach to the sampled authored bones, without moving the hands.
	for pair in [["KeyboardSocket","prop_socket.L"],["CableTipSocket","cable_16"],["ScreenSocket","monitor_tilt"]]:
		var attachment := BoneAttachment3D.new();attachment.bone_name = skeleton.get_bone_name(_bone_map[(motion.bones as Array).find(pair[1])]);skeleton.add_child(attachment)
		var marker := Marker3D.new();marker.name = pair[0];attachment.add_child(marker)
	fx = FX_SCRIPT.new();fx.name = "CyberEffects";add_child(fx)
	activation_fx = ACTIVATION_FX.new();activation_fx.name = "ActivationTethers";add_child(activation_fx)
	sync_context({"action_id":"idle","time":0.0})

func _process(delta: float) -> void:
	code_phase += delta/3.2
	hit_timer = maxf(0.0,hit_timer-delta)
	_blend_time = minf(1.0,_blend_time+delta/0.18)
	if _code and action_id != "activate":_code.set_shader_parameter("scroll_phase",code_phase)

func flash_hit() -> void:
	hit_timer = 10.0/30.0

func sync_context(context: Dictionary, blend := true) -> void:
	if skeleton == null:return
	_context = context
	var requested := str(context.get("action_id","idle"))
	assert(motion.clips.has(requested),"Unregistered monitor clip: "+requested)
	if requested != action_id:
		_blend_from = _blended.duplicate();_blend_time = 0.0
		action_id = requested
	var clip: Dictionary = motion.clips[action_id]
	sample_time = maxf(0.0,float(context.get("time",0.0)))
	if clip.loop:sample_time = fmod(sample_time,float(clip.duration))
	else:sample_time = minf(sample_time,float(clip.duration))
	if animation_player.current_animation != action_id:animation_player.play(action_id)
	animation_player.seek(sample_time,true);animation_player.advance(0.0)
	var pos := pose_frame
	var frame := mini(floori(pos),clip.frames.size()-1)
	var next := mini(frame+1,clip.frames.size()-1)
	var mix := pos-floorf(pos)
	expression = int(clip.frames[frame].expression)
	if hit_timer > 0.0 and not action_id.begins_with("stun") and action_id not in ["dead","activate"]:expression = 4
	# Turning clips contain a 90-degree authored visual turn; remove only that yaw.
	rotation.y = 0.0
	if action_id in ["turn_left","turn_right"]:
		var i := (motion.bones as Array).find("pedestal_motion")
		var rest := skeleton.get_bone_global_rest(_bone_map[i])
		var authored := interpolate_affine(matrix(clip.frames[frame].bones[i]),matrix(clip.frames[next].bones[i]),mix)*rest.affine_inverse()
		rotation.y = -authored.basis.get_euler().y
	_blended.clear()
	for i in range(_bone_map.size()):
		var pose := matrix(clip.frames[frame].bones[i])
		if mix > 0.00001:pose = interpolate_affine(pose,matrix(clip.frames[next].bones[i]),mix)
		# Transition blending only between locomotion clips; impacts remain frame exact.
		if blend and action_id in ["idle","move"] and _blend_from.size() == _bone_map.size() and _blend_time < 1.0:pose = interpolate_affine(_blend_from[i],pose,_blend_time)
		_blended.append(pose)
		skeleton.set_bone_global_pose_override(_bone_map[i],pose,1.0,true)
	skeleton.force_update_all_bone_transforms()
	# BoneAttachment3D receives deferred skeleton signals; synchronize props from the same sample now.
	for attachment in skeleton.get_children():
		if attachment is BoneAttachment3D:
			var index := (attachment as BoneAttachment3D).bone_idx
			if index >= 0:attachment.transform = skeleton.get_bone_global_pose(index)
	for slot in _faces:
		var face_start := 5.7 if slot == "large_eye" else 5.83 if slot == "round_eye" else 6.0
		_faces[slot].mesh.visible = action_id != "activate" or sample_time >= face_start
		var box: Array = face_boxes[slot][expression]
		var uv_rect := Vector4(float(box[0])/1536.0,float(box[1])/1024.0,float(box[2]-box[0])/1536.0,float(box[3]-box[1])/1024.0)
		_faces[slot].material.set_shader_parameter("region",uv_rect)
		var sizes: Array = clip.frames[frame].face_scale[slot]
		var next_sizes: Array = clip.frames[next].face_scale[slot]
		_faces[slot].material.set_shader_parameter("face_scale",Vector2(lerpf(float(sizes[0]),float(next_sizes[0]),mix)/float(face_rest[slot][0]),lerpf(float(sizes[1]),float(next_sizes[1]),mix)/float(face_rest[slot][1])))
		if action_id == "activate":
			var pop := clampf((sample_time-face_start)/0.20,0.0,1.0)
			var size := lerpf(0.20,1.0,pop) + sin(pop*PI)*0.35
			_faces[slot].material.set_shader_parameter("face_scale",Vector2(size,size))
	for mesh in _emerging_meshes:mesh.visible = action_id != "activate" or sample_time >= (3.73 if str(mesh.name).ends_with("L") else 3.9)
	if _code:
		_code.set_shader_parameter("boot_reveal",clampf(floorf((sample_time-0.60)*30.0)/27.0,0.0,1.0) if action_id == "activate" else 1.0)
		if action_id == "activate":_code.set_shader_parameter("scroll_phase",maxf(0.0,sample_time-0.6)*0.32)
	activation_fx.sync_activation(action_id,sample_time,self)
	fx.sync_effects(context,self)

static func matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))

static func interpolate_affine(a: Transform3D,b: Transform3D,weight: float) -> Transform3D:
	# Keep the stretch/shear residual; ordinary TRS interpolation discards it between samples.
	if weight <= 0.0:return a
	if weight >= 1.0:return b
	var ar := a.basis.orthonormalized();var br := b.basis.orthonormalized()
	var astretch := ar.transposed()*a.basis;var bstretch := br.transposed()*b.basis
	var stretch := Basis(astretch.x.lerp(bstretch.x,weight),astretch.y.lerp(bstretch.y,weight),astretch.z.lerp(bstretch.z,weight))
	var rotation := Basis(ar.get_rotation_quaternion().slerp(br.get_rotation_quaternion(),weight))
	return Transform3D(rotation*stretch,a.origin.lerp(b.origin,weight))

func bone_point(name: String) -> Vector3:
	return skeleton.get_bone_global_pose(_bone_map[(motion.bones as Array).find(name)]).origin


## 受击盒规格（骨名 / 骨局部中心 / 骨局部尺寸）。表现层只提供几何事实，
## 由 `Enemy3D` 建物理形状并逐帧跟位 —— 碰撞始终归玩法层所有。
static func get_hit_volume_spec() -> Array:
	return HIT_VOLUMES


## 受击盒的**世界空间**形状变换，与 `HIT_VOLUMES` 一一对应（含骨姿态里的伸缩）。
## 只在 `sync_context` 之后调用才反映当帧姿态。
func hit_volume_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if skeleton == null:
		return out
	for spec in HIT_VOLUMES:
		var index := hit_volume_bone_index(str(spec["bone"]))
		assert(index >= 0, "Missing authored hit volume bone: " + str(spec["bone"]))
		if index < 0:
			out.append(Transform3D())
			continue
		out.append(skeleton.global_transform * skeleton.get_bone_global_pose(index) * Transform3D(Basis(), spec["center"] as Vector3))
	return out


## 骨名（用美术母版里的**原始**名字，不含 Godot 去重产生的 `_2` 后缀）⇒ 骨架骨索引。
func hit_volume_bone_index(bone_name: String) -> int:
	var authored := (motion.bones as Array).find(bone_name)
	if authored < 0 or authored >= _bone_map.size():
		return -1
	return _bone_map[authored]

func get_presentation_snapshot() -> Dictionary:
	return {"asset_id":"ENM-BOSS-MONITOR002-3D","version":"v035","action_id":action_id,"time":sample_time,"expression":expression,"bone_count":skeleton.get_bone_count() if skeleton else 0,"clip_count":motion.get("clips",{}).size(),"procedural_pose":false,"electric_active":_context.get("electric_active",false),"death_duration":2.0}
