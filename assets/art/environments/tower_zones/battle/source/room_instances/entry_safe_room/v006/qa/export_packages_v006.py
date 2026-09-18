"""入口安全房 v006 导出 —— 转发壳（导出逻辑已合并）。

导出逻辑统一由 `v007/qa/export_packages_v007.py` 提供：那一份脚本按 `--version`
参数服务入口安全房的**全部版本**（两版之间除版本号与包数量外，导出主体逐行相同，
包数量由各自的 catalog.json 决定）。本文件保留原路径与文件名，只为让 v006 的
README / QA_REPORT 里的旧调用说明继续有效。

运行：
  "D:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" \
      --background --factory-startup --python export_packages_v006.py
"""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

VERSION = "v006"
CANONICAL = Path(__file__).resolve().parent.parent.parent / "v007" / "qa" / "export_packages_v007.py"
if not CANONICAL.is_file():
    raise SystemExit(f"缺少合并后的导出脚本: {CANONICAL}")

# 只透传影响行为的开关；本壳固定自己的版本号。
EXTRA = [a for a in sys.argv if a.startswith("--allow")]
sys.argv = [str(CANONICAL), "--version", VERSION] + EXTRA
runpy.run_path(str(CANONICAL), run_name="__main__")
