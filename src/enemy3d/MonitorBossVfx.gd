extends Node3D
## Smooth filled cyber ribbons, segmented shock waves and a one-frame yellow silhouette.
const BLUE := Color(0.10,0.48,0.66,0.82)
const ICE := Color(0.62,0.88,0.96,0.92)
const PINK := Color(0.66,0.22,0.44,0.78)
const GOLD := Color(1.0,0.86,0.23,1.0)
var surfaces: Array[ImmediateMesh] = []
var materials: Array[StandardMaterial3D] = []
var effect_snapshot: Dictionary = {}

func _ready() -> void:
	for color in [BLUE,ICE,PINK,GOLD]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		material.emission_enabled = true;material.emission = color;material.emission_energy_multiplier = 0.35
		var mesh := ImmediateMesh.new();surfaces.append(mesh);materials.append(material)
		var instance := MeshInstance3D.new();instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 20.0;add_child(instance)

func sync_effects(context: Dictionary, presenter: MonitorBossPresentation) -> void:
	if surfaces.is_empty():return
	var clip := str(context.get("action_id","idle"))
	var time := float(context.get("time",0.0))
	var active := bool(context.get("electric_active",false))
	var impact := 64.0/30.0 if clip == "heavy_spin_slam" else 32.0/30.0
	var center := Vector3(0,0.035,-1.4) if clip == "heavy_spin_slam" else Vector3(0,0.035,-3.2)
	if str(context.get("skill_id","")) in ["monitor_keyboard","monitor_spin_slam"]:
		center = to_local(context.contact_point);center.y = 0.035
	var hit := clip in ["heavy_spin_slam","melee_keyboard"] and time >= impact and time < impact+0.45
	var flash := (hit and time-impact < 1.0/30.0) or (clip == "stun_enter" and time >= 3.0/30.0 and time < 4.0/30.0)
	effect_snapshot = {"electric_active":active,"yellow_flash":flash,"spin":clip == "heavy_spin_slam" and time >= 0.6 and time < 1.65,"impact":hit}
	for color in range(4):
		var mesh := surfaces[color];mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,materials[color])
		triangle(mesh,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		if float(context.get("telegraph_radius",0.0)) > 0.0 and color == 0:
			var point: Vector3 = context.get("contact_point",global_position)
			var local := to_local(point);local.y = 0.045
			var radius := float(context.telegraph_radius)/global_basis.get_scale().x
			var cone := str(context.get("skill_id","")) == "monitor_cable"
			var start := -PI/2.0-deg_to_rad(80.0) if cone else 0.0
			var span := deg_to_rad(160.0) if cone else TAU
			for sector in range(12):arc(mesh,local,radius,radius+0.055,start+sector*span/12.0,start+sector*span/12.0+span/12.0*0.7,false)
		if clip == "heavy_spin_slam" and time >= 0.6 and time < 1.65 and color < 3:
			var axle := presenter.bone_point("monitor_tilt")
			for sector in range(3):
				var angle := time*19.0 + sector*TAU/3.0 + color*0.17
				arc(mesh,axle,1.75+color*0.10,1.91+color*0.10,angle,angle+1.28,true)
		if clip == "melee_cable" and time >= 0.79 and time <= 1.15 and color < 3:
			arc(mesh,Vector3(0,0.32,0),4.6+color*0.16,4.93+color*0.16,-2.95+(time-0.8)*3.0,-0.20+(time-0.8)*3.0,false)
		if hit and color < 3:
			var age := time-impact
			var radius := 1.6 + age*(9.0 if clip == "heavy_spin_slam" else 5.0) - color*0.32
			for sector in range(9):
				var angle := sector*TAU/9.0+color*0.2
				arc(mesh,center,maxf(0.3,radius),maxf(0.4,radius+0.20*(1.0-age/0.45)),angle,angle+0.52,false)
			for shard in range(10):
				var a := shard*2.39996+color*0.3
				var point := center+Vector3(cos(a)*radius,0.3+sin(age*PI/0.45)*1.1,sin(a)*radius)
				quad(mesh,point,Vector3(0.13,0.0,0.07),Vector3(0.0,0.32,0.0))
		if flash and color == 3:
			var point := center if hit else Vector3(0,0.08,0)
			var radius := 4.2 if clip == "heavy_spin_slam" else 2.8
			for sector in range(24):
				var a := sector*TAU/24.0;var b := (sector+1)*TAU/24.0
				var r1 := radius if sector%2 == 0 else radius*0.53
				var r2 := radius if (sector+1)%2 == 0 else radius*0.53
				triangle(mesh,point,point+Vector3(cos(a)*r1,0,sin(a)*r1),point+Vector3(cos(b)*r2,0,sin(b)*r2))
		if active and color < 3:
			for segment in range(1,16):
				var a := presenter.bone_point("cable_%02d"%segment)
				var b := presenter.bone_point("cable_%02d"%(segment+1))
				var path := PackedVector3Array()
				for step in range(7):
					var u := step/6.0;var offset := Vector3(cos(u*TAU*1.5+time*22+segment),sin(u*TAU*1.5+time*22+segment),0)*0.065
					path.append(a.lerp(b,u)+offset)
				for step in range(6):ribbon(mesh,path[step],path[step+1],0.028)
			var point: Vector3 = context.get("contact_point",global_position)
			var p := to_local(point);p.y = 0.045
			var radius := fmod(time+color*0.25,0.8)*8.5
			for sector in range(9):arc(mesh,p,radius,radius+0.13,sector*TAU/9.0,sector*TAU/9.0+0.5,false)
		if clip.begins_with("stun") and (color == 3 or color == 2):
			var head := presenter.bone_point("monitor_tilt")+Vector3(0,0.72,0)
			for star in range(5):
				if star%2 != color%2:continue
				var a := time*2.0+star*TAU/5.0
				var point := head+Vector3(cos(a)*0.95,sin(a*2.0)*0.1,sin(a)*0.55)
				for tip in range(10):
					var r1 := 0.17 if tip%2 == 0 else 0.075;var r2 := 0.17 if (tip+1)%2 == 0 else 0.075
					triangle(mesh,point,point+Vector3(cos(tip*TAU/10)*r1,sin(tip*TAU/10)*r1,0),point+Vector3(cos((tip+1)*TAU/10)*r2,sin((tip+1)*TAU/10)*r2,0))
		mesh.surface_end()

func arc(mesh: ImmediateMesh,center: Vector3,inner: float,outer: float,start: float,end: float,vertical: bool) -> void:
	for i in range(28):
		var a := lerpf(start,end,i/28.0);var b := lerpf(start,end,(i+1)/28.0)
		var av := Vector3(cos(a),sin(a) if vertical else 0.0,0.0 if vertical else sin(a))
		var bv := Vector3(cos(b),sin(b) if vertical else 0.0,0.0 if vertical else sin(b))
		triangle(mesh,center+av*inner,center+av*outer,center+bv*outer)
		triangle(mesh,center+av*inner,center+bv*outer,center+bv*inner)

func ribbon(mesh: ImmediateMesh,a: Vector3,b: Vector3,width: float) -> void:
	var normal := (b-a).cross(Vector3.FORWARD).normalized()*width
	triangle(mesh,a-normal,a+normal,b+normal);triangle(mesh,a-normal,b+normal,b-normal)

func quad(mesh: ImmediateMesh,p: Vector3,x: Vector3,y: Vector3) -> void:
	triangle(mesh,p-x-y,p+x-y,p+x+y);triangle(mesh,p-x-y,p+x+y,p-x+y)

func triangle(mesh: ImmediateMesh,a: Vector3,b: Vector3,c: Vector3) -> void:
	mesh.surface_add_vertex(a);mesh.surface_add_vertex(b);mesh.surface_add_vertex(c)
