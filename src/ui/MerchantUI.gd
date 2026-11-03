class_name MerchantUI
extends Control
## 局内商人适配器：与99F共用贩卖机页面，交易仍由 RunMerchantService 拥有。

signal purchase_command_requested(session_id: String, offer_id: String, weapon_instance_id: String)
signal merchant_closed()

const MENU := preload("res://scenes/BaseVendingMenu.tscn")

@export var inventory_tier: int = 1
@export var shop_name: String = "贩卖机"

var _session_id := ""
var _offers: Array[Dictionary] = []
var _inventory: InventoryModule
var _menu: BaseVendingMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	GameManager.currency_changed.connect(_on_currency_changed)


func set_tier(tier: int) -> void:
	inventory_tier = tier


func set_shop_name(title: String) -> void:
	shop_name = title


func set_inventory_module(module: InventoryModule) -> void:
	_inventory = module
	if _inventory != null and not _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.connect(_refresh)


func show_offers(session_id: String, offers: Array[Dictionary]) -> void:
	_session_id = session_id
	_offers = offers.duplicate(true)
	if _menu == null:
		_menu = MENU.instantiate() as BaseVendingMenu
		_menu.configure_run_shop(_inventory, shop_name)
		_menu.present_run_offers(_offers, GameManager.currency)
		_menu.run_purchase_requested.connect(_on_purchase_requested)
		_menu.run_shop_closed.connect(hide_merchant)
		add_child(_menu)
	visible = true
	_refresh()


func update_offers(offers: Array[Dictionary]) -> void:
	_offers = offers.duplicate(true)
	_refresh()


func show_purchase_result(message: String) -> void:
	if is_instance_valid(_menu):
		_menu.show_run_result(message)


func hide_merchant() -> void:
	if not visible:
		return
	visible = false
	if is_instance_valid(_menu):
		_menu.hide()
		_menu.queue_free()
	_menu = null
	merchant_closed.emit()


func _on_currency_changed(_amount: int) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_menu):
		return
	_menu.present_run_offers(_offers, GameManager.currency)


func _on_purchase_requested(offer_id: String, weapon_instance_id: String) -> void:
	purchase_command_requested.emit(_session_id, offer_id, weapon_instance_id)


## 保留命令入口供事务专项使用；鼠标和手柄均通过页面上的购买按钮进入。
func _on_slot_clicked(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	var offer := _offers[index]
	var item := offer.get("item", {}) as Dictionary
	_on_purchase_requested(str(offer.get("offer_id", "")), str(item.get("weapon_instance_id", "")))
