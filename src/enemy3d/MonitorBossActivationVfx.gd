extends Node3D
## Deterministic, seekable visual tethers. Combat timing belongs to MonitorBossCombat.
var surfaces: Array[ImmediateMesh] = []
var materials: Array[StandardMaterial3D] = []
var flash: OmniLight3D
var snapshot: Dictionary = {}

func _ready() -> void:
	for color in [Color(0.025,0.045,0.055),Color(1.0,0.38,0.07),Color(1.0,0.87,0.44)]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color;material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.6
		if surfaces.size() > 0:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_enabled = true;material.emission = color;material.emission_energy_multiplier = 2.0
		var mesh := ImmediateMesh.new();surfaces.append(mesh);materials.append(material)
		var instance := MeshInstance3D.new();instance.mesh = mesh;instance.extra_cull_margin = 12.0;add_child(instance)
	flash = OmniLight3D.new();flash.light_color = Color(1.0,0.48,0.15);flash.omni_range = 5.0;add_child(flash)

func sync_activation(clip: String,time: float,presenter: MonitorBossPresentation) -> void:
	visible = clip == "activate"
	if not visible:return
	flash.light_energy = 0.0
	var frame := time*30.0
	var breaks := [65.0,98.0,102.0]
	var root := presenter.bone_point("rear_axle")
	var flash_count := 0
	for layer in range(3):
		var mesh := surfaces[layer];mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,materials[layer])
		tri(mesh,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		for wire in range(3):
			var side := float(wire-1)
			var start := root+Vector3(side*0.44,0.45+absf(side)*0.20,0.15)
			var anchor := Vector3(side*1.95,0.12,3.1+absf(side)*0.65)
			var cut := start.lerp(anchor,0.42)
			var age := (frame-float(breaks[wire]))/30.0
			if layer == 0 and frame < 139.0:
				var previous := start
				for step in range(1,33):
					var t := step/32.0
					var point := start.lerp(anchor,t)+Vector3(0,-sin(t*PI)*0.28,0)
					if age >= 0.0:
						var recoil := smoothstep(0.0,0.35,age)
						point += Vector3(side*0.4, sin(t*PI)*sin(age*12.0)*0.45, (1.0 if t>0.42 else -1.0)*0.55)*recoil
						point.y = lerpf(point.y,0.06,smoothstep(0.3,1.1,age))
					if not (age>=0.0 and step in [13,14,15,16]):tube(mesh,previous,point,0.045*(1.0-smoothstep(125.0,139.0,frame)))
					previous = point
			var spark_age := age
			if wire == 0 and frame < 65.0:spark_age = (frame-44.0)/30.0
			if layer > 0 and spark_age >= 0.0 and spark_age < 0.42:
				flash_count += 1
				flash.position = cut;flash.light_energy = maxf(flash.light_energy,4.0*(1.0-spark_age/0.42))
				for ray in range(15):
					var angle := ray*2.39996+wire*0.9
					var direction := Vector3(cos(angle),sin(angle)*0.7+0.35,sin(angle*1.7)*0.55).normalized()
					var distance := spark_age*(3.0+fmod(ray*1.7,2.0))
					var p := cut+direction*distance+Vector3.DOWN*spark_age*spark_age*2.0
					var width := (0.036 if layer == 2 else 0.065)*(1.0-spark_age/0.42)
					var tail := direction*(0.08+0.28*(1.0-spark_age/0.42))
					tube(mesh,p-tail,p,width)
				if spark_age < 2.0/30.0:
					for ray in range(8):
						var a := ray*TAU/8.0
						tri(mesh,cut,cut+Vector3(cos(a)*0.72,sin(a)*0.72,0),cut+Vector3(cos(a+0.22)*0.16,sin(a+0.22)*0.16,0))
		mesh.surface_end()
	snapshot = {"active":true,"spark_layers":flash_count,"tethers_visible":frame<139.0}

func tube(mesh: ImmediateMesh,a: Vector3,b: Vector3,radius: float) -> void:
	var axis := (b-a).normalized()
	var x := axis.cross(Vector3.UP).normalized()*radius
	if x.length_squared()<0.0000001:x = Vector3.RIGHT*radius
	var y := axis.cross(x).normalized()*radius
	for i in range(6):
		var u := x*cos(i*TAU/6.0)+y*sin(i*TAU/6.0)
		var v := x*cos((i+1)*TAU/6.0)+y*sin((i+1)*TAU/6.0)
		tri(mesh,a+u,b+u,b+v);tri(mesh,a+u,b+v,a+v)

func tri(mesh: ImmediateMesh,a: Vector3,b: Vector3,c: Vector3) -> void:
	mesh.surface_set_normal((b-a).cross(c-a).normalized())
	mesh.surface_add_vertex(a);mesh.surface_add_vertex(b);mesh.surface_add_vertex(c)
