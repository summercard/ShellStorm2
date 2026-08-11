"""Relink and pack both canonical palettes in a multi-asset Blender master file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--main-palette", required=True, type=Path)
    parser.add_argument("--facility-palette", required=True, type=Path)
    return parser.parse_args(values)


def main() -> None:
    options = parse_args()
    bpy.context.preferences.filepaths.save_version = 0
    counts = {"main": 0, "facility": 0}
    for image in bpy.data.images:
        if image.source != "FILE" or "色盘" not in image.name:
            continue
        if "设施低亮" in image.name:
            target = options.facility_palette
            counts["facility"] += 1
        else:
            target = options.main_palette
            counts["main"] += 1
        image.filepath = str(target)
        image.reload()
        image.pack()
    if not counts["main"] or not counts["facility"]:
        raise RuntimeError(f"总合集必须同时包含两类色盘，实际为 {counts}")
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    print("REPACKED_MASTER_PALETTES", counts)


if __name__ == "__main__":
    main()
