class_name MusicCatalog
extends RefCounted
## 音乐资产注册表。纯数据，不挂场景、不发信号、不依赖 autoload。
## 新增曲目只需在 ENTRIES 加一行；触发点全部用 music_id 字符串调用 MusicManager。

const ENTRIES: Array[Dictionary] = [
	{
		"music_id": "base_passion",
		"title": "基地热血激情",
		"scene": "BaseWorld3D",
		"description": "基地大厅 / 备战室，配热血史诗管弦",
		"tracks": [
			"res://assets/audio/music/base_passion/base_passion_a.mp3",
			"res://assets/audio/music/base_passion/base_passion_b.mp3",
		],
		"selection_mode": "random",   # random | sequential | first
		"loop": true,
		"default_volume_db": -2.0,
		"fade_in_seconds": 1.2,
		"fade_out_seconds": 1.2,
		"bus": "Music",
	},
	{
		"music_id": "rooftop_relax",
		"title": "天台放松",
		"scene": "Rooftop (floor_number>=100)",
		"description": "楼顶休息区，配轻松浪漫管弦",
		"tracks": [
			"res://assets/audio/music/rooftop_relax/rooftop_relax_a.mp3",
			"res://assets/audio/music/rooftop_relax/rooftop_relax_b.mp3",
		],
		"selection_mode": "random",
		"loop": true,
		"default_volume_db": -3.0,
		"fade_in_seconds": 2.0,
		"fade_out_seconds": 2.0,
		"bus": "Music",
	},
	{
		"music_id": "descent_suspense",
		"title": "进入关卡 / 悬疑",
		"scene": "Dungeon3D / FloorEntry (99→98F)",
		"description": "下塔探索，配紧张悬疑恐怖",
		"tracks": [
			"res://assets/audio/music/descent_suspense/descent_suspense_a.mp3",
			"res://assets/audio/music/descent_suspense/descent_suspense_b.mp3",
		],
		"selection_mode": "random",
		"loop": true,
		"default_volume_db": -2.0,
		"fade_in_seconds": 1.5,
		"fade_out_seconds": 1.5,
		"bus": "Music",
	},
	{
		"music_id": "boss_intense",
		"title": "Boss 战激烈",
		"scene": "Boss 房（95/90/85F 触发）",
		"description": "Boss 战 / 精英战，配激烈管弦",
		"tracks": [
			"res://assets/audio/music/boss_intense/boss_intense_a.mp3",
			"res://assets/audio/music/boss_intense/boss_intense_b.mp3",
		],
		"selection_mode": "random",
		"loop": true,
		"default_volume_db": -1.0,
		"fade_in_seconds": 0.6,
		"fade_out_seconds": 1.0,
		"bus": "Music",
	},
]


static func get_entry(music_id: String) -> Dictionary:
	for entry in ENTRIES:
		if str(entry.get("music_id", "")) == music_id:
			return entry
	return {}


static func has_music_id(music_id: String) -> bool:
	return not get_entry(music_id).is_empty()


static func list_music_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in ENTRIES:
		ids.append(str(entry.get("music_id", "")))
	return ids