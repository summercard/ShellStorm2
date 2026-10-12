extends RefCounted
## 将场景依赖里的 GPU 资源分批读取，避免一次 PackedScene 请求集中提交大量上传。
## 只处理资源缓存；节点装配与所有玩法状态仍由主线程/目标场景负责。
const SCAN_BUDGET_USEC := 3000


static func warm(path: String, tree: SceneTree, keep_alive: Array[Resource], report: Callable = Callable(), include_models := true) -> Error:
	var pending: Array[String] = [path]
	var seen := {}
	var images: Array[String] = []
	var models: Array[String] = []
	var scan_started := Time.get_ticks_usec()
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if seen.has(current):
			continue
		seen[current] = true
		if not ResourceLoader.has_cached(current):
			var extension := current.get_extension().to_lower()
			if extension in ["png", "jpg", "jpeg", "webp", "svg", "res"]:
				images.append(current)
			elif include_models and extension in ["glb", "gltf"]:
				models.append(current)
			for dependency in ResourceLoader.get_dependencies(current):
				# Godot 依赖描述可为 uid::type::fallback_path；最后一段是可加载路径。
				var parts := str(dependency).split("::")
				pending.append(parts[-1])
		if Time.get_ticks_usec() - scan_started >= SCAN_BUDGET_USEC:
			await tree.process_frame
			scan_started = Time.get_ticks_usec()
	images.append_array(models)
	var index := 0
	while index < images.size():
		var resource_path := images[index]
		index += 1
		if ResourceLoader.has_cached(resource_path):
			continue
		var error := ResourceLoader.load_threaded_request(resource_path)
		if error != OK:
			return error
		await tree.process_frame
		var status := ResourceLoader.load_threaded_get_status(resource_path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
			status = ResourceLoader.load_threaded_get_status(resource_path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			return ERR_CANT_OPEN
		keep_alive.append(ResourceLoader.load_threaded_get(resource_path))
		if report.is_valid():
			report.call(float(index) / float(images.size()))
	return OK
