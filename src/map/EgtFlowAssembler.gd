class_name EgtFlowAssembler
extends RefCounted
## 《挺进地牢》式关卡组装器：把 flow 图（只有拓扑）变成带坐标的房间表。
##
## 机制来源：Boris the Brave 的反编译分析
## （`docs/v0.1/reference/挺进地牢/随机关卡生成逻辑.md` §一、§二）。五段管线逐段对应：
##
## | 段 | 函数 | 随机点 |
## |---|---|---|
## | 1 选骨架 | `pick_flow()` | ★ |
## | 2 变换（注入 / 选模板） | `assign_templates()` / `apply_injections()` | ★★ |
## | 3 拆最小环 | `cut_loops()` | — |
## | 4 分别拼装（树 DFS / 环两端合） | `_layout_tree()` / `_layout_loop()` | 部分 |
## | 5 总装（从最忙的房间开始） | `_layout_all()` | 部分 |
##
## ## 一句话原理
##
## **房间不存坐标，只存出口。** 拼装 = 从新房间取一个出口、从已放好的结构取一个出口，
## 凑成一对，对齐 —— 新房间的位置就确定了。原文：
## "Exits are pre-defined locations in the metadata for each room."
##
## 本项目里这句话对应两处现成契约，本类**不自造第二份**：
## - 出口位置：`room_templates/*.json` 的 `wall_lane_table`
## - 门槽算法：`RoomDoorLane.lane_offsets()`（首尾各留一格不贴角）
## - 对齐结果复核：`RoomDoorLane.port_pair()` 反向验算（见 `_verify_edges()`）
##
## ## 使用
## ```gdscript
## var result := EgtFlowAssembler.assemble_flow(flow, templates, node_templates, 12345)
## if result["ok"]:
##     for room in result["rooms"]:
##         # room.center / size / template_id / ports = {"east": [-2.5], ...}
## ```

const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")

## 整次布局的重试上限。原文的回溯是"重抽房间模板，最多 3 次"；这里放宽到 24，
## 因为一张骨架有 17 间房、任一间放不下都要重来，3 次远远不够。
const LAYOUT_ATTEMPTS := 128
## 单节点内层重试（已由 LAYOUT_ATTEMPTS 取代，保留供环拼装使用）。
const TREE_BACKTRACK_LIMIT := 3
## 环拼装每个节点的候选出口对上限（防组合爆炸）。
const LOOP_CANDIDATE_LIMIT := 8
## 单节点最多尝试的出口对数量。
const MAX_ATTEMPTS_PER_NODE := 32
## 重叠判定的容差：共墙贴合（交集面积为 0）不算重叠。
const OVERLAP_EPS := 0.01
## 走廊长度区间（米）。原文 4~30 单位、矿坑层 50；本项目 5m 一格，取 5~45。
## 走廊的硬上下限 —— 原文："The corridor must be between 4 and 30 units long
## (50 in the mines)." 远征03 是第一层，取 30；超过说明环被拉直成一条长蛇，
## 是结构缺陷不是风格问题。
const CORRIDOR_HARD_MIN_M := 4.0
const CORRIDOR_HARD_MAX_M := 30.0
## 走廊长度的基本步长（= 一个 5m 格）。
const CORRIDOR_GAP_STEP := 5.0
## 连接房朝向加分的量级。必须**压过**所有基于距离的打分（距离项最大约 ±500），
## 否则"窄长房的长轴要沿行进方向"这条会被距离偏好压掉，连接房就会横着摆。
const CONNECTOR_ORIENTATION_BONUS := 1000.0
## 补走廊时两门允许的横向错位上限（米）。超过要绕 L 形第二段，那一段会沿着
## b 的墙横穿过去，容易压进第三个房间。
##
## 5.0 → 10.0：5 边以上的环（flow_05 的 hub_01→n03→conn_01→n04…n05）闭合时，
## 两端常常错开 2 格而对不齐，卡在 5m 会让整张骨架 0/12。压房风险由
## `_corridor_hits_rooms()` 正面拦（它按 5m 宽的包围矩形判，宁严不宽），
## 所以这里可以放宽到 2 格。
const CORRIDOR_LATERAL_MAX_M := 10.0
## 走廊净宽（米）= 一个 5m 格。桥接层按它生成走廊房间，所以占位判定必须同宽。
const CORRIDOR_WIDTH_M := 5.0

## 注入房的模板归属。**推定值** —— flow 只声明 kind，不声明用哪个模板。
## 选它们的原因：尺寸够放一个独立小房间，且已在远征03 的模板池里。
const INJECTION_TEMPLATE := {
	"SECRET_ROOM": "db_70x50",
	"NPC_SECRET_ROOM": "office_60x70",
	"FIREPLACE_ROOM": "std_25x25",
}

const SIDE_OPPOSITE := {
	"north": "south", "south": "north", "east": "west", "west": "east",
}
const ALL_SIDES: Array[String] = ["north", "south", "east", "west"]


# ── 对外入口 ────────────────────────────────────────────────────────────────
## 全程组装。
##
## - `flow`：一张 flow（`nodes` / `tree_edges` / `loop_edges` / `injections`）
## - `templates`：`template_id -> 模板字典`（含 `size_m` / `wall_lane_table` / `door_contract`）
## - `node_templates`：`node_id -> template_id`（省略时用 `assign_templates` 现算）
static func assemble_flow(flow: Dictionary, templates: Dictionary, node_templates: Dictionary,
		seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var diagnostics := {
		"seed": seed_value,
		"flow_id": str(flow.get("flow_id", "")),
		"stages": [],
	}

	# 段 2a：先算一次模板映射（注入需要它给新节点定模板）
	var first_assign := assign_templates(flow, templates, rng)
	if not bool(first_assign["ok"]):
		return _fail(str(first_assign["error"]), diagnostics)
	var base_mapping: Dictionary = (first_assign["node_templates"] as Dictionary).duplicate(true)
	if not node_templates.is_empty():
		base_mapping = node_templates.duplicate(true)
	diagnostics["stages"].append("templates: %d 从池子抽, %d 固定" % [
		int(first_assign["swapped"]), int(first_assign["pinned"])])

	# 段 2b：注入（只做一次 —— 重试时重掷注入会让概率语义漂移）
	var injected := apply_injections(flow, base_mapping, rng)
	diagnostics["stages"].append("injections: 插入 %d, 跳过 %s" % [
		injected["nodes"].size(), str(injected["skipped"])])

	var graph := {
		"nodes": injected["nodes"],
		"edges": injected["edges"],
		"node_templates": injected["node_templates"],
	}
	# 段 3：拆最小环（拓扑固定，只需算一次）
	var split := cut_loops(graph)
	diagnostics["stages"].append("loops: 切出 %d 个环, 树节点 %d 个" % [
		(split["loops"] as Array).size(), int(split["tree_node_count"])])
	for value in split["loops"] as Array:
		diagnostics["stages"].append("  loop %s" % str((value as Dictionary)["sequence"]))

	# 段 4 + 5：拼装。放不下就**整次重来并重抽房间模板** ——
	# 这是原文 "backtrack and regen the choice of room, up to 3 times" 的完整语义；
	# 改边（把 n03 接到 entry 上）会让地图和设计不符，绝不允许。
	var last_error := ""
	for attempt in range(LAYOUT_ATTEMPTS):
		var mapping := _reroll_pool_templates(flow, split["node_templates"] as Dictionary,
			templates, rng) if attempt > 0 else (split["node_templates"] as Dictionary)
		var attempt_split := split.duplicate(true)
		attempt_split["node_templates"] = mapping
		var layout := _layout_all(attempt_split, templates, rng)
		if not (layout["failures"] as Array).is_empty():
			last_error = str(layout["failures"])
			continue
		var edge_check := _verify_edges(graph, layout["rooms"], layout["connections"])
		if not bool(edge_check["ok"]):
			last_error = str(edge_check["error"])
			continue
		diagnostics["stages"].append("layout: 第 %d 次尝试成功, 放置 %d 间" % [
			attempt + 1, (layout["rooms"] as Array).size()])
		diagnostics["stages"].append("edges: %d 条全部落门" % (edge_check["edges"] as Array).size())
		return {
			"ok": true,
			"error": "",
			"rooms": layout["rooms"],
			"connections": layout["connections"],
			"edges": edge_check["edges"],
			"corridors": layout["corridors"],
			"loops": split["loops"],
			"attempts": attempt + 1,
			"diagnostics": diagnostics,
		}

	diagnostics["stages"].append("layout: %d 次尝试全部失败" % LAYOUT_ATTEMPTS)
	return _fail("拼装失败（%d 次重试）：%s" % [LAYOUT_ATTEMPTS, last_error.substr(0, 200)],
		diagnostics)


## 重抽池子模板（固定 template_id 的节点不动）。EGT 的回溯就发生在这一层。
static func _reroll_pool_templates(flow: Dictionary, current: Dictionary,
		templates: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := current.duplicate(true)
	for value in flow.get("nodes", []) as Array:
		var node := value as Dictionary
		var pool: Array = []
		for item in node.get("template_pool", []) as Array:
			if templates.has(str(item)):
				pool.append(str(item))
		if pool.size() < 2:
			continue
		# 连接房的重抽没有意义：它的模板在布局时才定，本来就每轮重选。
		if str(node.get("kind", "")) == "CONNECTOR":
			continue
		var node_id := str(node.get("node_id", ""))
		var picked := str(pool[rng.randi_range(0, pool.size() - 1)])
		# 尽量换成与当前不同的
		if picked == str(out.get(node_id, "")):
			picked = str(pool[(pool.find(picked) + 1) % pool.size()])
		out[node_id] = picked
	return out


## 段 1：从一层里的多张 flow 抽一张（`seeded_uniform`）。
static func pick_flow(flows: Array, seed_value: int) -> Dictionary:
	if flows.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return flows[rng.randi_range(0, flows.size() - 1)] as Dictionary


# ── 段 2a：选模板 ───────────────────────────────────────────────────────────
## 每个节点挑一个具体模板。`NORMAL` 从 `template_pool` 抽，其余用固定 `template_id`。
## 原文："avoid picking the same room twice"（同一局不重复）—— 池子够大时优先未用过的。
static func assign_templates(flow: Dictionary, templates: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var node_templates := {}
	var used := {}
	var swapped := 0
	var pinned := 0
	for value in flow.get("nodes", []) as Array:
		var node := value as Dictionary
		var node_id := str(node.get("node_id", ""))
		var pinned_id := str(node.get("template_id", ""))
		var pool: Array = []
		for item in node.get("template_pool", []) as Array:
			if templates.has(str(item)):
				pool.append(str(item))

		if pool.is_empty():
			if pinned_id.is_empty() or not templates.has(pinned_id):
				return {"ok": false,
					"error": "节点 %s 既无可用 template_pool 也无 template_id" % node_id}
			node_templates[node_id] = pinned_id
			used[pinned_id] = int(used.get(pinned_id, 0)) + 1
			pinned += 1
			continue

		var unused: Array = []
		for tid in pool:
			if not used.has(tid):
				unused.append(tid)
		var candidates: Array = unused if not unused.is_empty() else pool
		var chosen := str(candidates[rng.randi_range(0, candidates.size() - 1)])
		node_templates[node_id] = chosen
		used[chosen] = int(used.get(chosen, 0)) + 1
		swapped += 1
	return {"ok": true, "error": "", "node_templates": node_templates,
		"swapped": swapped, "pinned": pinned}


# ── 段 2b：注入 ─────────────────────────────────────────────────────────────
## 按注入规则往图上插特殊节点。四要素：`{注什么类型, 注在哪, 概率, 前置条件}`。
##
## - `dead_end_first`：只在死胡同（度 1 且非根）挂；没有死胡同就按
##   `anchor_fallback_probability` 决定是否退到任意房间。
## - `scope: "run"`（跨层预算）：**本层不决定**，记进 `skipped`，不静默忽略。
static func apply_injections(flow: Dictionary, node_templates: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var nodes := {}
	var mapping := node_templates.duplicate(true)
	for value in flow.get("nodes", []) as Array:
		var node := value as Dictionary
		var node_id := str(node.get("node_id", ""))
		# **整个节点原样保留**，只覆盖 template_id。
		#
		# 旧版只取 node_id / kind / template_id 三个字段，把 `template_pool` 丢了 ——
		# 后果是连接房"布局时选模板"的判据（kind==CONNECTOR 且池非空）永远不成立，
		# 连接房于是退回成开局随机定一个模板，长轴朝向完全不受控。
		# 这个 bug 隐蔽在于：组装仍然成功、断言（当时还没这条）全绿，只是形状不对。
		var entry := node.duplicate(true)
		entry["node_id"] = node_id
		entry["kind"] = str(node.get("kind", ""))
		entry["template_id"] = str(mapping.get(node_id, ""))
		nodes[node_id] = entry
	var edges: Array = []
	for value in flow.get("tree_edges", []) as Array:
		var edge := value as Dictionary
		edges.append({"from": str(edge.get("from", "")), "to": str(edge.get("to", "")),
			"kind": "tree"})
	for value in flow.get("loop_edges", []) as Array:
		var edge := value as Dictionary
		edges.append({"from": str(edge.get("from", "")), "to": str(edge.get("to", "")),
			"kind": "loop"})

	var root_id := _root_of(flow)
	var skipped: Array = []
	var inserted := 0
	for value in flow.get("injections", []) as Array:
		var rule := value as Dictionary
		var inject_id := str(rule.get("inject_id", ""))
		if str(rule.get("scope", "shared")) == "run":
			skipped.append("%s(scope=run：跨层预算不在此处决定)" % inject_id)
			continue
		var kind := str(rule.get("kind", ""))
		if not INJECTION_TEMPLATE.has(kind):
			skipped.append("%s(kind=%s 无模板映射)" % [inject_id, kind])
			continue
		if rng.randf() >= float(rule.get("probability", 0.0)):
			skipped.append("%s(掷骰未中 p=%.2f)" % [inject_id, float(rule.get("probability", 0.0))])
			continue

		var anchor := _pick_anchor(rule, nodes, edges, root_id, rng)
		if anchor.is_empty():
			skipped.append("%s(无可用锚点)" % inject_id)
			continue

		inserted += 1
		var new_id := "%s_inj%d" % [kind.to_lower(), inserted]
		nodes[new_id] = {
			"node_id": new_id, "kind": kind,
			"template_id": str(INJECTION_TEMPLATE[kind]),
			"injected_by": inject_id,
		}
		mapping[new_id] = str(INJECTION_TEMPLATE[kind])
		edges.append({"from": anchor, "to": new_id, "kind": "inject"})

	return {"nodes": nodes, "edges": edges, "node_templates": mapping, "skipped": skipped}


static func _pick_anchor(rule: Dictionary, nodes: Dictionary, edges: Array,
		root_id: String, rng: RandomNumberGenerator) -> String:
	var dead_ends := _dead_ends(nodes, edges, root_id)
	if str(rule.get("anchor_policy", "dead_end_first")) == "dead_end_first":
		if not dead_ends.is_empty():
			return str(dead_ends[rng.randi_range(0, dead_ends.size() - 1)])
		if rng.randf() >= float(rule.get("anchor_fallback_probability", 0.0)):
			return ""
	var candidates: Array = []
	for node_id in nodes:
		if str(node_id) != root_id:
			candidates.append(str(node_id))
	candidates.sort()
	if candidates.is_empty():
		return ""
	return str(candidates[rng.randi_range(0, candidates.size() - 1)])


# ── 段 3：拆最小环 ──────────────────────────────────────────────────────────
## "找图里最小的环 → 整块切出来当一个复合对象 → 重复到没有环"。
##
## 实现：每条 `loop` 边加上它在树上的路径就是一个环。按路径长度**升序**贪心切，
## 已被切走的节点不再归属下一个环（原文是"整块切出来"，节点归环所有）。
static func cut_loops(graph: Dictionary) -> Dictionary:
	var nodes := graph["nodes"] as Dictionary
	var adj := {}
	var tree_edges: Array = []
	var loop_edges: Array = []
	for value in graph["edges"] as Array:
		var edge := value as Dictionary
		var a := str(edge["from"])
		var b := str(edge["to"])
		if str(edge.get("kind", "tree")) == "loop":
			loop_edges.append(edge)
			continue
		tree_edges.append(edge)
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)

	var candidates: Array = []
	for value in loop_edges:
		var edge := value as Dictionary
		var path := _tree_path(adj, str(edge["from"]), str(edge["to"]))
		if path.size() >= 3:
			candidates.append({"path": path, "edge": edge})
	candidates.sort_custom(func(x, y): return (x["path"] as Array).size() < (y["path"] as Array).size())

	var claimed := {}
	var loops: Array = []
	for value in candidates:
		var item := value as Dictionary
		var path := item["path"] as Array
		var conflict := false
		for node_id in path:
			if claimed.has(str(node_id)) and str(node_id) != str(path[0]):
				conflict = true
				break
		if conflict:
			continue
		for node_id in path:
			claimed[str(node_id)] = true
		loops.append({
			"sequence": path,
			"attach_node": str(path[0]),
			"closing_edge": item["edge"],
		})

	# 每个环的接点 = 环与树的连接点。三条优先级，越靠前越稳：
	#   1. 根节点在环里 → 它一定是接点（树 DFS 从这里出发）
	#   2. 有"环外邻居"的节点 → 树会走到它
	#   3. 都没有 → 退回环首，环自落（会与已有房间重叠则失败重试）
	var root_hint := _root_of_graph(nodes, tree_edges)
	for value in loops:
		var loop := value as Dictionary
		var members := {}
		for node_id in loop["sequence"] as Array:
			members[str(node_id)] = true
		var attach := ""
		if members.has(root_hint):
			attach = root_hint
		if attach.is_empty():
			for node_id in loop["sequence"] as Array:
				for neighbor in adj.get(str(node_id), []) as Array:
					if not members.has(str(neighbor)):
						attach = str(node_id)
						break
				if not attach.is_empty():
					break
		if attach.is_empty():
			attach = str((loop["sequence"] as Array)[0])
		loop["attach_node"] = attach

	var loop_members := {}
	var attach_nodes := {}
	for value in loops:
		var loop := value as Dictionary
		attach_nodes[str(loop["attach_node"])] = true
		for node_id in loop["sequence"] as Array:
			loop_members[str(node_id)] = true

	var tree_nodes: Array = []
	for node_id in nodes:
		if not claimed.has(str(node_id)):
			tree_nodes.append(str(node_id))
	tree_nodes.sort()
	return {
		"loops": loops,
		"loop_members": loop_members,
		"attach_nodes": attach_nodes,
		"tree_nodes": tree_nodes,
		"tree_node_count": tree_nodes.size(),
		"adjacency": adj,
		"root_id": _root_of_graph(nodes, tree_edges),
		"all_edges": graph["edges"],
		"nodes": nodes,
		"node_templates": graph["node_templates"],
	}


# ── 段 4 + 5：拼装 ──────────────────────────────────────────────────────────
## 段 4 + 5：拼装。
##
## 顺序照原文："walked over, starting with the room with the most connections."
##
## ## 为什么环不单独拼装
##
## 第一版把环"切出来独立拼"，结果：树 DFS 已经把环上的节点全铺了（因为环的边有一半是
## 树边），环拼装时全部命中"已放置"守卫 ⇒ `loop_edge`（闭合那条）**永远没人连**，
## 拓扑缺边。实测六张骨架 0/72 成功。
##
## 现在的做法：**树 DFS 一次铺完所有节点**（拓扑由它保证），然后对**每一条还没落门的边**
## 调 `_connect_edge()`。环的闭合因此走"补走廊"这条路 —— 这正是原文允许的收尾方式
## （"pathfinds between the exits, and makes a 'room' that is just a narrow corridor"）。
static func _layout_all(split: Dictionary, templates: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var ctx := {
		"templates": templates,
		"node_templates": split["node_templates"],
		"nodes": split["nodes"],
		"adjacency": split["adjacency"],
		"rng": rng,
		"rooms": {},
		"connections": [],
		"misaligned": [],
	}
	var failures: Array = []
	var corridors: Array = []
	var root_id := str(split["root_id"])

	# 三段式，对应原文"切环 → 分别拼装 → 总装"：
	#
	#   1. **树**：从根出发深度优先，**跳过环成员**，只铺环外的部分。
	#   2. **环**：每个环按"从接点两端往中间合"独立拼（`_layout_loop`）。
	#   3. **总装**：环就位后解除排除，再把剩余子树接上
	#      —— 挂在环下面的子树（boss / shop / exit）就是在这一步接上的。
	#
	# 早先版本只有第 1 步（不排除环成员），环被 DFS 拉成一条直线，最后靠一条
	# 55~70m 的走廊闭合 —— 画出来就是"一条细线"，根本不是环。
	# 后来试过排除环成员但没有第 3 步，挂在环下面的子树全部走不到
	# （flow_01 每次 7 间房"不连通"）。第 3 步就是补那个缺口。
	ctx["excluded"] = split["loop_members"]

	# 节点 → 所属环 id。`_corridor_gap()` 用它判断"这对门是不是同一个环的两个成员"：
	# 是则紧贴（形成原文说的 tight loops），否则垫走廊。
	var loop_of := {}
	for index in range((split["loops"] as Array).size()):
		var loop := (split["loops"] as Array)[index] as Dictionary
		for node_id in loop["sequence"] as Array:
			loop_of[str(node_id)] = index
	ctx["loop_of"] = loop_of

	# 连接房：模板不在开局定，留到布局时按行进方向选（原文"picked later"）。
	# 判据：kind == CONNECTOR 且池里至少 2 个可用模板（1 个就没有选的意义）。
	var deferred := {}
	var node_map := split["nodes"] as Dictionary
	for node_key in node_map.keys():
		var node := node_map[node_key] as Dictionary
		if str(node.get("kind", "")) != "CONNECTOR":
			continue
		var pool: Array = []
		for item in node.get("template_pool", []) as Array:
			if templates.has(str(item)):
				pool.append(str(item))
		if pool.size() >= 2:
			deferred[str(node_key)] = pool
	ctx["deferred_pools"] = deferred

	if not root_id.is_empty():
		var tree_result := _layout_tree(root_id, ctx)
		if not bool(tree_result["ok"]):
			failures.append("树块: %s" % str(tree_result["error"]))

	# 2. 环：从接点两端往中间合（原文 "adding entries alternately at either end"）
	#
	# **顺序不能照 cut_loops 的输出**：环之间会互相依赖接点。实测 flow_01 的
	# 两个环是 [reward_02,n06,n05,hub_02] 和 [reward_01,n03,hub_01,n02,n01]，
	# 前者要接到 n04 上，而 n04 是后者成员 hub_01 的子 —— 先处理前者必然
	# "找不到接点"，然后退回原点自落、撞上 entry，64 轮重试全灭。
	#
	# 改成迭代：每轮只放**接点已就位**的环，放完再扫一遍，直到没有进展。
	# 这与原文"总装时按连接最多的房间出发"是同一种思路，只是作用在复合对象层。
	if failures.is_empty():
		var pending: Array = []
		for value in split["loops"] as Array:
			pending.append(value as Dictionary)
		var progress_guard := 0
		while not pending.is_empty() and progress_guard < 32:
			progress_guard += 1
			var progressed := false
			# ① 环：能接上的先放
			var still_pending: Array = []
			for loop in pending:
				var loop_result := _layout_loop(loop, ctx)
				if bool(loop_result["ok"]):
					progressed = true
				elif bool(loop_result.get("retryable", false)):
					still_pending.append(loop)
				else:
					failures.append("环 %s: %s" % [
						str(loop["sequence"]), str(loop_result["error"])])
			pending = still_pending
			# ② 总装：补**非环成员**（它们可能就是下一个环的接点）
			#
			# 这一步不能等到所有环都放完再做。实测 flow_01：环 A 放下 hub_01 后，
			# 环 B 的接点 n04 才可能就位；而 n04 是"父为环成员"的树节点，
			# 只能由总装补。于是「环 → 总装 → 环」必须交替，否则环 B 永远等不到 n04。
			# `_sweep_remaining` 会跳过 `excluded`（= 全部环成员），所以这里安全。
			if not pending.is_empty() and failures.is_empty():
				var before := (ctx["rooms"] as Dictionary).size()
				_sweep_remaining(ctx)
				if (ctx["rooms"] as Dictionary).size() > before:
					progressed = true
			if not progressed:
				break
		for loop in pending:
			failures.append("环 %s: 接点始终未就位（%d 轮后放弃）" % [
				str(loop["sequence"]), progress_guard])

	# 3. 总装：环成员已就位，解除排除后把剩余子树铺完
	if failures.is_empty():
		ctx["excluded"] = {}
		var sweep := _sweep_remaining(ctx)
		if not bool(sweep["ok"]):
			failures.append("总装: %s" % str(sweep["error"]))

	# 仍有未放置的（图不连通）：单独落位并如实记失败
	var remaining: Array = []
	for node_id in split["tree_nodes"] as Array:
		if not (ctx["rooms"] as Dictionary).has(str(node_id)):
			remaining.append(str(node_id))
	for node_id in remaining:
		var iso := _make_room(node_id, ctx, Vector2.ZERO)
		if iso.is_empty():
			failures.append("%s: 模板缺失" % node_id)
			continue
		(ctx["rooms"] as Dictionary)[node_id] = iso
		failures.append("%s: 与主图不连通，单独落位" % node_id)

	# 补齐所有未落门的边（含 loop 边与注入边）
	if failures.is_empty():
		var closed := _connect_remaining_edges(split, ctx)
		failures.append_array(closed["failures"] as Array)
		corridors.append_array(closed["corridors"] as Array)

	var ordered: Array = []
	var keys: Array = (ctx["rooms"] as Dictionary).keys()
	keys.sort()
	for node_id in keys:
		ordered.append((ctx["rooms"] as Dictionary)[str(node_id)])

	# 走廊一律从"连接事实"里汇总 —— 不另存一份，否则两处会走偏。
	var corridor_list: Array = []
	for value in ctx["connections"] as Array:
		var conn := value as Dictionary
		if str(conn.get("kind", "direct")) != "corridor":
			continue
		corridor_list.append({
			"from_node": str(conn["a_id"]), "to_node": str(conn["b_id"]),
			"from_side": str(conn["a_side"]), "from_lane": float(conn["a_lane"]),
			"to_side": str(conn["b_side"]), "to_lane": float(conn["b_lane"]),
			"length_m": float(conn.get("corridor_length_m", 0.0)),
		})
	return {"rooms": ordered, "corridors": corridor_list, "failures": failures,
		"connections": ctx["connections"]}


## 把图上每条还没有落门的边补上。先试"两房已相邻、直接对齐门"，否则补走廊。
static func _connect_remaining_edges(split: Dictionary, ctx: Dictionary) -> Dictionary:
	var failures: Array = []
	var corridors: Array = []
	var done := {}
	for value in ctx["connections"] as Array:
		var conn := value as Dictionary
		done[_edge_key(str(conn["a_id"]), str(conn["b_id"]))] = true

	# 环的闭合边优先处理（它们决定环是否闭合），其次才是一般边
	var ordered_edges: Array = []
	var loop_edges: Array = []
	for value in split["all_edges"] as Array:
		var edge := value as Dictionary
		if str(edge.get("kind", "tree")) == "loop":
			loop_edges.append(edge)
		else:
			ordered_edges.append(edge)
	ordered_edges.append_array(loop_edges)

	for value in ordered_edges:
		var edge := value as Dictionary
		var a := str(edge["from"])
		var b := str(edge["to"])
		if done.has(_edge_key(a, b)):
			continue
		var result := _connect_edge(a, b, ctx)
		if not bool(result["ok"]):
			failures.append("边 %s-%s 补不上：%s" % [a, b, str(result["error"])])
			continue
		done[_edge_key(a, b)] = true
		if result.has("corridor"):
			corridors.append(result["corridor"])
	return {"failures": failures, "corridors": corridors}


## 两间已定位的房间之间补一条连接。
## 相邻就直接对齐门；不相邻就补走廊（原文的 pathfind 收尾）。
static func _connect_edge(a_id: String, b_id: String, ctx: Dictionary) -> Dictionary:
	var rooms := ctx["rooms"] as Dictionary
	if not rooms.has(a_id) or not rooms.has(b_id):
		return {"ok": false, "error": "端点未放置"}
	var room_a := rooms[a_id] as Dictionary
	var room_b := rooms[b_id] as Dictionary

	# 1) 已经共墙且能对齐门 → 直接落门
	if bool(_try_direct_close(a_id, b_id, ctx)["ok"]):
		return {"ok": true}

	# 2) 补走廊：**遍历四面 × 空闲门槽的全部相向组合**，不按中心差方向硬选一侧。
	#
	# 旧版用 `_nearest_open_side` 各取一侧、再各取第一条空闲 lane —— 全局只有一个候选。
	# 两房斜向共墙时（x 贴住、y 错开 30m），那个唯一候选的沿行进轴缺口是 0，
	# 走廊跨度为 0：桥接层无从生成房间。而把四面都试一遍，往往能找到另一对
	# 相向的面（例如 a 的南墙对 b 的北墙）真的存在 5m 缺口。
	# 环闭合只有这一步有机会补救，所以必须**搜**，不能猜。
	var best := {}
	for a_side_value in ALL_SIDES:
		var a_side := str(a_side_value)
		var b_side := str(SIDE_OPPOSITE[a_side])
		for a_lane_value in _free_lanes(room_a, a_side):
			var gate_a := _gate_position(room_a, a_side, float(a_lane_value))
			for b_lane_value in _free_lanes(room_b, b_side):
				var gate_b := _gate_position(room_b, b_side, float(b_lane_value))
				var along_x := a_side in ["east", "west"]
				# 沿法线方向必须真的分开（缺口 > 0）。反向说明这两个面不是朝内的。
				var span := (gate_b.x - gate_a.x) if along_x else (gate_b.y - gate_a.y)
				if span < CORRIDOR_HARD_MIN_M or span > CORRIDOR_HARD_MAX_M:
					continue
				# 两门横向错开超过一格时，L 形走廊的第二段会横穿别的房间。
				var lateral := absf((gate_b.y - gate_a.y) if along_x else (gate_b.x - gate_a.x))
				if lateral > CORRIDOR_LATERAL_MAX_M:
					continue
				if _corridor_hits_rooms(a_side, gate_a, gate_b, rooms, a_id, b_id):
					continue
				if best.is_empty() or span < float(best["span"]):
					best = {
						"a_side": a_side, "a_lane": float(a_lane_value),
						"b_side": b_side, "b_lane": float(b_lane_value),
						"gap": gate_a.distance_to(gate_b), "span": span,
					}
	if best.is_empty():
		return {"ok": false,
			"error": "四面都找不到能补走廊的相向面（缺口/横向错位/压房均不满足）"}
	var a_side := str(best["a_side"])
	var b_side := str(best["b_side"])
	var a_lane := float(best["a_lane"])
	var b_lane := float(best["b_lane"])
	var gap := float(best["gap"])
	# 长度取**实际门距**，不做取整 —— 取整会让走廊比缺口长，visual 上压进房间。
	# 两个门不共线时，这段走廊是 L 形的（原文 pathfind 出来的本就允许折）。
	var length := gap
	_commit_port(room_a, a_side, a_lane)
	_commit_port(room_b, b_side, b_lane)
	_record_connection(ctx, a_id, a_side, a_lane, b_id, b_side, b_lane,
		"corridor", length)
	return {"ok": true, "corridor": {
		"from_node": a_id, "to_node": b_id,
		"from_side": a_side, "from_lane": a_lane,
		"to_side": b_side, "to_lane": b_lane,
		"length_m": length, "raw_gap_m": gap, "kind": "pathfind_corridor",
	}}


## 这条走廊占的位置会不会压到第三间房。
##
## 走廊在运行时是**真实房间**（`EgtPlanBridge` 会给它 5m 净宽 + 墙），不是一条线
## —— 所以组装器算位置时必须按 5m 宽的矩形来避让，否则桥接层会报 `room_overlap`。
## 判定取 L 形第二段的**包围矩形**（略大于实际 L 形），宁严不宽。
static func _corridor_hits_rooms(a_side: String, ga: Vector2, gb: Vector2,
		rooms: Dictionary, a_id: String, b_id: String) -> bool:
	var half := CORRIDOR_WIDTH_M * 0.5
	var rects: Array = []
	if a_side in ["east", "west"]:
		rects.append(Rect2(Vector2(minf(ga.x, gb.x), ga.y - half),
			Vector2(absf(gb.x - ga.x), CORRIDOR_WIDTH_M)))
		if absf(gb.y - ga.y) > 0.01:
			var dir := 1.0 if gb.x > ga.x else -1.0
			rects.append(Rect2(
				Vector2(minf(gb.x, gb.x - CORRIDOR_WIDTH_M * dir), minf(ga.y, gb.y) - half),
				Vector2(CORRIDOR_WIDTH_M, absf(gb.y - ga.y) + CORRIDOR_WIDTH_M)))
	else:
		rects.append(Rect2(Vector2(ga.x - half, minf(ga.y, gb.y)),
			Vector2(CORRIDOR_WIDTH_M, absf(gb.y - ga.y))))
		if absf(gb.x - ga.x) > 0.01:
			var dir := 1.0 if gb.y > ga.y else -1.0
			rects.append(Rect2(
				Vector2(minf(ga.x, gb.x) - half, minf(gb.y, gb.y - CORRIDOR_WIDTH_M * dir)),
				Vector2(absf(gb.x - ga.x) + CORRIDOR_WIDTH_M, CORRIDOR_WIDTH_M)))
	# **端点房间也要查**。走廊从门向外长，正常情况下它与端点房只共一条边
	# （交集面积为 0，不会误判）；真判出面积 > 0 说明走廊侵进了端点房内部，
	# 那是几何错误，正是要拦的东西。旧版跳过端点，于是
	# `cr02_conn_01_n03_a` 压 `conn_01` 10×5 这种错静默通过。
	for value in rooms.values():
		var room := value as Dictionary
		var room_id := str(room.get("node_id", ""))
		var size := _size_of_room(room)
		var rect := Rect2((room["center"] as Vector2) - size * 0.5, size)
		for rect_value in rects:
			var inter := (rect_value as Rect2).intersection(rect)
			if inter.size.x > 0.01 and inter.size.y > 0.01:
				return true
	return false


## 树块：深度优先 + 回溯。
## 原文："walking the tree depth first … prefers to select exits far from already used
## exits … backtrack and regen the choice of room, up to 3 times."
static func _layout_tree(root_id: String, ctx: Dictionary) -> Dictionary:
	var root_room := _make_room(root_id, ctx, Vector2.ZERO)
	if root_room.is_empty():
		return {"ok": false, "error": "%s 模板缺失" % root_id}
	(ctx["rooms"] as Dictionary)[root_id] = root_room
	return _dfs_place(root_id, "", ctx)


## 总装：反复找"有已放置邻居的未放置节点"贴上去，直到没有进展。
##
## 环拼完之后，环成员已经在场，所以挂在环下面的子树（boss / shop / exit…）
## 在这一步都能接上。这就是"先造最复杂的中部，再拿其余部分去适配它们"。
static func _sweep_remaining(ctx: Dictionary) -> Dictionary:
	var adjacency := ctx["adjacency"] as Dictionary
	var rooms := ctx["rooms"] as Dictionary
	var excluded := ctx.get("excluded", {}) as Dictionary
	var guard := 0
	while guard < 8192:
		guard += 1
		var candidates: Array = []
		for node_key in adjacency.keys():
			var node_id := str(node_key)
			if rooms.has(node_id) or excluded.has(node_id):
				continue
			for value in adjacency[node_key] as Array:
				var anchor := str(value)
				if rooms.has(anchor):
					candidates.append({"node": node_id, "anchor": anchor})
					break
		if candidates.is_empty():
			return {"ok": true, "error": ""}
		# 分叉多的先铺，避免最后被挤在角落
		candidates.sort_custom(func(a, b):
			return (adjacency.get(a["node"], []) as Array).size() > (adjacency.get(b["node"], []) as Array).size())
		var progressed := false
		for item in candidates:
			var placed := _place_child(str(item["node"]), str(item["anchor"]), ctx)
			if bool(placed["ok"]):
				progressed = true
				break
		if not progressed:
			var stuck: Array = []
			for item in candidates:
				stuck.append("%s←%s" % [str(item["node"]), str(item["anchor"])])
			return {"ok": false, "error": "剩余节点都贴不上：%s" % ", ".join(stuck)}
	return {"ok": false, "error": "总装迭代超上限（疑似死循环）"}


## 这一对门之间垫多长的通道（米）。
##
## 为什么需要这一段：EGT 的地图和 flow 图**不是一一对应**的 —— Boris 原话
## "there's these weird corridor rooms"，实际地图上会多出 flow 里没有的走廊房间。
## 全部把房间直接贴死，画出来就是一大片方块，没有通道，也不像 EGT 的地图。
##
## 也不是"处处拉长走廊"。原文对整体形状的取舍是：
##
## > "The generator emphasizes making **tight loops and short corridors** for the
## >  most central parts, and then tries to fit everything else around that."
##
## 而且走廊在原作里是**少数**：Boris 说地图和 flow 图"不完全对应，多出了一些
## 奇怪的走廊房间"—— 是例外，不是常态。多数房间仍然共墙贴合。
##
## 所以分两种：
## - **环内**（两个端点同属一个环）→ gap 0，直接共墙贴合，形成"紧环"
## - **其余连接** → 约一半直接贴合，另一半垫 5~15m 走廊
##
## 上一版一律 gap 0，整层摊成一大块方阵、完全看不出通道（业主指出）；
## 一律加走廊又拉成一条斜线长蛇。按下面的比例混着才像：
## 房间成团，团与团之间用短廊接。
static func _corridor_gap(ctx: Dictionary, a_id: String, b_id: String) -> float:
	var loop_of := ctx.get("loop_of", {}) as Dictionary
	# 同一环的两个成员：紧贴，形成紧环
	if loop_of.has(a_id) and loop_of.get(a_id) == loop_of.get(b_id):
		return 0.0
	var rng := ctx["rng"] as RandomNumberGenerator
	var roll := rng.randf()
	if roll < 0.45:
		return 0.0
	if roll < 0.78:
		return CORRIDOR_GAP_STEP
	if roll < 0.94:
		return CORRIDOR_GAP_STEP * 2.0
	return CORRIDOR_GAP_STEP * 3.0


static func _dfs_place(node_id: String, came_from: String, ctx: Dictionary) -> Dictionary:
	var adjacency := ctx["adjacency"] as Dictionary
	var rooms := ctx["rooms"] as Dictionary
	var excluded := ctx.get("excluded", {}) as Dictionary
	var neighbors: Array = []
	for value in adjacency.get(node_id, []) as Array:
		var other := str(value)
		if other == came_from or rooms.has(other):
			continue
		if excluded.has(other):
			continue  # 环成员归环拼装，树不碰
		neighbors.append(other)
	# 先铺分叉多的，避免最后被挤在角落
	neighbors.sort_custom(func(a, b):
		return (adjacency.get(a, []) as Array).size() > (adjacency.get(b, []) as Array).size())

	for child_id in neighbors:
		var placed := _place_child(str(child_id), node_id, ctx)
		if not bool(placed["ok"]):
			return {"ok": false, "error": "放不下 %s: %s" % [child_id, str(placed["error"])]}
		var deeper := _dfs_place(str(child_id), node_id, ctx)
		if not bool(deeper["ok"]):
			return deeper
	return {"ok": true, "error": ""}


## 把一个子房间贴到**它在图上的父房间**上。
##
## ⚠️ 这里刻意**不允许**"接不上就换别的房间"。第一版那样做过，结果是拓扑被改：
## 图上 `hub_01-n03` 相连，实际把 n03 接到了 `entry` 上 —— 生成的地图和设计不符，
## 把一个子房间贴到**它在图上的父房间**上。
##
## ⚠️ 刻意**不允许**"接不上就换别的房间"。第一版那样做过，结果是拓扑被改：
## 图上 `hub_01-n03` 相连，实际把 n03 接到了 `entry` 上 —— 生成的地图和设计不符。
## EGT 的回溯是"重抽房间模板"（原文 "backtrack and regen the choice of room"），
## 不是改边；放不下就如实失败，由 outer 循环整次重试。
static func _place_child(child_id: String, parent_id: String, ctx: Dictionary) -> Dictionary:
	var rooms := ctx["rooms"] as Dictionary
	if rooms.has(child_id):
		return {"ok": false, "error": "%s 已被放置，不能再挂到 %s" % [child_id, parent_id]}
	if not rooms.has(parent_id):
		return {"ok": false, "error": "父房间 %s 未放置" % parent_id}

	var anchor := rooms[parent_id] as Dictionary
	# 这对门之间留多长的通道。环内成员之间为 0（共墙，形成紧环），
	# 其余连接垫 5~20m 走廊 —— 这就是 EGT 地图上"房间之间那段通道"。
	var gap := _corridor_gap(ctx, parent_id, child_id)
	var pair := _best_pair(child_id, parent_id, anchor, rooms, ctx, Vector2.INF, gap)
	if pair.is_empty():
		return {"ok": false, "error": "%s 贴不到 %s 上（所有出口对都会重叠）" % [
			child_id, parent_id]}

	var room := pair["room"] as Dictionary
	_commit_port(anchor, str(pair["anchor_side"]), float(pair["anchor_lane"]))
	_commit_port(room, str(pair["child_side"]), float(pair["child_lane"]))
	(room["parents"] as Dictionary)[str(pair["anchor_side"])] = parent_id
	rooms[child_id] = room
	_record_connection(ctx, parent_id, str(pair["anchor_side"]), float(pair["anchor_lane"]),
		child_id, str(pair["child_side"]), float(pair["child_lane"]),
		"direct" if gap <= 0.0 else "corridor", gap)
	return {"ok": true, "error": ""}


## 在指定锚点房上找一对门：锚点侧全部空闲槽 × 子房侧全部候选槽，取最优解。
##
## 子房可能有**多个候选模板**（连接房就是），所以最外层多一层模板循环：
## 对每个候选模板各试一遍，取分最高者。选中的模板写进 `pair["room"]["template_id"]`，
## 这就是原文说的"rooms picked later, while layout occurs"。
static func _best_pair(child_id: String, anchor_id: String, anchor: Dictionary,
		rooms: Dictionary, ctx: Dictionary, toward: Vector2 = Vector2.INF,
		gap: float = 0.0) -> Dictionary:
	var templates := ctx["templates"] as Dictionary
	var candidates := _candidate_templates(ctx, child_id)
	var best: Dictionary = {}
	var best_score := -INF
	for tpl_id in candidates:
		if not templates.has(str(tpl_id)):
			continue
		var child_size := _size_of(templates[str(tpl_id)] as Dictionary)
		if child_size == Vector2.ZERO:
			continue
		for anchor_side in ALL_SIDES:
			for anchor_lane in _free_lanes(anchor, str(anchor_side)):
				for child_side in ALL_SIDES:
					if str(child_side) == str(anchor_side):
						continue
					for child_lane in _candidate_lanes(templates, str(tpl_id), str(child_side)):
						var center := _aligned_center(anchor, str(anchor_side), float(anchor_lane),
							child_size, str(child_side), float(child_lane), gap)
						var room := {
							"node_id": child_id,
							"kind": _kind_of(ctx, child_id),
							"template_id": str(tpl_id),
							"center": center,
							"size": child_size,
							"ports": {},
							"parents": {},
						}
						if _overlaps_any(room, rooms):
							continue
						# 源头自检：算出的位置必须让两个门相距恰好 = gap
						var gate_a := _gate_position(anchor, str(anchor_side), float(anchor_lane))
						var gate_b := _gate_position(room, str(child_side), float(child_lane))
						if absf(gate_a.distance_to(gate_b) - gap) > 0.01:
							(ctx["misaligned"] as Array).append("%s@%.1f->%s@%.1f" % [
								anchor_side, float(anchor_lane), child_side, float(child_lane)])
							continue
						# **走廊占位必须在这一步就拦**，不能等到补边阶段。
						#
						# 走廊是"边放房间边生成"的（`_corridor_gap` 决定间隙），它占的是
						# anchor 与 child 之间那段空隙。旧版只检查新房间本身不重叠，
						# 于是两个房间之间那条 5m 宽的通道可以横穿第三个房间 ——
						# 桥接层把它变成真实走廊房之后就是 `room_overlap`（实测 12/120 局）。
						# 到补边阶段才发现已经晚了：那时所有房间都定死，只能重排整层。
						if gap > 0.0 and _corridor_hits_rooms(
								str(anchor_side), gate_a, gate_b, rooms, anchor_id, child_id):
							continue
						var score := _pair_score(ctx, child_id, str(tpl_id), str(anchor_side),
							str(child_side), room, anchor, anchor_id, rooms, toward)
						if score > best_score:
							best_score = score
							best = {"anchor_id": anchor_id, "anchor_side": str(anchor_side),
								"anchor_lane": float(anchor_lane), "child_side": str(child_side),
								"child_lane": float(child_lane), "room": room,
								"template_id": str(tpl_id)}
	return best


## 一对出口的得分。四项相加，量级递减：
##
## 1. **窄长房朝向**（+1000）—— 连接房的长轴必须沿行进方向，这一项必须压过全部距离项；
## 2. **环后半段拉近**（toward × 4）—— 原文 "bring the two unclosed ends closer together"；
## 3. **环前半段偏好对面墙**（+6）—— 原文 "with preference for opposing walls"；
## 4. **树**：紧凑为主 + 上限内轻微推向空白（`_spread_score` 权重 0.35、封顶 45m）。
static func _pair_score(ctx: Dictionary, child_id: String, tpl_id: String, anchor_side: String,
		child_side: String, room: Dictionary, anchor: Dictionary, anchor_id: String,
		rooms: Dictionary, toward: Vector2) -> float:
	var center: Vector2 = room["center"]
	var score := _connector_orientation_score(ctx, child_id, tpl_id, child_side)
	# 锚点那侧也要管：如果锚点本身是连接房，下一个房间必须从它的**长轴端**接进来，
	# 否则连接房会变成"从侧边岔出去的一间小房"，失去穿堂的意义。
	# 只算子房一侧是不够的 —— 实测每张含连接房的骨架都栽在这里（0/2 或 1/2 扇门在长轴上）。
	score += _anchor_connector_bonus(ctx, anchor_id, anchor_side, anchor)
	if toward.is_finite():
		score += -center.distance_to(toward) * 4.0
		if child_side == str(SIDE_OPPOSITE[anchor_side]):
			# 这一项是**恒真**的：两房要接上，child 的门必然开在 anchor 门的对面墙上
			# （`_best_pair` 只枚举相向的组合）。所以它只是记账，不参与择优。
			#
			# 曾经把它当"偏好对面墙"抬到 400，想借此让环两端分向相反面 —— 无效，
			# 因为真正的自由度在 `anchor_side`（从 anchor 的哪一面出去），不在这一项。
			# 实测调 6 → 400 后 112/120 一位没变。
			score += 6.0
	else:
		score += -center.distance_to(anchor["center"] as Vector2)
		score += 0.35 * minf(45.0, _spread_score(room, rooms, anchor_id))
	return score


## 连接房的长轴要沿着**行进方向**。
##
## 从 `child_side` 那道墙进来的门，法线垂直于该墙；长轴应与法线平行 ——
## 走进去是"穿过一条窄长空间"，而不是横着穿过它。
## 非连接房（只有单一模板）恒返回 0，不受影响。
static func _connector_orientation_score(ctx: Dictionary, node_id: String,
		tpl_id: String, child_side: String) -> float:
	var deferred := ctx.get("deferred_pools", {}) as Dictionary
	if not deferred.has(node_id):
		return 0.0
	var templates := ctx["templates"] as Dictionary
	if not templates.has(tpl_id):
		return 0.0
	var size := _size_of(templates[tpl_id] as Dictionary)
	var long_along_y := size.y > size.x
	var travel_along_y := str(child_side) in ["north", "south"]
	return CONNECTOR_ORIENTATION_BONUS if long_along_y == travel_along_y else 0.0


## 锚点是连接房时，优先从它**长轴两端**接出去。
##
## 连接房的语义是"穿过去"，两个门该在长轴两端。只约束子房一侧不够：
## 实测 flow_02 / flow_03 / flow_05 / flow_06 里，连接房都是先被正确放置，
## 然后下一间房从它的**短边**接进来，长轴上就只剩一个门 —— 穿堂变成了侧岔。
static func _anchor_connector_bonus(ctx: Dictionary, anchor_id: String, anchor_side: String,
		anchor: Dictionary) -> float:
	var deferred := ctx.get("deferred_pools", {}) as Dictionary
	if not deferred.has(anchor_id):
		return 0.0
	var size := _size_of_room(anchor)
	var long_along_y := size.y > size.x
	var side_along_y := str(anchor_side) in ["north", "south"]
	return CONNECTOR_ORIENTATION_BONUS if long_along_y == side_along_y else 0.0


## 某节点可用的候选模板。连接房返回整个池（布局时才定），其余返回唯一那个。
static func _candidate_templates(ctx: Dictionary, node_id: String) -> Array:
	var deferred := ctx.get("deferred_pools", {}) as Dictionary
	if deferred.has(node_id):
		return (deferred[node_id] as Array).duplicate()
	var template_id := str((ctx["node_templates"] as Dictionary).get(node_id, ""))
	return [template_id] if not template_id.is_empty() else []


## 环：从接点出发，两端往中间合。
##
## 原文："loop composites are laid out by adding entries from the loop, alternately at
## either end of a line. To begin with, exit pairs are picked randomly (with preference
## for opposing walls, west-east or north-south). Once the loop is half constructed, it
## starts to prefer exit pairs that bring the two unclosed ends of the loop closer together."
##
## 实现要点：
## - 环的成员**不归树 DFS**（`_dfs_place` 跳过它们），否则环会被拉成一条直线、
##   最后只能靠一条长走廊闭合，等于没做"两端合"。
## - 接点是环与树共享的节点，树 DFS 已铺好它；环从这里向两个方向展开。
## - 后半段（已放置数 > 一半）改为"朝另一侧开口靠"，两端自然靠近。
## - 相遇后两端之间补最后一条边（贴合或走廊），这就是环的闭合。
static func _layout_loop(loop: Dictionary, ctx: Dictionary) -> Dictionary:
	var sequence := (loop["sequence"] as Array).duplicate()
	var rooms := ctx["rooms"] as Dictionary
	var adjacency := ctx["adjacency"] as Dictionary
	var members := {}
	for node_id in sequence:
		members[str(node_id)] = true

	# 接点 = 环与树的共享节点。三种情形：
	#   1. 已在场（根在环上，或树 DFS 走到过）→ 直接用
	#   2. 不在场，但它的某个**环外**邻居已放置 → 先把它贴到那个邻居上
	#      （树 DFS 排除了环成员，所以这一步是必需的，否则环永远找不到落点）
	#   3. 都没有 → 原点自落（重叠则报错，由外层重试兜底）
	var attach_index := -1
	# 已在场的环成员**全部**收进候选，最后从里面抽一个当起点。
	#
	# 环的几何完全由起点决定：固定取"第一个已在场的成员"，24 次重试就是同一张图
	# ——重抽模板也救不回来。实测 flow_05 的 6 节点环 [n05,conn_02,hub_01,n03,n04,n06]
	# 24 轮全部卡在同一条闭合边上。让起点也进 rng，重试才真的在换几何。
	var attach_candidates: Array[int] = []
	for i in range(sequence.size()):
		if rooms.has(str(sequence[i])):
			attach_candidates.append(i)
	if attach_candidates.is_empty():
		# **遍历全部**「环成员 × 它的环外邻居」组合，不能试第一个就 break。
		#
		# 旧版在 for 循环末尾无条件 `break` —— 只试第一个环成员，贴不上就判定
		# 「整个环找不到接点」，然后退回原点自落、撞上已有房间、整轮失败。
		# 实测 flow_01 的环 [hub_02, n05, n06, reward_02] 因此 0/12 全灭：
		# hub_02 的邻居 n04 周围已经放满，但换成 reward_02 的邻居就能贴。
		for i in range(sequence.size()):
			var node_id := str(sequence[i])
			var placed_ok := false
			for value in adjacency.get(node_id, []) as Array:
				var other := str(value)
				if not rooms.has(other) or members.has(other):
					continue
				if bool(_place_child(node_id, other, ctx)["ok"]):
					placed_ok = true
					break
			if placed_ok:
				attach_candidates.append(i)
	if not attach_candidates.is_empty():
		var pick := (ctx["rng"] as RandomNumberGenerator).randi_range(
			0, attach_candidates.size() - 1)
		attach_index = attach_candidates[pick]
	if attach_index < 0:
		# 已经有房间在场、但本环一个接点都贴不上 ⇒ **可能是别的环还没就位**
		# （环之间会互相提供接点）。标成 retryable，交给 `_layout_all` 的迭代重扫；
		# 直接判死会让 flow_01 那种「两个环共用主干」的骨架 100% 失败。
		if not rooms.is_empty():
			return {"ok": false, "retryable": true,
				"error": "环 %s 的接点尚未就位" % str(sequence)}
		attach_index = 0
		var seed_id := str(sequence[0])
		var seed_room := _make_room(seed_id, ctx, Vector2.ZERO)
		if seed_room.is_empty():
			return {"ok": false, "error": "%s 模板缺失" % seed_id}
		if _overlaps_any(seed_room, rooms):
			return {"ok": false, "error": "环 %s 找不到接点，且原点已被占用" % str(sequence)}
		rooms[seed_id] = seed_room
	var attach_id := str(sequence[attach_index])

	var rotated: Array = []
	for i in range(sequence.size()):
		rotated.append(str(sequence[(attach_index + i) % sequence.size()]))

	var total := rotated.size()
	var left := 1
	var right := total - 1
	var left_end := attach_id
	var right_end := attach_id
	var constructed := 1
	# 本轮从哪一侧先长（0 = 先左，1 = 先右）。重试时 rng 前进，起手侧会变。
	var flip := (ctx["rng"] as RandomNumberGenerator).randi_range(0, 1)

	while left <= right:
		# 前半段先往哪侧长是**随机**的（原文 "exit pairs are picked randomly"）。
		# 每轮重试换一个起手侧，形状才会变 —— 固定"先左"会让每次重试都得到
		# 同一个几何，环闭合长度不变，重试 24 次等于重试 1 次。
		# 实测 flow_05 有一个种子就是这样 24 轮全失败、闭合走廊 75m。
		var grow_left := ((constructed + flip) % 2 == 1) or (left_end == right_end)
		# —— 三角环专用：一侧连续长 ——
		#
		# 三条边的小环（A→B→C→A）若按"左右各放一个"来摆，B 挂 A 北侧、C 挂 A 东侧，
		# 最后闭合 B–C 要横跨 A 的对角 —— 实测 47m 走廊，超出原文 4~30。
		# 改成在一侧连续长（A→B→C），C 与 B 相邻，闭合边只剩 C–A，环自然是"紧环"。
		#
		# **这条只对三角环成立**（2026-10-28 修）。旧版无条件生效，于是 4~6 边环
		# 也被拉成一条链，闭合边必然横跨整条链：flow_05 的 5 边环
		# [hub_01→n03→conn_01→n04 … n05] 因此 0/12 全灭。
		# 4 边以上必须**两端交替**长，两端才会保持接近、围成口字形。
		if total <= 3:
			if grow_left and left_end == attach_id and right_end != attach_id:
				grow_left = false
			elif not grow_left and right_end == attach_id and left_end != attach_id:
				grow_left = true
		var node_id := str(rotated[left] if grow_left else rotated[right])
		var anchor_id := left_end if grow_left else right_end
		# 后半段：朝另一侧开口拉近（原文 "bring the two unclosed ends closer together"）
		#
		# 阈值取 `>=` 而不是 `>`：4 节点环后半段只剩 1 次机会（节点 3）时太晚，
		# 前面已经连成一条直线，闭合边只能横跨整条链 —— 实测 flow_01 的
		# [hub_02 → n05 → n06 → reward_02] 闭合边 100m+，直接超原文 30 上限。
		# 从「过半」就开始收（节点 2 起），环才有机会围成口字形而不是长条。
		var toward := Vector2.INF
		if constructed * 2 >= total and left_end != right_end:
			var other_end := right_end if grow_left else left_end
			if rooms.has(other_end):
				toward = (rooms[other_end] as Dictionary)["center"] as Vector2
		var placed := _place_loop_node(node_id, anchor_id, toward, ctx)
		if not bool(placed["ok"]):
			return {"ok": false, "error": str(placed["error"])}
		if grow_left:
			left_end = node_id
			left += 1
		else:
			right_end = node_id
			right -= 1
		constructed += 1

	# 两端相遇：尝试补最后一条边（这是环的闭合）
	#
	# **闭合不上不判死**，留给 `_connect_remaining_edges()` 在总装之后补。
	#
	# 原因是「看不见的未来房间」：环闭合时只有一部分房间在场，若闭合要拉走廊，
	# 走廊的占位检查只能看到**此刻**已有的房间。实测 flow_05 的环边 conn_01–n03
	# 在环阶段补了一条 L 形走廊，而 conn_02 还没放 —— 等 conn_02 落到那条走廊上，
	# 桥接层就报 `room_overlap`（12/120 局）。等到补边阶段时全体房间都在场，
	# 撞房检查才看得全；那一层真接不上会如实报错并触发整轮重排。
	if left_end != right_end:
		_connect_edge(left_end, right_end, ctx)
	return {"ok": true, "error": ""}


static func _place_loop_node(node_id: String, anchor_id: String, toward: Vector2,
		ctx: Dictionary) -> Dictionary:
	var rooms := ctx["rooms"] as Dictionary
	if rooms.has(node_id):
		return {"ok": false, "error": "%s 已被放置" % node_id}
	var anchor := rooms.get(anchor_id, {}) as Dictionary
	if anchor.is_empty():
		return {"ok": false, "error": "锚点 %s 未放置" % anchor_id}
	var pair := _best_pair(node_id, anchor_id, anchor, rooms, ctx, toward)
	if pair.is_empty():
		return {"ok": false, "error": "%s 贴不到 %s 上" % [node_id, anchor_id]}
	var room := pair["room"] as Dictionary
	_commit_port(anchor, str(pair["anchor_side"]), float(pair["anchor_lane"]))
	_commit_port(room, str(pair["child_side"]), float(pair["child_lane"]))
	(room["parents"] as Dictionary)[str(pair["anchor_side"])] = anchor_id
	rooms[node_id] = room
	_record_connection(ctx, anchor_id, str(pair["anchor_side"]), float(pair["anchor_lane"]),
		node_id, str(pair["child_side"]), float(pair["child_lane"]), "direct", 0.0)
	return {"ok": true, "error": ""}


## 两间已定位的房间若**已经共墙**，就把门落在对齐的那一对槽上。
## 这是"前面所有房间都摆好了、最后补连接"时最省的做法（原文优先塞房间而非拉走廊）。
static func _try_direct_close(a_id: String, b_id: String, ctx: Dictionary) -> Dictionary:
	var rooms := ctx["rooms"] as Dictionary
	var room_a := rooms[a_id] as Dictionary
	var room_b := rooms[b_id] as Dictionary
	var delta: Vector2 = (room_b["center"] as Vector2) - (room_a["center"] as Vector2)
	var along_x := absf(delta.x) >= absf(delta.y)
	var a_side := "east"
	var b_side := "west"
	if along_x:
		if delta.x < 0.0:
			a_side = "west"
			b_side = "east"
	else:
		if delta.y >= 0.0:
			a_side = "south"
			b_side = "north"
		else:
			a_side = "north"
			b_side = "south"
	# 必须**枚举两侧空闲 lane 的全部组合**，不能各取第一条就判死。
	#
	# 旧版各取 `_free_lane()` 的第一条，对不上就 `return false` —— 于是退回"补走廊"，
	# 而两房其实已经贴住（共墙），走廊长度算出来是 **0**：桥接层拿到一条 0 长走廊，
	# 实测 120 局里 21 局栽在这里（hub_01 与邻居）。换一条 lane 就能直接对开的边，
	# 被误判成"必须拉走廊"，这是判据太窄，不是布局真的不行。
	var b_center: Vector2 = room_b["center"]
	for a_lane_value in _free_lanes(room_a, a_side):
		for b_lane_value in _free_lanes(room_b, b_side):
			# 两房必须已经贴合：用这对门反算出的位置要和 B 的现位置一致
			var expect := _aligned_center(room_a, a_side, float(a_lane_value),
				_size_of_room(room_b), b_side, float(b_lane_value))
			if expect.distance_to(b_center) > OVERLAP_EPS:
				continue
			_commit_port(room_a, a_side, float(a_lane_value))
			_commit_port(room_b, b_side, float(b_lane_value))
			_record_connection(ctx, a_id, a_side, float(a_lane_value), b_id, b_side,
				float(b_lane_value), "direct", 0.0)
			return {"ok": true}
	return {"ok": false}


# ── 几何 ────────────────────────────────────────────────────────────────────
## 把新房间对齐到已放置房间的一对出口上 —— **整套机制的核心公式**。
##
## `side_a` 侧的门在 `a.center + lane_a`（沿墙轴偏移），`side_b` 侧的门在
## `b.center + lane_b`。令两个门重合，即得 `b.center`。
## 方向约定与 `RoomDoorLane.port_pair()` 一致：north=−z、south=+z、east=+x、west=−x。
##
## `gap` = 两个门之间留出的**走廊长度**。
## `gap = 0` 时两房共墙、门直接对开；`gap > 0` 时两房之间隔一段通道，
## 那一段就是原文说的"地图上多出来的走廊房间"（Boris: "these weird corridor rooms"）。
static func _aligned_center(a: Dictionary, side_a: String, lane_a: float,
		b_size: Vector2, side_b: String, lane_b: float, gap: float = 0.0) -> Vector2:
	var a_center: Vector2 = a["center"]
	var a_size := _size_of_room(a)
	var b_center := a_center
	match side_a:
		"east":
			b_center.x = a_center.x + (a_size.x + b_size.x) * 0.5 + gap
			b_center.y = a_center.y + lane_a - lane_b
		"west":
			b_center.x = a_center.x - (a_size.x + b_size.x) * 0.5 - gap
			b_center.y = a_center.y + lane_a - lane_b
		"south":
			b_center.y = a_center.y + (a_size.y + b_size.y) * 0.5 + gap
			b_center.x = a_center.x + lane_a - lane_b
		"north":
			b_center.y = a_center.y - (a_size.y + b_size.y) * 0.5 - gap
			b_center.x = a_center.x + lane_a - lane_b
	return b_center


static func _make_room(node_id: String, ctx: Dictionary, center: Vector2) -> Dictionary:
	var templates := ctx["templates"] as Dictionary
	# 延迟选模板的节点（连接房）此时还没定，先取池里第一个做落位兜底；
	# 正常流程下它一定由 `_place_child` 放置，这里只服务根节点/孤立节点。
	var template_id := _first_template_for(ctx, node_id)
	if template_id.is_empty() or not templates.has(template_id):
		return {}
	var tpl := templates[template_id] as Dictionary
	return {
		"node_id": node_id,
		"kind": _kind_of(ctx, node_id),
		"template_id": template_id,
		"center": center,
		"size": _size_of(tpl),
		"ports": {},
		"parents": {},
	}


## 节点的房型（`ENTRANCE` / `BOSS` / `HUB` / …）。
##
## 房间字典**必须带它**：下游 `EgtPlanBridge.to_block()` 靠 `room["kind"]` 填
## `room_meta`，`_generate_flow_floor()` 再靠它映射成 role / room_type / content_type。
## 旧版房间字典里没有 `kind`，于是 `room_meta` 全是空串 ⇒ **整层房间都退化成
## `role=main` / `type=COMBAT`**：BOSS 房变普通战斗房、入口失去安全屋身份、
## 撤离点不触发终局。而当时所有断言都通过 —— 因为校验器只在「存在 boss 房」时
## 才要求有 BOSS，全是 main 时它根本不检查。
static func _kind_of(ctx: Dictionary, node_id: String) -> String:
	var nodes := ctx.get("nodes", {}) as Dictionary
	if nodes.has(node_id):
		return str((nodes[node_id] as Dictionary).get("kind", ""))
	return ""


static func _size_of(tpl: Dictionary) -> Vector2:
	var raw: Array = tpl.get("size_m", [0.0, 0.0]) as Array
	if raw.size() < 2:
		return Vector2.ZERO
	return Vector2(float(raw[0]), float(raw[1]))


static func _size_of_template(ctx: Dictionary, node_id: String) -> Vector2:
	var templates := ctx["templates"] as Dictionary
	var template_id := _first_template_for(ctx, node_id)
	if not templates.has(template_id):
		return Vector2.ZERO
	return _size_of(templates[template_id] as Dictionary)


static func _first_template_for(ctx: Dictionary, node_id: String) -> String:
	var candidates := _candidate_templates(ctx, node_id)
	return str(candidates[0]) if not candidates.is_empty() else ""


static func _size_of_room(room: Dictionary) -> Vector2:
	return room.get("size", Vector2.ZERO) as Vector2


static func _rect_of(room: Dictionary) -> Rect2:
	var size := _size_of_room(room)
	var center: Vector2 = room["center"]
	return Rect2(center - size * 0.5, size)


## 共墙贴合（交集面积为 0）不算重叠；真正交叠才算。
static func _overlaps_any(room: Dictionary, rooms: Dictionary) -> bool:
	var rect := _rect_of(room)
	for value in rooms.values():
		var other := value as Dictionary
		if other.is_empty():
			continue
		var inter := rect.intersection(_rect_of(other))
		if inter.size.x > OVERLAP_EPS and inter.size.y > OVERLAP_EPS:
			return true
	return false


static func _distance_score(room: Dictionary, rooms: Dictionary) -> float:
	var center: Vector2 = room["center"]
	var best := INF
	for value in rooms.values():
		var other := value as Dictionary
		if other.is_empty():
			continue
		best = minf(best, center.distance_to(other["center"] as Vector2))
	return 0.0 if is_inf(best) else best


## 新房间到"其他已放房间"的最近距离（排除它自己的锚点，锚点必然紧贴）。
##
## 越大 = 越往空白处生长 = 越不容易被楼群夹住。这就是原文的"偏好离已有房间远的出口"。
static func _spread_score(room: Dictionary, rooms: Dictionary, anchor_id: String) -> float:
	var center: Vector2 = room["center"]
	var best := 120.0
	for value in rooms.values():
		var other := value as Dictionary
		if other.is_empty() or str(other.get("node_id", "")) == anchor_id:
			continue
		best = minf(best, center.distance_to(other["center"] as Vector2))
	return best


## 某侧还没被占用的门槽（与 `RoomDoorLane.lane_offsets()` 同源）。
static func _free_lane(room: Dictionary, side: String) -> float:
	var size := _size_of_room(room)
	var length := size.x if side in ["north", "south"] else size.y
	if length <= 0.0:
		return NAN
	var used_raw: Array = (room["ports"] as Dictionary).get(side, []) as Array
	var door_width := float((room.get("door_contract", {}) as Dictionary).get("width_m", 2.2))
	for lane in ROOM_DOOR_LANE.lane_offsets(length):
		var taken := false
		for value in used_raw:
			if absf(float(lane) - float(value)) < door_width + 0.4:
				taken = true
				break
		if not taken:
			return float(lane)
	return NAN


## 某侧**全部**空闲门槽（`_free_lane` 只取第一个，组装需要遍历所有候选）。
static func _free_lanes(room: Dictionary, side: String) -> Array:
	var size := _size_of_room(room)
	var length := size.x if side in ["north", "south"] else size.y
	if length <= 0.0:
		return []
	var used_raw: Array = (room["ports"] as Dictionary).get(side, []) as Array
	var door_width := float((room.get("door_contract", {}) as Dictionary).get("width_m", 2.2))
	var out: Array = []
	for lane in ROOM_DOOR_LANE.lane_offsets(length):
		var taken := false
		for value in used_raw:
			if absf(float(lane) - float(value)) < door_width + 0.4:
				taken = true
				break
		if not taken:
			out.append(float(lane))
	return out


## 某个**具体模板**在某一面的合法门槽（直接读它的 `wall_lane_table`）。
## 不传 node_id 是因为连接房的模板要到布局时才定，此时 `node_templates` 里还是空的。
static func _candidate_lanes(templates: Dictionary, template_id: String, side: String) -> Array:
	if not templates.has(template_id):
		return []
	var lanes_raw: Dictionary = (templates[template_id] as Dictionary).get("wall_lane_table", {})
	var out: Array = []
	for value in lanes_raw.get(side, []) as Array:
		out.append(float(value))
	return out


static func _commit_port(room: Dictionary, side: String, lane: float) -> void:
	var ports: Dictionary = room["ports"]
	var list: Array = ports.get(side, []) as Array
	list.append(lane)
	ports[side] = list


static func _nearest_open_side(room: Dictionary, direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "east" if direction.x >= 0.0 else "west"
	return "south" if direction.y >= 0.0 else "north"


static func _root_of(flow: Dictionary) -> String:
	for value in flow.get("nodes", []) as Array:
		var node := value as Dictionary
		if str(node.get("kind", "")) == "ENTRANCE":
			return str(node.get("node_id", ""))
	var nodes := flow.get("nodes", []) as Array
	return str((nodes[0] as Dictionary).get("node_id", "")) if not nodes.is_empty() else ""


static func _root_of_graph(nodes: Dictionary, tree_edges: Array) -> String:
	for node_id in nodes:
		if str((nodes[node_id] as Dictionary).get("kind", "")) == "ENTRANCE":
			return str(node_id)
	return str((tree_edges[0] as Dictionary)["from"]) if not tree_edges.is_empty() else ""


static func _dead_ends(nodes: Dictionary, edges: Array, root_id: String) -> Array:
	var degree := {}
	for node_id in nodes:
		degree[str(node_id)] = 0
	for value in edges:
		var edge := value as Dictionary
		degree[str(edge["from"])] = int(degree.get(str(edge["from"]), 0)) + 1
		degree[str(edge["to"])] = int(degree.get(str(edge["to"]), 0)) + 1
	var out: Array = []
	for node_id in degree:
		if int(degree[node_id]) == 1 and str(node_id) != root_id:
			out.append(str(node_id))
	out.sort()
	return out


static func _tree_path(adjacency: Dictionary, start: String, goal: String) -> Array:
	if start == goal:
		return []
	var prev := {start: ""}
	var queue: Array = [start]
	while not queue.is_empty():
		var current := str(queue.pop_front())
		for value in adjacency.get(current, []) as Array:
			var nxt := str(value)
			if prev.has(nxt):
				continue
			prev[nxt] = current
			if nxt == goal:
				var path: Array = [goal]
				var cursor := goal
				while str(prev[cursor]) != "":
					cursor = str(prev[cursor])
					path.push_front(cursor)
				return path
			queue.append(nxt)
	return []


# ── 校验 ────────────────────────────────────────────────────────────────────
## 每条边都要有门位落上，并且**两个门的绝对坐标必须重合**。
##
## 为什么不用 `RoomDoorLane.port_pair()` 反算：它的语义是「已知两房位置，推荐一对最优门槽」，
## 会从交集里挑最接近中线的那个；而拼装是反过来的「先选门槽、再定位置」。
## 实测 192 个组合里有 44 个不一致 —— 那是语义不同，不是 bug。
## 所以校验直接验拼装事实：记录下来的 (side, lane) 换算成世界坐标，看是否同一点。
static func _verify_edges(graph: Dictionary, rooms: Array, connections: Array) -> Dictionary:
	var by_id := {}
	for value in rooms:
		var room := value as Dictionary
		by_id[str(room["node_id"])] = room
	var errors: Array = []
	var out: Array = []

	for value in connections:
		var conn := value as Dictionary
		var a := str(conn["a_id"])
		var b := str(conn["b_id"])
		if not by_id.has(a) or not by_id.has(b):
			errors.append("连接 %s-%s 端点缺失" % [a, b])
			continue
		var room_a := by_id[a] as Dictionary
		var room_b := by_id[b] as Dictionary
		var a_side := str(conn["a_side"])
		var b_side := str(conn["b_side"])
		var a_lane := float(conn["a_lane"])
		var b_lane := float(conn["b_lane"])

		if str(SIDE_OPPOSITE.get(a_side, "")) != b_side:
			errors.append("连接 %s-%s: 两侧不相向（%s vs %s）" % [a, b, a_side, b_side])

		var gate_a := _gate_position(room_a, a_side, a_lane)
		var gate_b := _gate_position(room_b, b_side, b_lane)
		var gap := gate_a.distance_to(gate_b)
		var kind := str(conn.get("kind", "direct"))
		var corridor_len := float(conn.get("corridor_length_m", 0.0))
		if kind == "corridor":
			# 走廊连接的语义：这条走廊就是连接这两扇门的通道。
			# 1) 长度必须盖得住门距（不能短于实际缺口）
			if corridor_len + 0.01 < gap:
				errors.append("连接 %s-%s: 走廊 %.0fm 盖不住门距 %.2fm" % [
					a, b, corridor_len, gap])
			# 2) 长度必须落在原文区间内 —— 原文："The corridor must be between
			#    4 and 30 units long (50 in the mines)."
			#    这一条专盯旧版那个 70m 长蛇：当时环被 DFS 拉直，最后只能拉一条
			#    穿越大半张图的走廊闭合。走廊过长就说明环没被正确"两端合"。
			if corridor_len > CORRIDOR_HARD_MAX_M:
				errors.append("连接 %s-%s: 走廊 %.0fm 超出原文上限 %.0fm（说明环被拉直了）" % [
					a, b, corridor_len, CORRIDOR_HARD_MAX_M])
			if corridor_len < CORRIDOR_HARD_MIN_M - 0.01:
				errors.append("连接 %s-%s: 走廊 %.1fm 短于原文下限 %.0fm" % [
					a, b, corridor_len, CORRIDOR_HARD_MIN_M])
		elif gap > 0.01:
			errors.append(
				"连接 %s-%s: 门差 %.2fm | A(%s %s@%.1f c=%.1f,%.1f s=%.0f,%.0f ports=%s) "
				% [a, b, gap, str(room_a["template_id"]), a_side, a_lane,
					(room_a["center"] as Vector2).x, (room_a["center"] as Vector2).y,
					(room_a["size"] as Vector2).x, (room_a["size"] as Vector2).y,
					str(room_a["ports"])]
				+ "B(%s %s@%.1f c=%.1f,%.1f s=%.0f,%.0f ports=%s)" % [
					str(room_b["template_id"]), b_side, b_lane,
					(room_b["center"] as Vector2).x, (room_b["center"] as Vector2).y,
					(room_b["size"] as Vector2).x, (room_b["size"] as Vector2).y,
					str(room_b["ports"])])
		out.append({
			"from": a, "to": b, "kind": kind,
			"a_side": a_side, "a_lane": a_lane,
			"b_side": b_side, "b_lane": b_lane,
			"gate": gate_a,
			"gap_m": gap,
			"corridor_length_m": corridor_len,
			"port_verified": (gap <= 0.01) if kind == "direct" else (corridor_len + 0.01 >= gap),
		})

	# 图上每条边都必须有对应连接（注入边也一样）——防"放了房间却没接门"
	var connected := {}
	for value in connections:
		var conn := value as Dictionary
		connected[_edge_key(str(conn["a_id"]), str(conn["b_id"]))] = true
	for value in graph["edges"] as Array:
		var edge := value as Dictionary
		var key := _edge_key(str(edge["from"]), str(edge["to"]))
		if not connected.has(key):
			errors.append("边 %s-%s 没有落门" % [str(edge["from"]), str(edge["to"])])

	return {"ok": errors.is_empty(), "error": "; ".join(errors), "edges": out}


## 门在世界坐标里的位置：沿墙轴取 `center + lane`，另一轴贴墙线。
static func _gate_position(room: Dictionary, side: String, lane: float) -> Vector2:
	var center: Vector2 = room["center"]
	var size := _size_of_room(room)
	match side:
		"north":
			return Vector2(center.x + lane, center.y - size.y * 0.5)
		"south":
			return Vector2(center.x + lane, center.y + size.y * 0.5)
		"west":
			return Vector2(center.x - size.x * 0.5, center.y + lane)
		"east":
			return Vector2(center.x + size.x * 0.5, center.y + lane)
	return center


static func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


## 记一条拼装事实。`kind` 有兩種：
## - `"direct"`：两房共墙、门直接对齐（门的绝对坐标必须重合）
## - `"corridor"`：中间补了走廊（两个门相距 = 走廊长度，**不应重合**）
static func _record_connection(ctx: Dictionary, a_id: String, a_side: String, a_lane: float,
		b_id: String, b_side: String, b_lane: float,
		kind: String = "direct", corridor_length: float = 0.0) -> void:
	(ctx["connections"] as Array).append({
		"a_id": a_id, "a_side": a_side, "a_lane": a_lane,
		"b_id": b_id, "b_side": b_side, "b_lane": b_lane,
		"kind": kind, "corridor_length_m": corridor_length,
	})


static func _has_lane(lanes: Array, lane: float) -> bool:
	for value in lanes:
		if absf(float(value) - lane) <= 0.01:
			return true
	return false


static func _fail(message: String, diagnostics: Dictionary) -> Dictionary:
	return {"ok": false, "error": message, "rooms": [], "edges": [],
		"corridors": [], "loops": [], "diagnostics": diagnostics}
