import os
import subprocess
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
LOG = os.path.join(ROOT, "_scratch", "nar_diag", "reverse")
os.makedirs(LOG, exist_ok=True)

SCRIPT_JSON = "data/narrative/nar_tower_opening_01_wake.json"
ADAPTER = "src/narrative/NarrativeAdapter3D.gd"

SNAPSHOT = {}


def read(rel):
    path = os.path.join(ROOT, rel)
    if rel not in SNAPSHOT:
        SNAPSHOT[rel] = open(path, "rb").read()
    return SNAPSHOT[rel].decode("utf-8")


def write(rel, text):
    open(os.path.join(ROOT, rel), "wb").write(text.replace("\n", "\r\n").encode("utf-8"))


def swap(rel, old, new):
    text = read(rel).replace("\r\n", "\n")
    assert text.count(old) == 1, "anchor %s count=%d" % (rel, text.count(old))
    write(rel, text.replace(old, new, 1))


def restore(rel=None):
    targets = [rel] if rel else list(SNAPSHOT.keys())
    for item in targets:
        open(os.path.join(ROOT, item), "wb").write(SNAPSHOT[item])


def run_probe(tag):
    log_path = os.path.join(LOG, tag + ".log")
    with open(log_path, "wb") as handle:
        subprocess.run(
            [GODOT, "--headless", "--path", ".", "res://tests/verification/verify_opening_script_runtime.tscn"],
            cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT,
        )
    text = open(log_path, "rb").read().decode("utf-8", "replace")
    result = "OK" if "_OK checks=" in text else "FAIL"
    lines = [line for line in text.split("\n") if line.startswith("  - ")]
    print("   -> %s ; 红项 %d" % (result, len(lines)))
    for line in lines:
        print("      %s" % line.strip())
    return result, lines


# --- 预读快照 ---
read(SCRIPT_JSON)
read(ADAPTER)

print("=== 反向对照 R1：把剧本 01 的触发源改回 room_entered（缺陷①③的根因） ===")
swap(SCRIPT_JSON, '"on": "gameplay_started"', '"on": "room_entered"')
run_probe("R1_trigger_room_entered")
restore(SCRIPT_JSON)

print("=== 反向对照 R2：让俯角枢轴退化成单位阵（= 老实现『只改距离』） ===")
swap(
    ADAPTER,
    "\tvar delta := deg_to_rad(_camera_elev_deg() - _camera_rest_elevation_deg)",
    "\tvar delta := 0.0",
)
run_probe("R2_elevation_noop")
restore(ADAPTER)

print("=== 反向对照 R3：归还时改写快照（锁定）而不是重新裁决（缺陷④） ===")
swap(
    ADAPTER,
    """	_player_input_taken = false
	var dungeon := dungeon_node()
	if dungeon != null and dungeon.has_method("refresh_player_input_lock"):
		dungeon.call("refresh_player_input_lock")
		return
	var player := player_node()
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", false)
""",
    """	_player_input_taken = false
	var player := player_node()
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", true)
""",
)
run_probe("R3_release_keeps_locked")
restore(ADAPTER)

# --- 还原校验：逐字节比对 ---
print("=== 还原校验 ===")
for rel, blob in SNAPSHOT.items():
    current = open(os.path.join(ROOT, rel), "rb").read()
    print("  %-56s %s" % (rel, "IDENTICAL" if current == blob else "*** 不一致 ***"))
    if current != blob:
        sys.exit(1)
print("REVERSE CONTROL DONE")
