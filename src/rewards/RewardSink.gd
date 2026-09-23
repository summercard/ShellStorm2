class_name RewardSink
extends RefCounted
## RewardSink — 统一发放层（三个出口）。REWARD-SERVICE 的最后一段：把解析出的实体交给场景。
##
##   GroundSink     落地为地面实体（遵守 04 §21：一物一实体，`count` 为真实数量）
##   InventorySink  直接进背包，失败则溢出到 GroundSink
##   WalletSink     直接入魂
##
## 分工纪律：`plan()` 是**纯逻辑**（只分类，不碰场景），`apply()` 只调用宿主暴露的三个具名方法。
## 本类不得 import 任何 `world3d`，也不得自己抽表 —— 抽表只有 `RewardService` 一处。
##
## 默认出口 = `ground`：保持「魂落在死亡点、拾取才入账」的现行用户设计（04 §21）。
## 结算/任务奖励这类"直接到手"的调度点显式传 `sink` 或覆盖 `currency_sink`。
##
## 设计依据：`docs/v0.1/04_技术施工_战斗与局内成长.md` §22.6。

const _SERVICE := preload("res://src/rewards/RewardService.gd")
const _SPEC := preload("res://src/rewards/RewardSpec.gd")

const SINK_GROUND := "ground"
const SINK_INVENTORY := "inventory"
const SINK_WALLET := "wallet"
const SINKS := [SINK_GROUND, SINK_INVENTORY, SINK_WALLET]

## 宿主必须实现的三个方法名（缺任何一个 → 该出口整批 deferred，不静默丢弃）。
const HOST_METHOD_GROUND := "reward_sink_spawn_ground"
const HOST_METHOD_INVENTORY := "reward_sink_add_to_inventory"
const HOST_METHOD_WALLET := "reward_sink_add_currency"

class GroundCallbackHost:
	extends RefCounted
	var spawn_ground: Callable
	func reward_sink_spawn_ground(items: Array) -> int:
		if not spawn_ground.is_valid():
			return 0
		return int(spawn_ground.call(items))


## 把解析结果分类到三个出口。纯逻辑，不依赖场景。
##
## options：
##   default_sink:String   grants 未显式带 sink 时的归属，默认 `ground`
##   currency_sink:String  货币实体的归属，默认沿用 grants 自带的 `wallet`
##                         （局内掉落要传 `ground`，让魂落在死亡点）
static func plan(grants: Array, options: Dictionary = {}) -> Dictionary:
	var default_sink := str(options.get("default_sink", SINK_GROUND))
	if not SINKS.has(default_sink):
		default_sink = SINK_GROUND
	var currency_override := str(options.get("currency_sink", ""))

	var out := {
		SINK_GROUND: [] as Array[Dictionary],
		SINK_INVENTORY: [] as Array[Dictionary],
		SINK_WALLET: [] as Array[Dictionary],
	}
	for grant in grants:
		if not (grant is Dictionary):
			continue
		var g: Dictionary = grant
		var is_currency := str(g.get("kind", "")) == _SPEC.KIND_CURRENCY
		var sink := str(g.get("sink", ""))
		if is_currency and not currency_override.is_empty():
			sink = currency_override
		if not SINKS.has(sink):
			sink = SINK_WALLET if is_currency else default_sink
		(out[sink] as Array).append(g)
	return out


## 唯一旧地面实体适配边界。解析/调度报告只保留 grants[]；房间节点仍消费 item 字典。
static func materialize_ground_items(grants: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for grant in grants:
		if not grant is Dictionary:
			continue
		var g := grant as Dictionary
		if str(g.get("kind", "")) == _SPEC.KIND_CURRENCY:
			out.append({
				"id": "__currency__", "name": "魂", "type": "currency",
				"count": maxi(1, int(g.get("amount", 1))), "is_currency": true,
			})
			continue
		if str(g.get("kind", "")) != _SPEC.KIND_ITEM:
			continue
		var item := (g.get("item", {}) as Dictionary).duplicate(true)
		if item.is_empty() or str(item.get("id", "")) != str(g.get("item_id", "")):
			continue
		item["count"] = maxi(1, int(g.get("count", 1)))
		out.append(item)
	return out


## 场景可按一次落点绑定地面宿主，不在 Sink 内缓存房间/坐标。
## 同 apply() 的结果口径：每个 grant 按实际生成实体数记 granted 或 rejected。
static func apply_ground(grants: Array, spawn_ground: Callable) -> Dictionary:
	var host := GroundCallbackHost.new()
	host.spawn_ground = spawn_ground
	return apply(host, {SINK_GROUND: grants})


## 执行发放。返回 `DispatchReport { granted[], deferred[], rejected[] }`。
##
## `host` 需实现本类顶部的三个方法名（`Dungeon3D` / `TowerDescent3D` / 测试替身均可）。
## 宿主缺方法或返回 0 时，那一批进 `deferred`（落地面），**部分失败不回滚已发放部分**。
static func apply(host: Object, classified: Dictionary) -> Dictionary:
	var report := {
		"granted": [] as Array[Dictionary],
		"deferred": [] as Array[Dictionary],
		"rejected": [] as Array[Dictionary],
	}

	var ground: Array = classified.get(SINK_GROUND, [])
	var inventory: Array = classified.get(SINK_INVENTORY, [])
	var wallet: Array = classified.get(SINK_WALLET, [])

	if not ground.is_empty():
		var delivered := _spawn_ground(host, ground)
		for index in range(ground.size()):
			if index < delivered:
				report["granted"].append(ground[index])
			else:
				report["rejected"].append(ground[index])

	if not inventory.is_empty():
		if _host_has(host, HOST_METHOD_INVENTORY):
			var accepted: int = clampi(int(host.call(HOST_METHOD_INVENTORY, inventory)), 0, inventory.size())
			for index in range(inventory.size()):
				if index < accepted:
					report["granted"].append(inventory[index])
				else:
					var overflow := [inventory[index]]
					if _spawn_ground(host, overflow) == 1:
						report["deferred"].append(inventory[index])
					else:
						report["rejected"].append(inventory[index])
		else:
			var delivered := _spawn_ground(host, inventory)
			for index in range(inventory.size()):
				if index < delivered:
					report["deferred"].append(inventory[index])
				else:
					report["rejected"].append(inventory[index])

	if not wallet.is_empty():
		if _host_has(host, HOST_METHOD_WALLET):
			var accepted := clampi(int(host.call(HOST_METHOD_WALLET, wallet)), 0, wallet.size())
			for index in range(wallet.size()):
				if index < accepted:
					report["granted"].append(wallet[index])
				else:
					report["rejected"].append(wallet[index])
		else:
			report["rejected"].append_array(wallet)

	return report


## 一步到位：解析 → 分类 → 发放。调度点只需给 spec / context / sink 选项与宿主。
static func dispatch(spec: Dictionary, context: Dictionary, host: Object, options: Dictionary = {}) -> Dictionary:
	var resolution := _SERVICE.resolve(spec, context)
	var report := apply(host, plan(resolution.get("grants", []), options))
	report["resolution"] = {
		"ok": resolution.get("ok", false),
		"spec_id": resolution.get("spec_id", ""),
		"rejected": resolution.get("rejected", []),
		"errors": resolution.get("errors", []),
		"truncated": resolution.get("truncated", false),
		"used_fallback": resolution.get("used_fallback", false),
	}
	return report


static func _host_has(host: Object, method_name: String) -> bool:
	return host != null and host.has_method(method_name)


static func _spawn_ground(host: Object, grants: Array) -> int:
	if not _host_has(host, HOST_METHOD_GROUND):
		return 0
	var items := materialize_ground_items(grants)
	if items.size() != grants.size():
		return 0
	return clampi(int(host.call(HOST_METHOD_GROUND, items)), 0, grants.size())
