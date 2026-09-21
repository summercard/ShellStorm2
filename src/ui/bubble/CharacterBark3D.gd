class_name CharacterBark3D
extends Node3D
## 角色"开口说话"的挂载点：把 [BarkCatalog] 的短句送到头顶 [SpeechBubble3D]。
##
## 职责边界（供剧情系统调用时的契约）：
##   - 它**不决定**什么时候该说话（那是调用方的判断），只负责"说出来"。
##   - 它**不持有**剧情状态，也不知道剧情进度。
##   - 它不认识 Player3D / Enemy3D 的任何私有字段，只挂在谁的下面就说谁的话。
##
## 朝向与位置：本节点只承担**纯垂直偏移**（default 头顶正上方）。因为偏移不含水平
## 分量，父角色绕 Y 轴转身不会改变气泡位置；而气泡自身用 BILLBOARD_ENABLED 面向
## 摄像机，所以"全程对着摄像机、不随角色转动"两件事都不需要每帧代码。

const DEFAULT_HEAD_HEIGHT := 2.15

## 气泡挂高。**只使用垂直分量** —— 偏移不含水平分量，所以角色绕 Y 轴转身不会带动
## 气泡位移。这是"不随角色转动"的位置侧保证（朝向侧由 BILLBOARD_ENABLED 保证）。
@export var head_height := DEFAULT_HEAD_HEIGHT
@export var hold_seconds := 3.4
@export var enabled := true

var _bubble: SpeechBubble3D
var _rng := RandomNumberGenerator.new()
var _last_index := {}


func _ready() -> void:
	position = Vector3(0.0, head_height, 0.0)
	_ensure_bubble()
	_rng.randomize()


## 便捷挂载：把说话能力装到任意角色节点上。
static func attach_to(actor: Node3D, height := 2.15) -> CharacterBark3D:
	if actor == null:
		return null
	var existing := actor.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if existing != null:
		return existing
	var bark := CharacterBark3D.new()
	bark.name = "CharacterBark3D"
	bark.head_height = height
	actor.add_child(bark)
	return bark


func get_bubble() -> SpeechBubble3D:
	_ensure_bubble()
	return _bubble


## 说一句随机短句；相同 bark_id 不会连续抽到同一句。
func say_bark(bark_id: String, hold := -1.0) -> bool:
	if not enabled:
		return false
	if not BarkCatalog.has_bark(bark_id):
		push_warning("CharacterBark3D: 未知的 bark_id 『%s』，本句被忽略。" % bark_id)
		return false
	var picked := BarkCatalog.pick_random(bark_id, _rng, int(_last_index.get(bark_id, -1)))
	_last_index[bark_id] = picked["index"]
	_ensure_bubble()
	if _bubble == null:
		return false
	_bubble.say(str(picked["text"]), hold if hold >= 0.0 else hold_seconds)
	return true


## 确定性取句（验收用）：固定取第 index 句。
func say_bark_at(bark_id: String, index: int, hold := -1.0) -> bool:
	if not BarkCatalog.has_bark(bark_id):
		push_warning("CharacterBark3D: 未知的 bark_id 『%s』。" % bark_id)
		return false
	_ensure_bubble()
	if _bubble == null:
		return false
	_bubble.say(BarkCatalog.pick_at(bark_id, index), hold if hold >= 0.0 else hold_seconds)
	return true


## 直接说一段文本（不走目录）；剧情系统要念固定台词时用这个。
func say_text(text: String, hold := -1.0) -> bool:
	_ensure_bubble()
	if _bubble == null:
		return false
	_bubble.say(text, hold if hold >= 0.0 else hold_seconds)
	return true


func hide_now() -> void:
	if _bubble != null:
		_bubble.hide_bubble()


func is_speaking() -> bool:
	return _bubble != null and _bubble.is_bubble_active()


func get_current_text() -> String:
	return _bubble.get_bubble_text() if _bubble != null else ""


func _ensure_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		return
	_bubble = get_node_or_null("SpeechBubble") as SpeechBubble3D
	if _bubble == null:
		_bubble = SpeechBubble3D.new()
		_bubble.name = "SpeechBubble"
		add_child(_bubble)
