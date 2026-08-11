"""Replace column 10 with a deterministic cool-gray ramp and rebuild the layered PSD."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from pytoshop import enums
from pytoshop.user import nested_layers


COOL_GRAY_TOP_TO_BOTTOM = (
    "#1B2533",
    "#263242",
    "#324052",
    "#3F4F62",
    "#4D5E72",
    "#5D6E82",
    "#718195",
    "#8998AA",
    "#A5B2C1",
    "#C5CED8",
)

ROW_GROUP_NAMES = (
    "01_ACTIVE_BRAND_COLORS",
    "02_RED_CORAL_GAMUT",
    "03_ORANGE_TANGERINE_GAMUT",
    "04_YELLOW_GOLD_GAMUT",
    "05_LIME_GREEN_GAMUT",
    "06_TEAL_CYAN_GAMUT",
    "07_BLUE_ELECTRIC_GAMUT",
    "08_INDIGO_VIOLET_GAMUT",
    "09_MAGENTA_PINK_GAMUT",
    "10_SUPPORT_CHROMATIC_NEUTRALS",
)


def rgb(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def bounds(index: int) -> tuple[int, int]:
    # 与由10×10色块最近邻放大到512像素时的边界保持一致：
    # 0, 51, 102, 154, 205, 256, 307, 358, 410, 461, 512。
    return round(index * 512 / 10), round((index + 1) * 512 / 10)


def update_png(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    if image.size != (512, 512):
        raise ValueError(f"{path.name} 必须为512×512")
    x0, x1 = bounds(9)
    for row, color in enumerate(COOL_GRAY_TOP_TO_BOTTOM):
        y0, y1 = bounds(row)
        image.paste(rgb(color), (x0, y0, x1, y1))
    image.save(path, format="PNG", optimize=False)
    return image


def solid_channel(value: int, width: int, height: int) -> np.ndarray:
    return np.full((height, width), value, dtype=np.uint8)


def rebuild_psd(image: Image.Image, path: Path) -> None:
    groups = []
    for row in range(10):
        y0, y1 = bounds(row)
        layers = []
        for column in range(10):
            x0, x1 = bounds(column)
            color = image.getpixel(((x0 + x1) // 2, (y0 + y1) // 2))
            hex_color = "#%02X%02X%02X" % color
            layer_number = row * 10 + column + 1
            state = "CURRENT" if row == 0 and column < 5 else "RESERVED"
            name = f"{layer_number:03d}_{state}_R{row + 1:02d}C{column + 1:02d}_{hex_color}"
            width, height = x1 - x0, y1 - y0
            layers.append(
                nested_layers.Image(
                    name=name,
                    top=y0,
                    left=x0,
                    bottom=y1,
                    right=x1,
                    channels={
                        0: solid_channel(color[0], width, height),
                        1: solid_channel(color[1], width, height),
                        2: solid_channel(color[2], width, height),
                    },
                )
            )
        groups.append(nested_layers.Group(name=ROW_GROUP_NAMES[row], layers=layers, closed=True))
    psd = nested_layers.nested_layers_to_psd(
        groups,
        color_mode=enums.ColorMode.rgb,
        compression=enums.Compression.raw,
        size=(512, 512),
    )
    with path.open("wb") as stream:
        psd.write(stream)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--palette-dir", required=True, type=Path)
    args = parser.parse_args()
    main_png = args.palette_dir / "多巴胺色盘_10x10_512.png"
    low_png = args.palette_dir / "设施低亮多巴胺色盘_10x10_512.png"
    psd_path = args.palette_dir / "多巴胺色盘_10x10_512.psd"
    main_image = update_png(main_png)
    update_png(low_png)
    rebuild_psd(main_image, psd_path)
    print("COOL_GRAY_COLUMN", ",".join(COOL_GRAY_TOP_TO_BOTTOM))


if __name__ == "__main__":
    main()
