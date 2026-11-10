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

## 示意框的挂高（米）。
##
## 为什么不能沿用 `head_height`：那个值是按**两行文字气泡**（高 1.21m）定的，
## 中心 3.40m 才能让气泡底边离头顶 0.23m。现在示意框只有 0.46m 高，
## 继续挂在 3.40m 就成了飘在半空的一个孤零零小框。
## 1.86m ≈ 绿苔头顶 1.215m + 0.25m 间隙 + 半高 0.23m。
const DEFAULT_INDICATOR_HEIGHT := 1.86
@export var indicator_head_height := DEFAULT_INDICATOR_HEIGHT

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
	_restore_text_height()
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
	_restore_text_height()
	_bubble.say(BarkCatalog.pick_at(bark_id, index), hold if hold >= 0.0 else hold_seconds)
	return true


## 直接说一段文本（不走目录）；剧情系统要念固定台词时用这个。
func say_text(text: String, hold := -1.0) -> bool:
	_ensure_bubble()
	if _bubble == null:
		return false
	_restore_text_height()
	_bubble.say(text, hold if hold >= 0.0 else hold_seconds)
	return true


## ── 说话示意（对话专用）──────────────────────────────────────────────
##
## 业主 2026-11-10：头顶只做「正在说话」的示意，文字统一走底栏；
## 但「开灯这类自言自语」要保留原来的文字气泡。
## 所以本节点同时提供两个入口，由调用方按语义选，不在这里猜：
##   · `say_text()`      —— 自言自语，气泡里写字。
##   · `say_indicator()` —— 对话，只出示意框。
func say_indicator(hold := -1.0, height := -1.0) -> bool:
	_ensure_bubble()
	if _bubble == null:
		return false
	var want := height if height >= 0.0 else indicator_head_height
	position = Vector3(0.0, want, 0.0)
	_bubble.say_indicator(hold if hold >= 0.0 else hold_seconds)
	return true


func is_indicator_active() -> bool:
	return _bubble != null and _bubble.is_indicator_only()


## 示意框还在，但里面的字不算数 —— 验收用它区分两种形态。
func is_speaking_any() -> bool:
	return _bubble != null and _bubble.is_bubble_active()


func _restore_text_height() -> void:
	position = Vector3(0.0, head_height, 0.0)


func hide_now() -> void:
	if _bubble != null:
		_bubble.hide_bubble()


func is_speaking() -> bool:
	return _bubble != null and _bubble.is_bubble_active()


func get_current_text() -> String:
	return _bubble.get_bubble_text() if _bubble != null else ""


## 打字机相关（2026-11-08 业主：对话文字要像打字机一样顺序出现）。
## 全都转给 `SpeechBubble3D`，本节点不持有第二份进度。

## 这句话是不是还在逐字往外冒。示意框永远不会逐字打，返回 false。
func is_typing() -> bool:
	return _bubble != null and _bubble.is_typing()


## 已显示的字数 / 整句字数 —— 验收用（证明真的是一字一字出来的）。
func get_visible_char_count() -> int:
	return _bubble.get_visible_char_count() if _bubble != null else 0


func get_total_char_count() -> int:
	return _bubble.get_total_char_count() if _bubble != null else 0


## 立刻显示整句（说话时按 E 跳过打字机）。
func reveal_all() -> void:
	if _bubble != null:
		_bubble.reveal_all()


## 只压缩当前句的文字停留，不改变气泡内容或全局剧情时钟。
func compress_hold_to_next() -> bool:
	return _bubble != null and _bubble.compress_hold_to_next()


func current_sentence_id() -> int:
	return _bubble.current_sentence_id() if _bubble != null else -1

func _ensure_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		return
	_bubble = get_node_or_null("SpeechBubble") as SpeechBubble3D
	if _bubble == null:
		_bubble = SpeechBubble3D.new()
		_bubble.name = "SpeechBubble"
		add_child(_bubble)
