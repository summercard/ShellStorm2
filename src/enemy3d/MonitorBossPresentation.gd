class_name MonitorBossPresentation
extends Node3D
## Baked Blender pose sampling, including spring stretch/constraints. No procedural limb poses.
const BASE := "res://assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/"
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

func get_presentation_snapshot() -> Dictionary:
	return {"asset_id":"ENM-BOSS-MONITOR002-3D","version":"v035","action_id":action_id,"time":sample_time,"expression":expression,"bone_count":skeleton.get_bone_count() if skeleton else 0,"clip_count":motion.get("clips",{}).size(),"procedural_pose":false,"electric_active":_context.get("electric_active",false),"death_duration":2.0}
