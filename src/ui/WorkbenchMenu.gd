class_name WorkbenchMenu
extends CanvasLayer
## 武器改造台的**设施入口包装层**。
##
## `WorkbenchPanel` 是纯 `Control`（自己铺满视口、自己处理 ESC、关闭时 `queue_free`），
## 而 `TowerDescent3D._open_facility_menu()` 的契约是「实例化一个 `CanvasLayer`，
## 依次调 `set_inventory_module` / `set_player` / `set_facility`，再 `add_child`」。
## 两边对不上，所以需要这一层 12 行的适配。
##
## ## 为什么是包装层而不是把 WorkbenchPanel 改成 CanvasLayer
##
## - 面板被 `verify_synthesis_catalog` / `verify_synthesis_gate` 直接 `new()` 挂在
##   普通 `Node` 下跑，`Control` 才能用 `_fit_to_viewport()` 拿到视口矩形；
##   改成 CanvasLayer 会连带改掉那两条验收的搭建方式，而它们验的是规则与表现，不是入口。
## - 入口形态（CanvasLayer）与功能本体（Control）是两件事。基地里以后再加第二个
##   改造台（比如移动工坊）时，换个包装层就能接，不用碰功能。
##
## ## 时序契约
##
## `_open_facility_menu()` 在 `add_child(menu)` **之前**调 `set_*`，
## 所以三个 setter 只能存字段，真正转发发生在 `_ready()`。
## 面板的 `_ready` 里会 `_resolve_inventory()`，那时 `get_inventory_module()` 必须已经能返回。
##
## ## 关闭
##
## 面板 ESC / 点关闭 → `closed` → 本层 `queue_free` → `tree_exited`
## → `TowerDescent3D._on_active_facility_menu_closed()` 清引用并解锁输入。
## 面板自己的 `_exit_tree()` 负责 `player.set_input_locked(false)`。

## 由 `_open_facility_menu` 在 add_child 前调用。
var _player: Player3D = null
var _inventory: InventoryModule = null
var _facility: BaseFacility3D = null
var _panel: WorkbenchPanel = null
## 打开期间被让位的基地 HUD。与衣柜菜单同一套做法（`WardrobeMenu3D._hide_gameplay_hud`）。
var _gameplay_hud: CanvasLayer = null
var _gameplay_hud_was_visible := true


func set_player(player: Player3D) -> void:
	_player = player


func set_inventory_module(module: InventoryModule) -> void:
	_inventory = module


func set_facility(facility: BaseFacility3D) -> void:
	_facility = facility


## `WorkbenchPanel._resolve_inventory()` 认这个接口 —— 面板只关心"背包从哪来"，
## 不关心宿主是基地设施还是局内工作台。
func get_inventory_module() -> InventoryModule:
	return _inventory


func get_panel() -> WorkbenchPanel:
	return _panel


func _ready() -> void:
	_hide_gameplay_hud()
	_panel = WorkbenchPanel.new()
	_panel.name = "WorkbenchPanel"
	# 面板通过 `_workbench_ref` 反查背包；传自己，而不是传 TowerDescent3D ——
	# 面板拿到的是一份明确的依赖，换成别的宿主时不用改面板。
	_panel.set_workbench_ref(self)
	if _player != null and is_instance_valid(_player):
		_panel.set_player(_player)
	_panel.closed.connect(_on_panel_closed)
	add_child(_panel)


## 让基地 HUD 退场。
##
## 改造台的遮罩是 `PRISM_DIM`（alpha 0.58，刻意让 3D 实景仍可见），
## 基地 HUD 是**另一个 CanvasLayer**、层号与菜单相同 —— 它不会被遮罩盖住，
## 而是隔着 0.58 的底色与面板叠在一起：左边一条血条、中间一块炼炉、
## 右下角一个金币数，读起来不是"两个界面"而是"界面坏了"。
##
## 衣柜菜单早就是这么做的（`WardrobeMenu3D._hide_gameplay_hud`），这里沿用同一套。
func _hide_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud):
		return
	var owner := get_parent()
	if owner == null:
		return
	_gameplay_hud = owner.get_node_or_null("HUD") as CanvasLayer
	if _gameplay_hud == null:
		return
	_gameplay_hud_was_visible = _gameplay_hud.visible
	_gameplay_hud.visible = false


func _restore_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud):
		_gameplay_hud.visible = _gameplay_hud_was_visible
	_gameplay_hud = null


func _on_panel_closed() -> void:
	_restore_gameplay_hud()
	if is_instance_valid(self):
		queue_free()


## 兜底：菜单被外部摘掉（场景切换 / 强制卸载）而面板没走 `closed` 时，
## HUD 也必须回来。少了这一条，玩家会回到一个"什么都没有"的基地。
func _exit_tree() -> void:
	_restore_gameplay_hud()
