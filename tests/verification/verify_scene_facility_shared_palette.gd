extends Node

const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const SHARED_PALETTE_IMPORT_PATH := SHARED_PALETTE_PATH + ".import"
const PALETTE_IMPORT_CONTRACT := {
	"compress/mode": "0",
	"mipmaps/generate": "false",
}
const SHARED_PALETTE_POST_IMPORT_SCRIPT := "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
const MINIMUM_GLB_COUNT := 44
const COMPONENT_ROOTS := [
	"res://assets/art/environments/base_facility_3d/components",
	"res://assets/art/props/base_world_3d/components",
	"res://assets/art/environments/tower_zones/battle/components/common_components",
]
## 只有这批目录强制「GLB 必须外链公共色盘 + 不内嵌图片」，
## 因为它们全部出自 v003 之后的统一流水线；更早的基地/道具 GLB 走各自的历史机制，
## 把它们一起要求会得到大量与本次改动无关的红灯。
const PALETTE_CONTRACT_ROOTS := [
	"res://assets/art/environments/tower_zones/battle/components/common_components",
]
## 历史欠账：这两件资产出自 v003 之前的流水线，材质至今未绑定公共色盘。
## 把整个验证场景长期挂在红灯上等于没有验证，所以这里用「精确路径欠账表」显式登记它们，
## 而不是放宽整个目录的检查——新增的违规资产不会被豁免，仍会点亮红灯；
## 欠账还清（资产合规了）或路径消失也会报错，逼迫这张表随现实一起更新。
const LEGACY_PALETTE_EXEMPT_GLBS := [
	"res://assets/art/environments/base_facility_3d/components/env_base99_structural/northwest_l_stair/northwest_l_stair_visual_top3d.glb",
	"res://assets/art/environments/base_facility_3d/components/env_base99_wall_contents/loft_good_vibes_neon/loft_good_vibes_neon_visual_top3d.glb",
]


func _ready() -> void:
	var failures: Array[String] = []
	_validate_palette_import_contract(failures)
	var glbs: Array[String] = []
	for root in COMPONENT_ROOTS:
		_collect_glbs(root, glbs)
	_expect(glbs.size() >= MINIMUM_GLB_COUNT, "场景/设施GLB数量异常: %d" % glbs.size(), failures)
	var material_count := 0
	var contract_glbs: Array[String] = []
	for contract_root in PALETTE_CONTRACT_ROOTS:
		_collect_glbs(contract_root, contract_glbs)
	for path in glbs:
		var packed := load(path) as PackedScene
		_expect(packed != null, "GLB无法加载: %s" % path, failures)
		if packed == null:
			continue
		var instance := packed.instantiate()
		var asset_failures: Array[String] = []
		material_count += _validate_materials(instance, path, asset_failures)
		instance.free()
		if path in LEGACY_PALETTE_EXEMPT_GLBS:
			if asset_failures.is_empty():
				failures.append("色盘欠账已还清，请从 LEGACY_PALETTE_EXEMPT_GLBS 移除: %s" % path)
		else:
			failures.append_array(asset_failures)
	for exempt in LEGACY_PALETTE_EXEMPT_GLBS:
		if not glbs.has(exempt):
			failures.append("色盘欠账表指向了不存在的GLB: %s" % exempt)
	_expect(contract_glbs.size() > 0, "没有可校验导入契约的组件GLB", failures)
	for path in contract_glbs:
		_validate_glb_import_contract(path, failures)
	for root in COMPONENT_ROOTS:
		_validate_no_duplicate_png(root, failures)
	_expect(material_count > 0, "没有找到可验证的场景/设施材质", failures)
	if failures.is_empty():
		print("SCENE_FACILITY_SHARED_PALETTE_OK: glbs=%d materials=%d shared_texture=1 lossless_no_mipmap=1 legacy_exempt=%d" % [glbs.size(), material_count, LEGACY_PALETTE_EXEMPT_GLBS.size()])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 公共色盘必须无损且无 MipMap：块压缩或 MipMap 会在纯色色块内部制造网格、
## 条纹和串色，而且这两条参数只活在 .png.import 里，删掉缓存或换机器就会被静默重置。
## 因此这里必须有一条会失败的断言盯着，而不是只写在文档里。
func _validate_palette_import_contract(failures: Array[String]) -> void:
	var params := _read_import_params(SHARED_PALETTE_IMPORT_PATH)
	if params.is_empty():
		failures.append("公共色盘缺少导入契约: %s" % SHARED_PALETTE_IMPORT_PATH)
		return
	for key in PALETTE_IMPORT_CONTRACT:
		var expected: String = PALETTE_IMPORT_CONTRACT[key]
		if not params.has(key):
			failures.append("公共色盘导入契约缺少 %s" % key)
		elif str(params[key]) != expected:
			failures.append("公共色盘 %s=%s，要求 %s（否则色块会串色）" % [key, params[key], expected])


## 每个组件 GLB 必须留下 .glb.import，且该文件本身要能进版本控制，
## 否则换机器后色盘后处理会静默失效，模型退化成未绑定贴图。
func _validate_glb_import_contract(glb_path: String, failures: Array[String]) -> void:
	var import_path := glb_path + ".import"
	if not FileAccess.file_exists(import_path):
		failures.append("GLB 缺少导入契约: %s" % import_path)
		return
	var params := _read_import_params(import_path)
	if params.is_empty():
		failures.append("GLB 导入契约无法解析: %s" % import_path)
		return
	if str(params.get("import_script/path", "")) != SHARED_PALETTE_POST_IMPORT_SCRIPT:
		failures.append("GLB 未绑定公共色盘后处理: %s" % import_path)
	if str(params.get("gltf/embedded_image_handling", "")) != "0":
		failures.append("GLB 仍内嵌图片（embedded_image_handling=%s）: %s" % [params.get("gltf/embedded_image_handling", "?"), import_path])


## 解析 .import 的 [params] 段，返回键值字典；读不到返回空字典。
## 路径类取值在 .import 里是带引号的字符串（如 import_script/path="res://..."），
## 这里必须去掉首尾引号，否则字符串比对会永远为假，把合规资产误判成违规。
func _read_import_params(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var in_params := false
	var params := {}
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("["):
			in_params = line == "[params]"
			continue
		if not in_params or line.is_empty() or line.begins_with(";"):
			continue
		var separator := line.find("=")
		if separator <= 0:
			continue
		var key := line.substr(0, separator)
		var value := line.substr(separator + 1)
		if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2)
		params[key] = value
	file.close()
	return params


func _validate_materials(root: Node, asset_path: String, failures: Array[String]) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material == null:
					continue
				count += 1
				_expect(material.albedo_texture != null, "材质缺少公共色盘: %s" % asset_path, failures)
				if material.albedo_texture != null:
					_expect(material.albedo_texture.resource_path == SHARED_PALETTE_PATH, "材质仍指向模型私有贴图: %s -> %s" % [asset_path, material.albedo_texture.resource_path], failures)
				_expect(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "色盘不是最近邻采样: %s" % asset_path, failures)
	for child in root.get_children():
		count += _validate_materials(child, asset_path, failures)
	return count


func _collect_glbs(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_collect_glbs(child, result)
			elif name.ends_with(".glb"):
				result.append(child)
		name = directory.get_next()
	directory.list_dir_end()


func _validate_no_duplicate_png(path: String, failures: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_validate_no_duplicate_png(child, failures)
			elif name.ends_with(".png") and ("色盘" in name or "palette" in name.to_lower()):
				failures.append("组件目录仍有重复色盘: %s" % child)
		name = directory.get_next()
	directory.list_dir_end()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
