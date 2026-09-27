"""把标注好的规划输入拷到纯 ASCII 工作目录，跑 02 的 plan_components.py（--write），
再把 component_plan.json 与日志回拷到 _scratch 作业目录。

用法::
    python run_plan.py [corridor db ...]      # 默认两个都跑
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

PY = r"C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
PLAN = r"C:/Users/zhuangmenghong/.workbuddy/skills/02-battle-room-component-decomposer/scripts/plan_components.py"
SRC = Path(r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/corridor_db_plan")
TMP = Path(r"C:/Users/zhuangmenghong/AppData/Local/Temp/ss2pal/plan_work")

ROOMS = ("corridor", "db")


def main() -> int:
    rooms = [a for a in sys.argv[1:] if not a.startswith("-")] or list(ROOMS)
    bad = 0
    for room in rooms:
        dst = TMP / room
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(SRC / room / "plan_input", dst)
        work_log_dir = SRC / room / "plan_work"
        work_log_dir.mkdir(parents=True, exist_ok=True)
        print("=" * 78)
        print("ROOM:", room, "| work dir:", dst)
        proc = subprocess.run(
            [PY, PLAN, str(dst), "--write"],
            text=True, encoding="utf-8", errors="replace",
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        out = proc.stdout or ""
        print(out)
        print("rc =", proc.returncode)
        (work_log_dir / "plan_components.log").write_text(out, encoding="utf-8")
        plan = dst / "component_plan.json"
        if plan.is_file():
            shutil.copy2(plan, SRC / room / "plan_input" / "component_plan.json")
            print("PLAN_WRITTEN ->", SRC / room / "plan_input" / "component_plan.json")
        else:
            print("!! 未产出 component_plan.json")
            bad += 1
        if proc.returncode != 0:
            bad += 1
    print("RUN_PLAN_%s" % ("OK" if not bad else "FAILED"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
