extends Node

class_name SynthSfx

# SynthSfx — 程序化合成音效（解决音频文件缺失问题）
# 提供：射击、击中、暴击、换弹、撤离等关键音效
# 无需外部音频文件，纯程序生成

var _stream_player: AudioStreamPlayer = null

func _ready() -> void:
	_stream_player = AudioStreamPlayer.new()
	_stream_player.bus = "SFX"
	add_child(_stream_player)


func _exit_tree() -> void:
	# 合成 WAV 是运行时资源；显式断开播放句柄，避免快速切场景/无头验证
	# 在 AudioServer 回收前仍保留 AudioStreamPlaybackWAV 引用。
	if _stream_player != null and is_instance_valid(_stream_player):
		_stream_player.stop()
		_stream_player.stream = null

## 播放射击音效
func play_shoot(fire_rate: float, projectile_count: int) -> void:
	var freq := 220.0 if fire_rate < 5.0 else (280.0 if fire_rate < 10.0 else 350.0)
	var duration := 0.05 if projectile_count < 5 else 0.09
	var stream := _make_square_wave(freq, duration, -6.0)
	_play_stream(stream)

## 播放击中音效
func play_hit() -> void:
	var stream := _make_noise_burst(0.07, -10.0, 1200.0, 150.0)
	_play_stream(stream)

## 播放暴击音效
func play_crit() -> void:
	var s1 := _make_square_wave(880.0, 0.08, -4.0)
	var s2 := _make_noise_burst(0.12, -6.0, 3000.0, 300.0)
	var mixed := _mix_two(s1, s2, 0.7, 0.5)
	_play_stream(mixed)

## 播放命运卡片应用音效
## 上升琶音 + 和声，暗示"命运降临、力量改变"
func play_fate_card() -> void:
	var notes := [261.63, 329.63, 392.0, 523.25, 659.25]
	var stream := _make_arpeggio_up(notes, 0.10, -6.0)
	_play_stream(stream)

## 播放换弹音效
func play_reload() -> void:
	var stream := _make_metallic(0.22, -8.0)
	_play_stream(stream)

## 播放撤离开始音效
func play_extraction_start() -> void:
	var s1 := _make_square_wave(110.0, 0.35, -6.0)
	var s2 := _make_square_wave(165.0, 0.35, -8.0)
	var mixed := _mix_two(s1, s2, 0.8, 0.6)
	_play_stream(mixed)

## 播放撤离成功音效
func play_extraction_done() -> void:
	var notes := [261.63, 329.63, 392.0, 523.25]
	var stream := _make_arpeggio(notes, 0.12, -4.0)
	_play_stream(stream)

## 播放撤离中断音效
## 短促降频噪声：下降的嘣声，表示"被打断"
func play_extraction_abort() -> void:
	var stream := _make_noise_burst(0.16, -8.0, 900.0, 60.0)
	_play_stream(stream)

## 播放敌人死亡音效
func play_enemy_die() -> void:
	var stream := _make_noise_burst(0.14, -8.0, 2000.0, 80.0)
	_play_stream(stream)

## 播放玩家受伤音效
func play_player_hit() -> void:
	var stream := _make_noise_burst(0.09, -7.0, 800.0, 60.0)
	_play_stream(stream)

## 播放闪避音效
func play_dash() -> void:
	var freq := 500.0 + randf_range(-80.0, 80.0)
	var stream := _make_square_wave(freq, 0.07, -12.0)
	_play_stream(stream)

## ========== 核心合成器 ==========

func _play_stream(stream: AudioStream) -> void:
	if _stream_player == null or not is_instance_valid(_stream_player):
		return
	# 单通道合成器以最新战斗提示为准；先断开旧播放实例，避免高频状态切换时
	# 旧 WAV playback 继续持有运行时资源。
	_stream_player.stop()
	_stream_player.stream = null
	_stream_player.stream = stream
	_stream_player.pitch_scale = 1.0 + randf_range(-0.04, 0.04)
	_stream_player.play()

func _make_square_wave(freq: float, duration: float, volume_db: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase := 0.0
	var phase_inc := freq / sample_rate
	var amp := db_to_linear(volume_db)
	for i in num_samples:
		var sample := 1.0 if phase < 0.5 else -1.0
		phase += phase_inc
		if phase >= 1.0:
			phase -= 1.0
		var s16 := int(sample * amp * 32767.0 * 0.8)
		s16 = clampi(s16, -32768, 32767)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = 2
	stream.data = data
	stream.mix_rate = sample_rate
	return stream

func _make_noise_burst(duration: float, volume_db: float, lp_freq: float, hp_freq: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var amp := db_to_linear(volume_db)
	var lp_alpha := 1.0 - exp(-1.0 / maxf(lp_freq / sample_rate, 0.001))
	var hp_alpha := 1.0 - exp(-1.0 / maxf(hp_freq / sample_rate, 0.001))
	var lp_s := 0.0
	var hp_s := 0.0
	for i in num_samples:
		var n := rng.randf_range(-1.0, 1.0)
		lp_s += lp_alpha * (n - lp_s)
		var hp := n - lp_s
		hp_s += hp_alpha * (hp - hp_s)
		var out := hp_s * amp * 0.8
		var s16 := int(out * 32767.0)
		s16 = clampi(s16, -32768, 32767)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = 2
	stream.data = data
	stream.mix_rate = sample_rate
	return stream

func _make_metallic(duration: float, volume_db: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var num_samples := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var amp := db_to_linear(volume_db)
	var frequencies := [600.0, 1200.0, 2400.0, 4800.0]
	for i in num_samples:
		var t := float(i) / sample_rate
		var env := exp(-t * 15.0)
		var tone := 0.0
		for f in frequencies:
			tone += sin(2.0 * PI * f * t)
		tone /= frequencies.size()
		var n := randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.2
		var s := float(tone * env + n) * amp * 0.6
		var s16 := int(s * 32767.0)
		s16 = clampi(s16, -32768, 32767)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = 2
	stream.data = data
	stream.mix_rate = sample_rate
	return stream

func _make_arpeggio(frequencies: Array, note_duration: float, volume_db: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var total_duration := note_duration * frequencies.size() + 0.1
	var num_samples := int(total_duration * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var amp := db_to_linear(volume_db)
	for i in num_samples:
		var t := float(i) / sample_rate
		var note_idx := int(t / note_duration)
		if note_idx >= frequencies.size():
			note_idx = frequencies.size() - 1
		var freq: float = frequencies[note_idx]
		var note_t := fmod(t, note_duration)
		var env := exp(-note_t * 8.0) if note_t > note_duration * 0.7 else 1.0
		var s := sin(2.0 * PI * freq * t) * env * amp * 0.5
		var s16 := int(s * 32767.0)
		s16 = clampi(s16, -32768, 32767)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = 2
	stream.data = data
	stream.mix_rate = sample_rate
	return stream

## 上升琶音（命运卡片应用：从低到高）
func _make_arpeggio_up(frequencies: Array, note_duration: float, volume_db: float) -> AudioStreamWAV:
	# 反转顺序实现从低到高
	var reversed := frequencies.duplicate()
	reversed.reverse()
	return _make_arpeggio(reversed, note_duration, volume_db)

func _mix_two(a: AudioStreamWAV, b: AudioStreamWAV, vol_a: float, vol_b: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var len_a: int = a.data.size() if a.data.size() > 0 else 0
	var len_b: int = b.data.size() if b.data.size() > 0 else 0
	var num_samples := maxi(len_a, len_b) / 2
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var sa := 0.0
		var sb := 0.0
		if i * 2 + 1 < len_a:
			sa = float(int(a.data[i * 2]) | (int(a.data[i * 2 + 1]) << 8))
			if sa >= 32768.0:
				sa -= 65536.0
		if i * 2 + 1 < len_b:
			sb = float(int(b.data[i * 2]) | (int(b.data[i * 2 + 1]) << 8))
			if sb >= 32768.0:
				sb -= 65536.0
		var out := sa * vol_a + sb * vol_b
		out = clamp(out, -32768.0, 32767.0)
		var s16 := int(out)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = 2
	stream.data = data
	stream.mix_rate = sample_rate
	return stream

const PI: float = 3.141592653589793

func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)
