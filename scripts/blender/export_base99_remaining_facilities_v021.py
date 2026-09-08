"""Deprecated entry point; use export_base_facility_latest.py instead.

The compatibility name now resolves the highest source version and writes the
matching export/v### derivative.  It no longer exports v017 directly.
"""

import runpy
from pathlib import Path


if __name__ == "__main__":
    project = Path(__file__).resolve().parents[2]
    runpy.run_path(str(project / "scripts/blender/export_base_facility_latest.py"), run_name="__main__")
