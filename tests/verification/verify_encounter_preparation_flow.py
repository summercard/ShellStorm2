"""在工程外隔离验证生产 Director 与输入锁接缝；可选正式场景回归。"""
import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import workspace_paths as wp
from verify_encounter_safe_selection import extract, run_isolated


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=shutil.which('godot'))
    parser.add_argument('--formal', action='store_true')
    parser.add_argument('--tower', action='store_true')
    parser.add_argument('--port', choices=('A', 'B'), default='A')
    parser.add_argument('--legacy-shapes', action='store_true')
    args = parser.parse_args()
    work = wp.work_path('probes/2026-11-11_expedition01_flow_v2/flow_integration/project.godot').parent
    if args.formal or args.tower or args.legacy_shapes:
        name = 'legacy_shapes' if args.legacy_shapes else ('tower_' + args.port if args.tower else 'formal')
        (work / name).mkdir(parents=True, exist_ok=True)
        scene = work / (name + '.tscn')
        script_name = 'verify_encounter_trigger_room_flow' if args.legacy_shapes else ('verify_encounter_door_preparation' if args.tower else 'verify_encounter_event_flow')
        scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/verification/' + script_name + '.gd" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
        marker = 'ENCOUNTER_TRIGGER_ROOM_OK' if args.legacy_shapes else ('ENCOUNTER_DOOR_PREPARATION_OK' if args.tower else 'ENCOUNTER_EVENT_FLOW_OK')
        command = [args.godot, '--headless', '--path', str(ROOT), str(scene)]
        if args.tower:
            command += ['--', '--port=' + args.port]
        return run_isolated(command, work / name, marker, 180 if args.tower else 200)
    director = (ROOT / 'src/world3d/EncounterEventDirector3D.gd').read_text(encoding='utf-8')
    director = director.replace('class_name EncounterEventDirector3D\nextends RefCounted', 'class Director extends RefCounted:')
    director = director.replace('MonsterInjector.is_authorable_enemy_type(type_id)', 'type_id in ["melee_chaser", "fat_zombie03"]')
    lines = director.splitlines()
    director = lines[0] + '\n' + '\n'.join('\t' + line for line in lines[1:])
    dungeon = (ROOT / 'src/world3d/Dungeon3D.gd').read_text(encoding='utf-8')
    lock = extract(dungeon, 'set_scripted_input_hold')
    script = 'extends SceneTree\n\n' + director + '''

class LockHost extends Node:
	var _scripted_input_hold := false
	var _scripted_input_hold_sources: Dictionary = {}
	var player = null
	func _sync_player_input_lock() -> void:
		pass
'''
    script += '\n'.join('\t' + line for line in lock.splitlines())
    script += '''

class Host extends RefCounted:
	var current_room := "room"
	var alive := true
	var run_active := true
	var live := 0
	var spawned := 0
	var retry := false
	var hard_fail := false
	var holds := {}
	var last_spec := {}
	func encounter_event_context(_room, _instance) -> Dictionary:
		return {"current_room_id":current_room, "player_alive":alive, "run_active":run_active}
	func encounter_event_room_busy(_room) -> bool:
		return false
	func encounter_event_spawn(_instance, _room, spec, count) -> Dictionary:
		last_spec = spec.duplicate(true)
		if hard_fail:
			return {"ok":false, "reason":"injected"}
		if retry:
			return {"ok":true, "spawned":0, "retryable":true}
		live += count
		spawned += count
		return {"ok":true, "spawned":count}
	func encounter_event_live_count(_instance) -> int:
		return live
	func encounter_event_despawn(_instance, _reason) -> Dictionary:
		live = 0
		return {"ok":true}
	func encounter_event_input_hold(id, held) -> void:
		if held:
			holds[id] = true
		else:
			holds.erase(id)

var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func config() -> Dictionary:
	return {"schema_version":1, "event_id":"test", "room_id":"room", "duration_sec":0.0,
		"completion":"clear", "stage_advance":"clear", "progress_mode":"tick",
		"preparation_sec":3.0, "freeze_player_sec":1.0, "trigger_port_id":"west",
		"remote_spawn_policy":"opposite_entry", "spawn_origin_port_id":"east",
		"max_alive":8, "intermission_sec":2.0, "min_player_distance_m":6.0,
		"stages":[{"at_sec":4.0,"monsters":[{"type":"melee_chaser","count":20}]},
		{"at_sec":0.0,"monsters":[{"type":"fat_zombie03","count":1}]}]}

func _initialize() -> void:
	var lock_host := LockHost.new()
	lock_host.set_scripted_input_hold(true)
	lock_host.set_scripted_input_hold(true, false, "encounter:1")
	lock_host.set_scripted_input_hold(true, false, "encounter:1")
	lock_host.set_scripted_input_hold(false, true)
	check(lock_host._scripted_input_hold and lock_host._scripted_input_hold_sources.size() == 1, "旧force释放不清事件锁且同源幂等")
	lock_host.set_scripted_input_hold(true)
	lock_host.set_scripted_input_hold(false, false, "encounter:1")
	check(lock_host._scripted_input_hold, "释放事件不能释放legacy")
	lock_host.set_scripted_input_hold(false)
	check(not lock_host._scripted_input_hold, "所有source释放后归还输入")
	lock_host.free()
	var host := Host.new()
	var director := Director.new(host)
	var started := director.start(config())
	check(started.ok, "准备事件启动")
	var id := str(started.instance_id)
	check(host.holds.has(id) and host.spawned == 0, "启动即冻结但无怪")
	director.tick(0.5)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(director.export_snapshot()))
	check(director.import_snapshot(saved).ok and host.holds.has(id), "准备中JSON恢复持锁")
	check(is_equal_approx(director.get_snapshot(id).preparation_remaining_sec, 2.5), "恢复剩余准备不重置")
	director.tick(0.5)
	check(host.holds.is_empty() and host.spawned == 0, "1秒只释放自己的冻结且准备继续无怪")
	director.tick(2.0)
	check(host.spawned == 0 and not director.get_snapshot(id).preparation_active, "准备结束仍等首波4秒门槛")
	check(is_zero_approx(director.get_snapshot(id).elapsed), "准备期不计战斗截止")
	director.tick(0.9)
	check(host.spawned == 0, "无截止首波start_delay不能被绕过")
	director.tick(0.1)
	check(host.spawned == 8 and host.live == 8, "20只按max_alive8涌入而非一次全塞")
	check(host.last_spec.trigger_port_id == "west" and host.last_spec.remote_spawn_policy == "opposite_entry" and host.last_spec.spawn_origin_port_id == "east", "冻结入口及远端字段送Host")
	check(host.last_spec.min_player_distance_m == 6.0, "六米距离传递")
	check(not director.get_snapshot(id).stage_states[1].started, "未清上一波不能出下一波")
	var emitted := host.spawned
	check(director.import_snapshot(JSON.parse_string(JSON.stringify(director.export_snapshot()))).ok, "已出首批恢复")
	director.tick(1.0)
	check(host.spawned == emitted, "读档不重刷首批")
	host.live = 0
	director.tick(0.1)
	check(host.spawned == 16, "容量释放补第二批")
	host.live = 0
	director.tick(0.1)
	check(host.spawned == 20, "余数四只保留")
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	director.tick(1.0)
	check(host.spawned == 20, "清空后真实间歇")
	director.tick(1.0)
	check(host.spawned == 21, "间歇结束才派下一波")
	host.live = 0
	director.notify_enemy_departed(id, "killed")
	check(director.get_snapshot(id).terminal and host.holds.is_empty(), "末波立即完成无遗留锁")
	var prep_host := Host.new()
	var prep_director := Director.new(prep_host)
	var prep_config := config()
	prep_config.stages[0].at_sec = 1.0
	var prep_started := prep_director.start(prep_config)
	prep_director.tick(2.9)
	check(prep_host.spawned == 0, "首波延迟已够但准备未结束仍无怪")
	prep_director.tick(0.1)
	check(prep_host.spawned == 8, "准备结束不重复等待首波延迟")
	var pause_host := Host.new()
	var pause_director := Director.new(pause_host)
	var pause_started := pause_director.start(config())
	pause_host.current_room = "other"
	pause_director.tick(2.0)
	check(pause_host.holds.is_empty() and pause_director.get_snapshot(pause_started.instance_id).preparation_remaining_sec == 3.0, "离房暂停准备且归还事件输入锁")
	pause_host.current_room = "room"
	pause_director.tick(0.1)
	check(pause_host.holds.has(pause_started.instance_id), "返房恢复剩余冻结")
	var retry_host := Host.new()
	var retry_director := Director.new(retry_host)
	var retry_started := retry_director.start(config())
	retry_host.retry = true
	retry_director.tick(4.0)
	check(retry_director.get_snapshot(retry_started.instance_id).pending == 20 and not retry_director.get_snapshot(retry_started.instance_id).terminal, "远端无点保留全部pending")
	retry_host.retry = false
	retry_director.tick(0.1)
	check(retry_host.spawned == 8, "远端无点之后继续同一阶段")
	for ending in ["cancel", "death", "unload", "failure"]:
		var h := Host.new()
		var d := Director.new(h)
		var result := d.start(config())
		if ending == "cancel":
			d.cancel(result.instance_id)
		elif ending == "death":
			h.alive = false
			d.tick(0.1)
		elif ending == "unload":
			d.cancel_all("scene_unloaded")
		else:
			d._fail_instance(result.instance_id, d._instances[result.instance_id], "injected")
		check(h.holds.is_empty() and d.get_snapshot(result.instance_id).terminal, "终止释放本事件锁:" + ending)
	var legacy_host := Host.new()
	var legacy_director := Director.new(legacy_host)
	var legacy := config()
	legacy.erase("preparation_sec")
	legacy.erase("freeze_player_sec")
	legacy.duration_sec = 10.0
	legacy.completion = "timer"
	legacy.stage_advance = "time"
	legacy.stages = [{"at_sec":1.0,"monsters":[{"type":"melee_chaser","count":1}]}]
	var legacy_started := legacy_director.start(legacy)
	legacy_director.tick(0.5)
	check(legacy_host.spawned == 0, "旧timer延迟仍生效")
	check(not legacy_director.get_snapshot(legacy_started.instance_id).has("preparation_total_sec"), "旧事件HUD投影不补造准备字段")
	legacy_director.tick(0.5)
	check(legacy_host.spawned == 1, "旧timer一秒首波")
	legacy_director.tick(9.0)
	check(legacy_director.get_snapshot(legacy_started.instance_id).terminal, "旧timer十秒完成")
	var old_host := Host.new()
	var old_director := Director.new(old_host)
	var old_saved := saved.duplicate(true)
	for key in ["preparation_total_sec","preparation_remaining_sec","preparation_active","freeze_player_remaining_sec","stage_elapsed_sec","trigger_port_id"]:
		old_saved.instances[0].erase(key)
	old_saved.instances[0].elapsed = 4.0
	check(old_director.import_snapshot(old_saved).ok, "旧事件缺新字段仍可恢复")
	old_director.tick(0.1)
	check(old_host.spawned == 8 and old_host.holds.is_empty(), "旧档不补准备演出且时间门槛正常")
	var subclass_saved := saved.duplicate(true)
	for key in ["preparation_total_sec","preparation_remaining_sec","preparation_active","freeze_player_remaining_sec","stage_elapsed_sec"]:
		subclass_saved.instances[0].erase(key)
	subclass_saved.instances[0].room_prepare_remaining_sec = 0.5
	var subclass_host := Host.new()
	var subclass_director := Director.new(subclass_host)
	check(subclass_director.import_snapshot(subclass_saved).ok, "旧局部Director剩余首波时间可迁移")
	subclass_director.tick(0.4)
	check(subclass_host.spawned == 0, "迁移不提前派发")
	subclass_director.tick(0.1)
	check(subclass_host.spawned == 8, "迁移保留已等待时间不重等")
	for bad in [-1, "1", true, INF, NAN]:
		var invalid := config()
		invalid.preparation_sec = bad
		check(not Director.validate_config(invalid).ok, "非法准备秒数拒绝")
	for field in ["alert_style", "alert_text", "alert_beep_interval_sec", "alert_pulse"]:
		var bad_values: Array = []
		match field:
			"alert_style": bad_values = [null, false, 1, [], {}, "default", "RED_EVA", ""]
			"alert_text": bad_values = [null, false, 1, [], {}, "中".repeat(81)]
			"alert_beep_interval_sec": bad_values = [null, false, true, "1", [], {}, NAN, INF, -INF, 0.0, 0.249, 2.001]
			"alert_pulse": bad_values = [null, "true", 1, 0, [], {}]
		for bad in bad_values:
			var invalid := config()
			invalid[field] = bad
			check(not Director.validate_config(invalid).ok, "严格拒绝错误警报类型/值:" + field)
	for style in ["red_eva", "subtle", "none"]:
		for interval in [0.25, 1, 2.0]:
			var valid := config()
			valid.merge({"alert_style":style, "alert_text":"中".repeat(80), "alert_beep_interval_sec":interval, "alert_pulse":false}, true)
			check(Director.validate_config(valid).ok, "合法警报边界:" + style)
	var alert_host := Host.new()
	var alert_director := Director.new(alert_host)
	var alert_config := config()
	alert_config.alert_style = "red_eva"
	alert_config.stages = [{"at_sec":3.0,"monsters":[{"type":"melee_chaser","count":1}]}, {"at_sec":0.0,"monsters":[{"type":"melee_chaser","count":1}]}]
	alert_config.intermission_sec = 3.0
	var alert_started := alert_director.start(alert_config)
	var alert_id: String = alert_started.instance_id
	var alert_snapshot := alert_director.get_snapshot(alert_id)
	check(alert_snapshot.alert_phase == "preparation" and alert_snapshot.alert_remaining_sec == 3.0 and alert_snapshot.alert_total_sec == 3.0, "准备投影来自唯一时钟")
	alert_director.tick(3.0)
	alert_host.live = 0
	alert_director.notify_enemy_departed(alert_id, "killed")
	alert_snapshot = alert_director.get_snapshot(alert_id)
	check(alert_snapshot.alert_phase == "intermission" and alert_snapshot.alert_remaining_sec == 3.0 and alert_snapshot.alert_total_sec == 3.0, "间歇直接投影业务剩余与总量")
	check(not alert_snapshot.preparation_active and alert_host.holds.is_empty(), "间歇不是准备且不冻结")
	check(not alert_director.export_snapshot().instances[0].has("alert_phase"), "派生警报字段不另存业务时钟")
	alert_director.tick(1.0)
	check(alert_director.get_snapshot(alert_id).alert_remaining_sec == 2.0, "间歇投影与原剩余同步")
	alert_director.import_snapshot(JSON.parse_string(JSON.stringify(alert_director.export_snapshot())))
	check(alert_director.get_snapshot(alert_id).alert_remaining_sec == 2.0 and alert_host.holds.is_empty(), "读档间歇不重置不冻结")
	alert_director.tick(2.0)
	check(alert_director.get_snapshot(alert_id).alert_phase == "" and alert_host.spawned == 2, "间歇结束消隐并派下一波")
	check(not legacy_director.get_snapshot(legacy_started.instance_id).has("alert_phase"), "旧timer不启用新警报")
	check(not director.get_snapshot(id).config.has("alert_style"), "缺省style不被标准化成显式启用")
	var none_config := config()
	none_config.alert_style = "none"
	var none_director := Director.new(Host.new())
	check(not none_director.start(none_config).snapshot.has("alert_phase"), "none不投影警报")
	print("ENCOUNTER_PREPARATION_FLOW_OK checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
'''
    (work / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="遭遇准备隔离验证"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    (work / 'verify.gd').write_text(script, encoding='utf-8')
    return run_isolated([args.godot, '--headless', '--path', str(work), '--script', 'verify.gd'], work, 'ENCOUNTER_PREPARATION_FLOW_OK', 40)


if __name__ == '__main__':
    raise SystemExit(main())
