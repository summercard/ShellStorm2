import subprocess, os, shutil

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SC = os.path.join(ROOT, "data", "narrative", "nar_tower_opening_02_zombies.json")
SNAP = os.path.join(ROOT, "_scratch", "nar_fix", "s02.snapshot.json")
GODOT = r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
LOG = os.path.join(ROOT, "_scratch", "nar_fix", "exp02.log")

raw = open(SC, "rb").read()
shutil.copyfile(SC, SNAP)
text = raw.decode("utf-8")
crlf = "\r\n" in text
flat = text.replace("\r\n", "\n")

old = '      "yaw_deg": -26.0,\n      "duration": 1.3'
new = '      "yaw_deg": -26.0,\n      "elevation_deg": 34.0,\n      "duration": 1.3'
assert flat.count(old) == 1, "anchor count=%d" % flat.count(old)
flat2 = flat.replace(old, new, 1)
open(SC, "wb").write((flat2.replace("\n", "\r\n") if crlf else flat2).encode("utf-8"))
print("injected elevation_deg into nar_tower_opening_02_zombies (experiment)")

with open(LOG, "w", encoding="utf-8") as fh:
    p = subprocess.run([GODOT, "--headless", "--path", ".", "res://tests/verification/verify_narrative_timeline.tscn"],
                       cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT)
print("exit=%d" % p.returncode)

lines = open(LOG, "r", encoding="utf-8", errors="replace").read().splitlines()
for ln in lines:
    if ("C2" in ln or "构图" in ln or "僵尸" in ln or "偏角" in ln or "深度" in ln
            or "第二段" in ln or "framing" in ln or "OK checks" in ln or "FAIL" in ln):
        print(ln)

# restore + byte verify
shutil.copyfile(SNAP, SC)
same = open(SC, "rb").read() == raw
print("RESTORED identical:", same)
