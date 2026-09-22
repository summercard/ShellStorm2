extends Node
## 一次性探针：清点掉落池登记表 vs 物品表声明键，打印每个池的 status/roll/cap/成员。
## 目的：① 冒烟验证 RewardPoolRegistry 修正后可运行；② 为 verify_reward_service_flow
## 选测试池（需要"成员数 2~8 的 active 池"来做 independent 覆盖层替身）。
## 只读，不写任何游戏状态、不碰存档。

func _ready() -> void:
	print("[POOL-CENSUS] %s" % RewardPoolRegistry.summary_line())
	var report := RewardPoolRegistry.evaluate()
	print("[POOL-CENSUS] ok=%s unregistered=%s empty_active=%s mixed=%s invalid_chance=%s missing_cap=%s deprecated_without_target=%s pending=%s" % [
		str(report["ok"]),
		str(report["unregistered"]),
		str(report["empty_active"]),
		str(report["mixed_fields"]),
		str(report["invalid_chance"]),
		str(report["missing_cap"]),
		str(report["deprecated_without_target"]),
		str(report["pending_decisions"]),
	])
	for pool_id in RewardPoolRegistry.pool_ids():
		var info := RewardPoolRegistry.get_pool(pool_id)
		var members := RewardPoolRegistry.members(pool_id)
		var ids: Array[String] = []
		for member in members:
			ids.append("%s(w=%s,p=%s)" % [
				str(member.get("id", "")),
				str(member.get("loot_weight", -1)),
				str(member.get("loot_chance", -1.0)),
			])
		print("[POOL-CENSUS] %-28s status=%-10s roll=%-11s cap=%d declared_cap=%s members=%d :: %s" % [
			pool_id,
			str(info.get("status", "")),
			str(info.get("roll", "")),
			RewardPoolRegistry.cap(pool_id),
			str(RewardPoolRegistry.has_declared_cap(pool_id)),
			members.size(),
			", ".join(ids),
		])
	print("[POOL-CENSUS] DONE")
	get_tree().quit(0)
