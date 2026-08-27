class_name WorldTimeDomain
extends RefCounted
## 无节点依赖的世界时钟算法。所有日期、HUD文本、太阳轨迹与周期接口都从
## elapsed_game_seconds 推导，避免场景各自维护互相漂移的“当前小时”。

const START_UNIX_SECONDS := 3313587600
const GAME_SECONDS_PER_DAY := 86_400.0
const REAL_SECONDS_PER_GAME_DAY := 20.0 * 60.0
const GAME_SECONDS_PER_REAL_SECOND := GAME_SECONDS_PER_DAY / REAL_SECONDS_PER_GAME_DAY
const SOLAR_PEAK_ENERGY := 3.0
const SUNRISE_HOUR := 6.0
const SUNSET_HOUR := 20.0
const BASE_SUN_YAW_DEGREES := 32.0
const SUNRISE_LIGHT_COLOR := Color(1.0, 0.48, 0.22)
const NOON_LIGHT_COLOR := Color(1.0, 0.95, 0.84)
const SUNSET_LIGHT_COLOR := Color(1.0, 0.30, 0.12)
const NIGHT_LIGHT_COLOR := Color(0.20, 0.28, 0.44)

const DAY_BACKGROUND := Color(0.58, 0.62, 0.64)
const NIGHT_BACKGROUND := Color(0.012, 0.022, 0.042)
const DAY_AMBIENT := Color(0.45, 0.52, 0.60)
const NIGHT_AMBIENT := Color(0.055, 0.085, 0.14)
const DAY_AMBIENT_ENERGY := 0.01
const NIGHT_AMBIENT_ENERGY := 0.0035


static func elapsed_from_real_seconds(real_seconds: float) -> float:
	return maxf(0.0, real_seconds) * GAME_SECONDS_PER_REAL_SECOND


static func get_snapshot(elapsed_game_seconds: float) -> Dictionary:
	var elapsed := maxf(0.0, elapsed_game_seconds)
	var unix_seconds := START_UNIX_SECONDS + int(floor(elapsed))
	var date_time := Time.get_datetime_dict_from_unix_time(unix_seconds)
	var second_of_day := fmod(17.0 * 3600.0 + elapsed, GAME_SECONDS_PER_DAY)
	var hour_float := second_of_day / 3600.0
	var day_index := int(floor((17.0 * 3600.0 + elapsed) / GAME_SECONDS_PER_DAY))
	var solar := get_solar_snapshot(hour_float)
	return {
		"elapsed_game_seconds": elapsed,
		"unix_seconds": unix_seconds,
		"day_index": day_index,
		"year": int(date_time.get("year", 2075)),
		"month": int(date_time.get("month", 1)),
		"day": int(date_time.get("day", 1)),
		"hour": int(date_time.get("hour", 17)),
		"minute": int(date_time.get("minute", 0)),
		"second": int(date_time.get("second", 0)),
		"hour_float": hour_float,
		"date_text": "%04d-%02d-%02d" % [
			int(date_time.get("year", 2075)),
			int(date_time.get("month", 1)),
			int(date_time.get("day", 1)),
		],
		"clock_text": "%02d:%02d" % [
			int(date_time.get("hour", 17)),
			int(date_time.get("minute", 0)),
		],
		"display_text": "%04d-%02d-%02d  %02d:%02d" % [
			int(date_time.get("year", 2075)),
			int(date_time.get("month", 1)),
			int(date_time.get("day", 1)),
			int(date_time.get("hour", 17)),
			int(date_time.get("minute", 0)),
		],
		"minute_key": int(floor((float(START_UNIX_SECONDS) + elapsed) / 60.0)),
		"solar": solar,
	}


static func get_solar_snapshot(hour_float: float) -> Dictionary:
	var hour := fposmod(hour_float, 24.0)
	var daylight := hour >= SUNRISE_HOUR and hour < SUNSET_HOUR
	var day_progress := clampf((hour - SUNRISE_HOUR) / (SUNSET_HOUR - SUNRISE_HOUR), 0.0, 1.0)
	var daylight_factor := 0.0
	if daylight:
		# 仍以12:00为能量峰值；下午单独延长到20:00，并用缓降指数保留
		# 17—19点可读的黄昏直射光，而不是把峰值随日落一起推迟到13点。
		var raw_factor := (
			sin(clampf((hour - SUNRISE_HOUR) / (12.0 - SUNRISE_HOUR), 0.0, 1.0) * PI * 0.5)
			if hour <= 12.0
			else cos(clampf((hour - 12.0) / (SUNSET_HOUR - 12.0), 0.0, 1.0) * PI * 0.5)
		)
		daylight_factor = pow(maxf(0.0, raw_factor), 0.65)
	# DirectionalLight3D 的 -Z 是光线方向：pitch 约 0° 接近地平线，
	# 负角度向地面照。太阳从东向西跨越时 yaw 同步改变。
	var pitch := lerpf(-4.0, -60.0, daylight_factor) if daylight else 14.0
	var yaw := BASE_SUN_YAW_DEGREES + lerpf(-88.0, 88.0, day_progress)
	var phase := _day_phase(hour)
	var sun_color := NIGHT_LIGHT_COLOR
	if daylight:
		if hour < 8.0:
			sun_color = SUNRISE_LIGHT_COLOR.lerp(
				NOON_LIGHT_COLOR, clampf((hour - SUNRISE_HOUR) / 2.0, 0.0, 1.0)
			)
		elif hour < 16.0:
			sun_color = NOON_LIGHT_COLOR
		else:
			sun_color = NOON_LIGHT_COLOR.lerp(
				SUNSET_LIGHT_COLOR, clampf((hour - 16.0) / (SUNSET_HOUR - 16.0), 0.0, 1.0)
			)
	return {
		"hour_float": hour,
		"daylight": daylight,
		"daylight_factor": daylight_factor,
		"energy": SOLAR_PEAK_ENERGY * daylight_factor,
		"rotation_degrees": Vector3(pitch, yaw, 0.0),
		"sun_color": sun_color,
		"phase": phase,
		"background_color": NIGHT_BACKGROUND.lerp(DAY_BACKGROUND, daylight_factor),
		"ambient_color": NIGHT_AMBIENT.lerp(DAY_AMBIENT, daylight_factor),
		"ambient_energy": lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, daylight_factor),
	}


static func _day_phase(hour: float) -> String:
	if hour >= 5.0 and hour < 8.0:
		return "dawn"
	if hour >= 8.0 and hour < 17.0:
		return "day"
	if hour >= 17.0 and hour < 20.0:
		return "dusk"
	return "night"
