class_name UiMenuFocus
extends RefCounted
## 覆盖式菜单的初始焦点统一入口。
##
## 起因：鼠标点击不需要「焦点」这个概念，但手柄不行 —— Godot 的
## ui_up / ui_down / ui_left / ui_right（十字键与左摇杆）和 ui_accept（A 键）
## 都必须先存在一个 gui focus owner 才会被派发。基地设施菜单此前只建控件、
## 从不抓焦点，于是手柄一进任何子界面就整体失灵（远征情报室最先被发现）。
##
## 默认焦点取「返回 / 放弃类按钮」而不是树序第一个 Button：
## 菜单刚打开、玩家还没看清界面时按下的那个 A 键，触发的必须是安全动作。
## 树序第一个往往是「解锁 / 购买 / 传送 / 恢复」这类有副作用的按钮，
## 误触代价太高；返回按钮在任何菜单里都存在且永远无副作用。
## 一个都没找到时才退化为树序第一个可聚焦控件。
##
## 名字按作用排序：先找返回，再找放弃（命运卡牌菜单没有返回，只有跳过）。
const SAFE_DEFAULT_FOCUS_NAMES: Array[String] = ["CloseButton", "SkipButton"]
##
## 注意：ui_accept 在 project.godot 里只绑了 Enter / 小键盘 Enter（没绑空格），
## 而空格属于 interact。所以「默认焦点 + 回车」不会误触发基地交互。


## 给刚建好的菜单抓一个初始焦点。返回被选中的控件，无可用目标时返回 null。
static func ensure_focus(menu: Node) -> Control:
	var target := find_default_focus(menu)
	if target == null:
		return null
	target.grab_focus()
	return target


## 默认焦点：优先返回/放弃类按钮，其次树序第一个可聚焦控件。
static func find_default_focus(menu: Node) -> Control:
	if menu == null or not is_instance_valid(menu):
		return null
	for candidate_name in SAFE_DEFAULT_FOCUS_NAMES:
		# owned = false：这些菜单的按钮大多是代码 new 出来的，owner 为空，
		# 用默认的 owned = true 会一个都找不到。
		var named := menu.find_child(candidate_name, true, false)
		if is_focusable(named):
			return named as Control
	return find_first_focusable(menu)


## 深度优先找第一个「手柄能停上去」的控件。
static func find_first_focusable(root: Node) -> Control:
	if root == null or not is_instance_valid(root):
		return null
	for child in root.get_children():
		if is_focusable(child):
			return child as Control
		var nested := find_first_focusable(child)
		if nested != null:
			return nested
	return null


## 手柄能否把焦点停在它上面。禁用按钮也算可聚焦（引擎允许），
## 但停上去毫无意义，所以这里一并排除。
static func is_focusable(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Control):
		return false
	var control := node as Control
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if not control.is_visible_in_tree():
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


## 收集菜单里所有可聚焦控件。验收脚本用它核对「焦点有去处」。
static func collect_focusable(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	_collect_focusable(root, found)
	return found


static func _collect_focusable(root: Node, found: Array[Control]) -> void:
	if root == null or not is_instance_valid(root):
		return
	for child in root.get_children():
		if is_focusable(child):
			found.append(child as Control)
		_collect_focusable(child, found)
