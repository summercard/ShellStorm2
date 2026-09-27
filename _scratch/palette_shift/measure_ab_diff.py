"""量化 render_palette_ab.py 的 before/after 差异（像素均值 / 中位亮度 / 达标比例）。"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SHOTS = Path("I:/workbuddy_tmp/palette_ab_shots")
OUT = Path("I:/工作项目/shellstrom2/ShellStorm2/outputs/palette_lighten_matte_ab_metrics.json")


def srgb_to_linear(channel: np.ndarray) -> np.ndarray:
    c = channel / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def relative_luminance(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    linear = np.stack([srgb_to_linear(rgb[..., i]) for i in range(3)], axis=-1)
    return 0.2126 * linear[..., 0] + 0.7152 * linear[..., 1] + 0.0722 * linear[..., 2]


def object_mask(image: Image.Image) -> np.ndarray:
    """用 alpha 抠出物体像素（背景是透明胶片）。"""
    alpha = np.asarray(image.convert("RGBA"), dtype=np.float64)[..., 3]
    return alpha > 8.0


def main() -> int:
    grid = json.loads((SHOTS / "grid.json").read_text(encoding="utf-8"))
    rows = []
    print(
        "%-13s %-22s %8s %8s %8s %9s %9s %7s"
        % ("room_slug", "component", "前均值", "后均值", "提升%", "前中位", "后中位", "覆盖%")
    )
    for row in grid:
        before = Image.open(row["before"])
        after = Image.open(row["after"])
        mask_b = object_mask(before)
        mask_a = object_mask(after)
        mask = mask_b & mask_a
        lb = relative_luminance(before)[mask]
        la = relative_luminance(after)[mask]
        if lb.size == 0:
            print("SKIP %s（无重叠物体像素）" % row["rel"])
            continue
        mb, ma = float(lb.mean()), float(la.mean())
        gain = (ma - mb) / mb * 100.0 if mb > 0 else 0.0
        print(
            "%-13s %-22s %8.4f %8.4f %7.1f%% %9.4f %9.4f %6.1f%%"
            % (
                row["room_slug"],
                Path(row["rel"]).stem,
                mb,
                ma,
                gain,
                float(np.median(lb)),
                float(np.median(la)),
                mask.mean() * 100.0,
            )
        )
        rows.append(
            {
                "room_slug": row["room_slug"],
                "component": Path(row["rel"]).stem,
                "luma_before": round(mb, 5),
                "luma_after": round(ma, 5),
                "gain_pct": round(gain, 2),
                "median_before": round(float(np.median(lb)), 5),
                "median_after": round(float(np.median(la)), 5),
                "object_pixel_ratio": round(float(mask.mean()), 4),
            }
        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("WROTE:%s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
