extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var pool := VfxPool3D.new()
	pool.max_per_kind = 2
	add_child(pool)
	var asset_id := VfxPool3D.FX01_IMPACT
	var first := pool.acquire(asset_id, Vector3.ZERO, Color.WHITE, 1.0)
	if first == null:
		failures.append("特效池无法借出已注册特效")
	else:
		first.call("_process", float(first.lifetime) + 0.01)
		if pool.active_count(asset_id) != 0 or pool.inactive_count(asset_id) != 1:
			failures.append("特效结束后没有从active回收到inactive")
		var reused := pool.acquire(asset_id, Vector3.ONE, Color.RED, 0.8)
		if reused != first:
			failures.append("已回收特效没有被下一次借出复用")
		if pool.active_count(asset_id) != 1 or pool.inactive_count(asset_id) != 0:
			failures.append("复用后的active/inactive计数不正确")
	pool.clear_all()
	await get_tree().process_frame
	await get_tree().process_frame
	if pool.active_count(asset_id) != 0 or pool.inactive_count(asset_id) != 0:
		failures.append("场景清理后特效池仍保留active或inactive引用")
	_check_prewarm_cleanup(pool, failures)
	pool.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("VFX_POOL_LIFECYCLE_OK: retire signal, reuse counters and scene cleanup pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check_prewarm_cleanup(pool: VfxPool3D, failures: Array[String]) -> void:
	var id := VfxPool3D.FX01_IMPACT
	var other_id := VfxPool3D.FX01_EXPLOSION
	pool.prewarm([id])
	pool._process(0.0)
	var expired: VfxEffectBase3D = pool._active[id][0]
	expired.finish()
	var playing := pool.acquire(id, Vector3.ZERO, Color.WHITE)
	if playing != expired:
		failures.append("预热结束的实例无法用于正式播放")
	pool.prewarm([id, other_id])
	pool._process(0.0)
	var warming: VfxEffectBase3D = pool._active[id].back()
	pool.finish_prewarm()
	pool.finish_prewarm()
	if pool.has_pending_prewarm() or pool.is_processing() or pool.active_count(other_id) != 0:
		failures.append("取消预热后仍有待执行的预热")
	if warming.is_visible_in_tree() or pool.inactive_count(id) != 1:
		failures.append("已装配的预热实例仍可见或未回池")
	if not playing.is_visible_in_tree() or pool.active_count(id) != 1:
		failures.append("清理预热误停已复借的正式特效")
	var reused := pool.acquire(id, Vector3.ONE, Color.RED)
	if reused != warming or not reused.is_visible_in_tree():
		failures.append("关闭预热后无法继续复用预热实例")
