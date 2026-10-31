extends CharacterBody3D

## 探针用的**假玩家**：只提供 AI 侧会读的那几个字段与接口。
##
## 为什么不用真 `Player3D`：真玩家会带入相机、武器树、命运卡、输入映射与 `_process`
## 里的一整套表现逻辑 —— 测 AI 节奏时那些全是噪声（而且相机抢占 `current` 会让
## headless 下的 `look_at` 行为变）。
##
## 需要提供的字段由消费方决定，逐条对照过：
##   `current_hp` —— `MonsterAIManager._target_is_legal()` / `MonsterVisionSystem3D.find_proximity_player()`
##   都是 `float(target.get("current_hp")) <= 0` 判死的。**缺这个属性会抛
##   「Nonexistent 'float' constructor」并让目标恒非法**（第一次跑就是栽在这）。
##   `take_damage()` —— 怪的接触/弹丸结算会调它，缺了会报 method not found。

var current_hp := 100
var max_hp := 100
## 节拍器/记录用的房间标识。真玩家由所在房间写入，探针里手动给。
var room_id := ""


func take_damage(
	_amount: int, _critical := false, _direction := Vector3.ZERO,
	_knockback := false, _knockback_strength := 0.0
) -> void:
	pass


func notify_attacked_by(_enemy: Node) -> void:
	pass
