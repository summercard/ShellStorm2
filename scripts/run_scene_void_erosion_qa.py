#!/usr/bin/env python3
"""Capture verification frames or record the void erosion orbit with a real renderer."""

from argparse import ArgumentParser
from datetime import datetime
import os
import shutil
import subprocess

from workspace_paths import PROJECT_ROOT, work_path


def main() -> int:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--renderer", choices=("forward_plus", "gl_compatibility"), default="forward_plus")
    parser.add_argument("--cyber-space", action="store_true", help="Check the Cyber Space presets and mixed boundaries.")
    parser.add_argument("--movie", action="store_true", help="Record the dynamic camera as a 30 fps MP4.")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()
    if not args.godot:
        parser.error("Supply the Godot executable with --godot or set GODOT_BIN.")
    if args.movie and not args.ffmpeg:
        parser.error("Supply FFmpeg with --ffmpeg to encode the movie.")
    if args.movie and args.cyber_space:
        parser.error("The orbit recording is available for the standalone void preview.")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    fixture = "scene_cyber_space" if args.cyber_space else "scene_void_erosion"
    output = work_path(f"verification/{fixture}/{timestamp}_{args.renderer}/forward.log").parent
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "TEMP", "TMP"):
        folder = output / "isolation" / key.lower()
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)

    command = [args.godot, "--path", str(PROJECT_ROOT), "--rendering-method", args.renderer,
               "--audio-driver", "Dummy", "--log-file", str(output / "godot.log"),
               "--scene", f"res://tests/visual/{fixture}_preview.tscn"]
    if args.movie:
        movie = output / "camera_source.avi"
        command += ["--resolution", "1280x720", "--disable-vsync", "--fixed-fps", "30",
                    "--quit-after", "480", "--write-movie", str(movie), "--", "--void-orbit"]
    else:
        frames = output / "frames"
        frames.mkdir()
        capture = "--space-captures" if args.cyber_space else "--void-captures"
        command += ["--resolution", "1440x900", "--quit-after", "660", "--", f"{capture}={frames}"]
    output_log = output / "forward.log"
    try:
        with output_log.open("wb") as log:
            result = subprocess.run(command, env=env, cwd=PROJECT_ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180 if args.movie else 90)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"Godot failed to complete: {exc}")
        print(output_log)
        return 1

    log_text = output_log.read_text(encoding="utf-8", errors="replace")
    for line in log_text.splitlines():
        if line.startswith(("VOID_EROSION_", "CYBER_SPACE_")):
            print(line)
    print(f"Godot exit={result.returncode} | {output}")
    errors = any(line.startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:")) for line in log_text.splitlines())
    expected = "VOID_EROSION_MOVIE seconds=15.0" if args.movie else "passed=true"
    if result.returncode != 0 or expected not in log_text or errors:
        return 1
    if not args.movie:
        return 0

    deliverable = work_path(f"outputs/scene_void_erosion/{timestamp}_camera.mp4")
    encoded = subprocess.run([
        args.ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(movie), "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", str(deliverable),
    ], check=False)
    if encoded.returncode == 0:
        print(deliverable)
    return encoded.returncode


if __name__ == "__main__":
    raise SystemExit(main())
