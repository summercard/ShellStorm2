extends GPUParticles2D

func _ready() -> void:
	one_shot = true
	emitting = true
	# 爆炸扩散后自动 free（粒子自然消散）
	var timer := Timer.new()
	timer.wait_time = 1.5
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()