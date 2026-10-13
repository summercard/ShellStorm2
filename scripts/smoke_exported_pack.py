"""对导出的 Windows 包做「隔离冒烟测试」：不动本机真实存档。

为什么必须有这个脚本
    导出包的 `user://` 目录与编辑器**共用同一处**
    （`%APPDATA%\\Godot\\app_userdata\\<project.godot 的 config/name>`）。
    所以直接双击跑包验证，会改写开发者本人的真实存档 —— 2026-10-12 就发生过一次。

做法
    把 `APPDATA` 环境变量指向一个工程外的空白目录再启动 exe。
    Godot 没有 `--user-data-dir` 参数，重定向 `APPDATA` 是唯一干净的隔离手段。
    该目录下的 `Godot/app_userdata/<项目名>/` 就是「全新机器」的视角。

判据（任一不满足即退出 1）
    ① exe 退出码为 0；
    ② 运行日志里出现 0 次：`Can't open` / `启动失败` / `Failed loading resource` / 行首 `ERROR`；
    ③ 隔离目录内**自动生成了** `base_save.json` ⇒ 首次运行（无存档）能正常初始化；
    ④ 该存档的 `revision` 足够小 ⇒ 确认是全新档，不是被灌进来的旧档。

用法
    python scripts/smoke_exported_pack.py <导出的 .exe 路径>
    python scripts/smoke_exported_pack.py <exe> --keep    # 保留隔离目录便于排查
    python scripts/smoke_exported_pack.py <exe> --gui      # 额外做一次图形模式启动检查

退出码：0 = 通过；1 = 失败。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent / "ShellStorm2-work"
ISOLATED_ROOT = WORK / "outputs" / "_isolated_smoke"

# 这些字样出现在运行日志里即视为失败。
FORBIDDEN = ("Can't open", "启动失败", "Failed loading resource")
FRESH_REVISION_CEILING = 200  # 全新档的 revision 应远低于任何真实进度


def project_name() -> str:
    """从 project.godot 读 application/config/name —— 它决定存档目录名。"""
    text = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")
    m = re.search(r'^config/name="([^"]+)"', text, re.M)
    return m.group(1) if m else ""


def run_once(exe: Path, appdata: Path, gui: bool, tag: str) -> tuple[int, str]:
    env = dict(os.environ)
    env["APPDATA"] = str(appdata)
    if gui:
        proc = subprocess.Popen(
            [str(exe)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(25)
        alive = proc.poll() is None
        if alive:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        return (0 if alive else int(proc.returncode or 1)), (
            "GUI_ALIVE" if alive else "GUI_EXITED_EARLY"
        )

    log = exe.parent / f"run_{tag}.log"
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        proc = subprocess.run(
            [str(exe), "--headless", "--quit-after", "900", "--verbose"],
            env=env,
            stdout=fh,
            stderr=subprocess.STDOUT,
        )
    return proc.returncode, log.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", help="导出的 .exe 路径")
    parser.add_argument("--keep", action="store_true", help="保留隔离目录")
    parser.add_argument("--gui", action="store_true", help="额外做图形模式启动检查")
    args = parser.parse_args()

    exe = Path(args.exe).resolve()
    if not exe.is_file():
        print(f"找不到 exe：{exe}")
        return 1

    appdata = ISOLATED_ROOT / "appdata"
    if appdata.exists():
        shutil.rmtree(appdata)
    appdata.mkdir(parents=True)

    name = project_name()
    print(f"被测包      : {exe}")
    print(f"项目名      : {name}（存档目录名由它决定）")
    print(f"隔离 APPDATA: {appdata}")
    print()

    failures: list[str] = []

    # ---- ① headless 冒烟 ----
    code, log = run_once(exe, appdata, gui=False, tag="headless")
    print(f"[headless] 退出码 = {code}")
    if code != 0:
        failures.append(f"headless 退出码 {code}（应为 0）")
    for bad in FORBIDDEN:
        n = log.count(bad)
        if n:
            failures.append(f"日志出现 {n} 次「{bad}」")
    errors = len(re.findall(r"^ERROR", log, re.M))
    if errors:
        failures.append(f"日志出现 {errors} 行 ERROR")
    print(f"[headless] Can't open={log.count(FORBIDDEN[0])} "
          f"启动失败={log.count(FORBIDDEN[1])} "
          f"Failed loading={log.count(FORBIDDEN[2])} "
          f"ERROR 行={errors}")

    # ---- ② 首次运行是否自动建了存档 ----
    save = appdata / "Godot" / "app_userdata" / name / "base_save.json"
    if not save.is_file():
        failures.append(f"隔离目录内未生成存档：{save}")
        print("[存档] ❌ 未生成")
    else:
        doc = json.loads(save.read_text(encoding="utf-8"))
        revision = doc.get("revision")
        print(f"[存档] ✅ {save.name}  revision={revision}  "
              f"{save.stat().st_size} B")
        if isinstance(revision, (int, float)) and revision > FRESH_REVISION_CEILING:
            failures.append(
                f"存档 revision={revision} 偏大（>{FRESH_REVISION_CEILING}），"
                "疑似不是全新档"
            )

    # ---- ③ 可选图形模式 ----
    if args.gui:
        code2, status = run_once(exe, appdata, gui=True, tag="gui")
        print(f"[gui]      {status}（进程存活检查）")
        if status != "GUI_ALIVE":
            failures.append(f"图形模式未能稳定运行：{status}")

    print()
    if failures:
        print("SMOKE_FAILED")
        for f in failures:
            print(f"  ❌ {f}")
        print(f"\n隔离目录保留在：{appdata}")
        return 1

    print("SMOKE_OK")
    if not args.keep:
        shutil.rmtree(appdata, ignore_errors=True)
        for leftover in exe.parent.glob("run_*.log"):
            leftover.unlink(missing_ok=True)
        print("（隔离目录已清理；用 --keep 可保留）")
    else:
        print(f"（隔离目录保留：{appdata}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
