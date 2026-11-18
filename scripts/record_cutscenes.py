"""剧情过场批量录制：逐条用真实场景播放正式剧本，抓帧后合成 mp4。

用法：
    python scripts/record_cutscenes.py --all
    python scripts/record_cutscenes.py --id nar_tower_opening_02_2_outside_boom
    python scripts/record_cutscenes.py --all --hold 3.0

产物：outputs/cutscenes_<时间戳>/<序号>_<中文名>.mp4 + index.json
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SCENE = "res://tools/cutscene_recorder/cutscene_recorder.tscn"
FPS = 30
RESOLUTION = "1280x720"


def resolve_godot():
    """PATH 里的 `godot` 是 sh 垫片，Python 的 CreateProcess 执行不了，必须找到真身 exe。"""
    given = os.environ.get("GODOT_BIN")
    if given and Path(given).is_file() and given.lower().endswith(".exe"):
        return given
    shim = Path.home() / "bin" / "godot"
    if shim.is_file():
        text = shim.read_text(encoding="utf-8", errors="replace")
        for token in __import__("re").findall(r'"([^"]+\.exe)"', text):
            if Path(token).is_file():
                return token
    for drive in ["I:/", "C:/", "D:/"]:
        base = Path(drive)
        if not base.is_dir():
            continue
        for folder in base.glob("Godot*"):
            for candidate in folder.glob("*_console.exe"):
                return str(candidate)
    raise SystemExit("找不到 Godot 可执行文件，请设置 GODOT_BIN 指向 godot*_console.exe")


def resolve_ffmpeg():
    given = os.environ.get("FFMPEG_BIN")
    if given and Path(given).is_file():
        return given
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise SystemExit("找不到 ffmpeg，请设置 FFMPEG_BIN")

# 播放顺序 = 玩家实际遇到的顺序（开场 → 教程 → 主线 → 远征仪式）。
# 中文名是给人看的；id 是唯一真源，名字对不上时以 id 为准。
ORDER = [
    ("nar_tower_opening_01_wake", "01_开场_在办公室醒来"),
    ("nar_tower_opening_02_zombies", "02_开场_会议室僵尸"),
    ("nar_tower_opening_02_lobby", "03_开场_门厅警察"),
    ("nar_tower_opening_02_1_find_owner", "04_开场_寻找主人"),
    ("nar_tower_opening_02_2_outside_boom", "05_开场_外面轰响"),
    ("nar_tower_opening_02_3_aftershock", "06_开场_楼梯余震"),
    ("nar_tower_opening_02_5_stairwell_blackout", "07_开场_基地提前关灯"),
    ("nar_tower_opening_03_base_dark", "08_开场_黑暗基地"),
    ("nar_tower_opening_04_stair_zombies", "09_开场_上行楼梯僵尸"),
    ("nar_tower_opening_05_rooftop_crowd", "10_开场_天台风波"),
    ("nar_tower_opening_05_bridge_fat", "11_开场_吊桥胖子"),
    ("nar_tutorial_fate_drop_01", "12_教程_命运卡掉落"),
    ("nar_tutorial_fate_open_01", "13_教程_命运卡开启"),
    ("nar_tutorial_fate_assembled_01", "14_教程_命运卡装配"),
    ("nar_tutorial_run_vending_01", "15_教程_局内贩卖机"),
    ("nar_main_031_green_briefing", "16_主线31_绿苔简报"),
    ("nar_main_032_monitor_audience", "17_主线32_显示器首领"),
    ("nar_main_032_key_return_call", "18_主线32_返航通讯"),
    ("nar_main_033_key_install", "19_主线33_钥匙安装"),
    ("nar_expedition_entry_hologram_scan", "20_远征_入场扫描"),
    ("nar_expedition_entry_hologram_materialize", "21_远征_入场凝实"),
]


def catalog_ids():
    """从 NarrativeCatalog 读真源，避免清单与代码漂移。"""
    text = (ROOT / "src/narrative/NarrativeCatalog.gd").read_text(encoding="utf-8")
    return sorted(set(__import__("re").findall(r'"(nar_[a-z0-9_]+)"\s*:', text)))


def run_one(nid, label, index, out_root, hold, timeout):
    godot = resolve_godot()
    job = out_root / ("_work/" + nid)
    frames = job / "f"
    if frames.exists():
        shutil.rmtree(frames)
    frames.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # Autoload 之前就把用户目录顶走：正式存档绝不能被录制碰到。
    for key in ["APPDATA", "LOCALAPPDATA", "TEMP", "TMP"]:
        path = job / ("_" + key.lower())
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["SHELLSTORM_CUTSCENE_ID"] = nid
    env["SHELLSTORM_CUTSCENE_OUT"] = str(job)
    env["SHELLSTORM_CUTSCENE_HOLD"] = str(hold)
    command = [
        godot, "--path", str(ROOT), "--audio-driver", "Dummy",
        "--resolution", RESOLUTION, "--fixed-fps", str(FPS),
        "--rendering-method", "forward_plus", "--rendering-driver", "vulkan",
        SCENE,
    ]
    console = job / "console.log"
    started = time.monotonic()
    with console.open("wb") as stream:
        process = subprocess.Popen(command, env=env, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, check=False)
            code = process.wait()
    elapsed = round(time.monotonic() - started, 1)
    report = {}
    report_file = job / "report.json"
    if report_file.exists():
        try:
            report = json.loads(report_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            report = {}
    count = len(list(frames.glob("*.jpg")))
    row = {"id": nid, "label": label, "exit_code": code, "frames": count,
           "wall_seconds": elapsed, "report": report.get("finish_reason", ""),
           "diagnostics": report.get("diagnostics", []), "mp4": ""}
    if count < 15:
        row["error"] = "帧数不足，见 " + str(console)
        return row
    target = out_root / ("%s.mp4" % label)
    ff = [
        resolve_ffmpeg(), "-y", "-loglevel", "error", "-framerate", str(FPS),
        "-i", str(frames / "%06d.jpg"),
        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(target),
    ]
    if subprocess.run(ff, capture_output=True).returncode != 0:
        row["error"] = "ffmpeg 合成失败"
        return row
    row["mp4"] = str(target)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", nargs="*", default=None)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--hold", type=float, default=2.6, help="单句对白停留秒数")
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--keep-frames", action="store_true")
    args = parser.parse_args()

    known = catalog_ids()
    if args.all or not args.id:
        plan = [(nid, label) for nid, label in ORDER if nid in known]
        missing = [nid for nid in known if nid not in {p[0] for p in plan}]
        for nid in missing:
            plan.append((nid, "99_未命名_" + nid))
    else:
        names = dict(ORDER)
        plan = []
        for nid in args.id:
            if nid not in known:
                print("未知 narrative_id：" + nid, file=sys.stderr)
                return 2
            plan.append((nid, names.get(nid, "99_未命名_" + nid)))

    stamp = time.strftime("%Y%m%d_%H%M%S")
    out_root = ROOT / "outputs" / ("cutscenes_" + stamp)
    out_root.mkdir(parents=True, exist_ok=True)
    print("输出目录=" + str(out_root), flush=True)
    rows = []
    for index, (nid, label) in enumerate(plan, start=1):
        print("[%d/%d] %s ..." % (index, len(plan), label), flush=True)
        row = run_one(nid, label, index, out_root, args.hold, args.timeout)
        rows.append(row)
        state = "OK" if row.get("mp4") else "FAIL"
        print("    %s frames=%d wall=%ss %s" % (state, row["frames"], row["wall_seconds"], row.get("error", "")), flush=True)
        (out_root / "index.json").write_text(
            json.dumps({"generated": stamp, "rows": rows}, ensure_ascii=False, indent=2), encoding="utf-8")
    if not args.keep_frames:
        shutil.rmtree(out_root / "_work", ignore_errors=True)
    ok = sum(1 for row in rows if row.get("mp4"))
    print("完成 %d/%d" % (ok, len(rows)), flush=True)
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
