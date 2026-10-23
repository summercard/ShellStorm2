"""把兔子本体的全部动画剪辑渲染进同一张画面 —— 总览静帧 + 循环演示视频。

链路：
  1. 读 `anim_bunny01_library.json`，按「基础 → 空手 → 短枪/长枪/机枪 → 近战三系」分区排版
  2. 调 Godot 场景 `tools/anim_showcase_capture.tscn` 采样骨骼帧并渲染（只读，不进状态机）
  3. PIL 贴中文标签 / 族色条 / 表头
  4. ffmpeg 把逐帧 jpg 编成循环 mp4

用法：
  python scripts/render_anim_showcase.py                 # 总览图 + 视频
  python scripts/render_anim_showcase.py --still-only    # 只出总览图
  python scripts/render_anim_showcase.py --with-props    # 格子里额外挂道具（默认关）

口径：
  - 每格按剪辑**自己的时长**循环播放，与玩家状态机无关；一次性动作播完从头再来。
  - 正交相机固定 yaw=32° / pitch=12°，全图同一尺度，便于横向比较动作幅度。
  - 默认不挂道具：武器挂点由动画驱动，单独挂 prefab 会引入朝向耦合；
    要看握持形态加 --with-props，并自行核对朝向。
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = (
    ROOT
    / "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01"
    / "components/chr_bunny01_motion/anim_bunny01_library.json"
)
SCENE = "res://tools/anim_showcase_capture.tscn"
GODOT_DEFAULT = r"I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"

COLS = 12
STILL_CELL = (320, 300)
VIDEO_CELL = (240, 220)
FPS = 30
SECONDS = 12
CAM_YAW = 0.0
CAM_PITCH = 0.0
AVATAR_YAW = 26.0

FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD_PATH = "C:/Windows/Fonts/msyhbd.ttc"

# 族：(键, 中文名, 条色)。顺序即版面顺序。
FAMILIES = [
    ("basic", "基础", (0x8F, 0xA3, 0xB8)),
    ("unarmed", "空手", (0x7E, 0xC8, 0xA6)),
    ("sidearm", "短枪", (0x6E, 0xB8, 0xE8)),
    ("longgun", "长枪", (0xC0, 0x8B, 0xE8)),
    ("machinegun", "机枪", (0xE8, 0x9B, 0x6E)),
    ("melee_blade", "大刀", (0xE8, 0x6E, 0x8B)),
    ("melee_axe", "战斧", (0xE8, 0xC4, 0x6E)),
    ("melee_bat", "球棒", (0x9E, 0xD8, 0x6E)),
]

BASIC_LABEL = {
    "idle": "待机",
    "walking": "走路",
    "moving": "跑动",
    "armed_idle": "持枪待机",
    "armed_walking": "持枪走路",
    "armed_moving": "持枪跑动",
    "locked": "锁定警戒",
    "seated": "坐下",
    "climbing": "攀爬",
    "dashing": "冲刺",
    "falling": "下落",
    "landing": "落地",
    "hurt": "受击",
    "dead": "倒地",
}

DIRECTION = {"forward": "前", "backward": "后", "strafe_left": "左", "strafe_right": "右"}
MELEE_PHASE = {"windup": "预备", "active": "命中", "recovery": "收势"}


def family_of(clip: str) -> str:
    for key, _label, _color in FAMILIES:
        if key != "basic" and clip.startswith(key + "_"):
            return key
    return "basic"


def action_label(clip: str) -> str:
    fam = family_of(clip)
    if fam == "basic":
        return BASIC_LABEL.get(clip, clip)
    rest = clip[len(fam) + 1:]

    if fam.startswith("melee_"):
        if rest == "idle":
            return "持械待机"
        if rest.startswith("charged_"):
            return "蓄力击·" + MELEE_PHASE.get(rest[len("charged_"):], rest)
        if rest == "spin_recovery":
            return "旋斩·收势"
        if rest == "spin":
            return "旋斩"
        if rest == "charge":
            return "蓄力"
        combo, _, phase = rest.partition("_")
        if combo.isdigit():
            return "连击{}·{}".format(combo, MELEE_PHASE.get(phase, phase))
        return rest

    if rest.startswith(("draw_", "stow_")):
        verb = "拔出" if rest.startswith("draw_") else "收起"
        return "{}·槽{}".format(verb, rest.rsplit("slot", 1)[-1])
    if rest == "reload":
        return "换弹"
    if rest == "idle":
        return "持枪待机"
    if rest == "fire_idle":
        return "开火待机"

    firing = rest.startswith("fire_")
    body = rest[len("fire_"):] if firing else rest
    prefix = "开火·" if firing else ""
    for speed, word in (("walking_", "走"), ("moving_", "跑")):
        if body.startswith(speed):
            tail = body[len(speed):]
            return "{}{}·{}".format(prefix, word, DIRECTION.get(tail, tail))
    return prefix + body


def build_layout(library: dict, cell_px: tuple[int, int]) -> dict:
    clips = library["clips"]
    order: list[str] = []
    for key, _label, _color in FAMILIES:
        if key == "basic":
            names = [c for c in clips if family_of(c) == "basic"]
            names.sort(key=lambda c: list(BASIC_LABEL).index(c) if c in BASIC_LABEL else 99)
        else:
            names = sorted(c for c in clips if c.startswith(key + "_"))
        order.extend(names)
    order.extend(sorted(c for c in clips if c not in order))

    rows = (len(order) + COLS - 1) // COLS
    slots = [{"row": i // COLS, "col": i % COLS, "clip": c} for i, c in enumerate(order)]
    return {"cols": COLS, "rows": rows, "cell_px": list(cell_px), "slots": slots, "order": order}


def run_godot(layout_path: Path, out_dir: Path, frames: int, still: bool, with_props: bool) -> None:
    env = dict(os.environ)
    env["APPDATA"] = str(ROOT.parent / "_scratch" / "anim_showcase" / "appdata")
    cmd = [
        os.environ.get("GODOT_BIN", GODOT_DEFAULT),
        "--path",
        str(ROOT),
        SCENE,
        "--",
        "--layout",
        str(layout_path),
        "--out",
        str(out_dir),
        "--yaw",
        str(CAM_YAW),
        "--pitch",
        str(CAM_PITCH),
        "--avatar-yaw",
        str(AVATAR_YAW),
        "--with-props" if with_props else "--no-weapons",
    ]
    cmd += ["--still"] if still else ["--frames", str(frames), "--fps", str(FPS)]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in (result.stdout or "").splitlines():
        if "[showcase]" in line:
            print(line)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        raise SystemExit("Godot 渲染失败，退出码 {}".format(result.returncode))


def fonts(cell: tuple[int, int]):
    scale = cell[0] / STILL_CELL[0]
    return (
        ImageFont.truetype(FONT_BOLD_PATH, max(13, int(46 * scale))),
        ImageFont.truetype(FONT_PATH, max(10, int(21 * scale))),
        ImageFont.truetype(FONT_BOLD_PATH, max(9, int(15 * scale))),
        ImageFont.truetype(FONT_PATH, max(8, int(13 * scale))),
    )


def build_overlay(layout: dict, library: dict, cell: tuple[int, int],
                  header: int, title: str, width: int, height: int) -> Image.Image:
    """生成一张与「带表头画面」同尺寸的 RGBA 文字层：表头 + 每格标签 + 网格线。

    视频用 ffmpeg 把这一层叠上去，静帧直接 alpha_composite —— 两条链路共用同一份排版，
    不会出现「图上有字、视频里没字」。
    """
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    title_font, sub_font, name_font, meta_font = fonts(cell)

    clips = library["clips"]
    colors = {k: c for k, _l, c in FAMILIES}
    labels = {k: l for k, l, _c in FAMILIES}
    scale = cell[0] / STILL_CELL[0]
    version = str(library.get("version", "?")).lstrip("vV")

    line1, line2, line3 = int(header * 0.06), int(header * 0.46), int(header * 0.74)
    draw.text((int(24 * scale), line1), title, font=title_font, fill=(236, 242, 248, 255))
    draw.text(
        (int(26 * scale), line2),
        "{} 个剪辑 · 动画库 v{} · 每格按剪辑自身时长循环，与玩家状态机无关 · 正交视图统一尺度".format(
            len(layout["order"]), version
        ),
        font=sub_font,
        fill=(142, 160, 178, 255),
    )

    cursor = int(26 * scale)
    chip = max(8, int(11 * scale))
    for key, label, color in FAMILIES:
        count = sum(1 for c in layout["order"] if family_of(c) == key)
        draw.rectangle([cursor, line3 + int(2 * scale), cursor + chip, line3 + chip + int(2 * scale)],
                       fill=(color[0], color[1], color[2], 255))
        text = "{} {}".format(label, count)
        draw.text((cursor + chip + int(5 * scale), line3 - int(1 * scale)), text,
                  font=meta_font, fill=(176, 190, 204, 255))
        cursor += chip + int(10 * scale) + int(draw.textlength(text, font=meta_font))

    for slot in layout["slots"]:
        col, row, clip = slot["col"], slot["row"], slot["clip"]
        x0, y0 = col * cell[0], header + row * cell[1]
        fam = family_of(clip)
        data = clips.get(clip, {})
        color = colors[fam]
        draw.rectangle([x0 + 4, y0 + 5, x0 + 8, y0 + cell[1] - 5],
                       fill=(color[0], color[1], color[2], 255))
        draw.text((x0 + int(14 * scale), y0 + int(4 * scale)),
                  "{}·{}".format(labels[fam], action_label(clip)),
                  font=name_font, fill=(232, 239, 246, 255))
        draw.text((x0 + int(14 * scale), y0 + int(4 * scale) + int(24 * scale)),
                  clip, font=meta_font, fill=(108, 126, 144, 255))
        draw.text(
            (x0 + int(14 * scale), y0 + cell[1] - int(26 * scale)),
            "{} {:.2f}s".format("循环" if data.get("loop") else "单次",
                                float(data.get("duration", 0.0))),
            font=meta_font,
            fill=(126, 144, 162, 255),
        )
        draw.line([x0, y0, x0, y0 + cell[1]], fill=(30, 40, 52, 255), width=1)
        draw.line([x0, y0, x0 + cell[0], y0], fill=(30, 40, 52, 255), width=1)
    return overlay


def compose(frame_path: Path, out_path: Path, layout: dict, library: dict,
            cell: tuple[int, int], header: int, title: str) -> None:
    base = Image.open(frame_path).convert("RGBA")
    canvas = Image.new("RGBA", (base.width, base.height + header), (13, 18, 24, 255))
    canvas.paste(base, (0, header))
    overlay_path = frame_path.parent / "overlay.png"
    if overlay_path.exists():
        canvas = Image.alpha_composite(canvas, Image.open(overlay_path).convert("RGBA"))
    else:
        canvas = Image.alpha_composite(
            canvas, build_overlay(layout, library, cell, header, title, canvas.width, canvas.height))
    canvas.convert("RGB").save(out_path, quality=94)


def write_overlay(out_dir: Path, layout: dict, library: dict, cell: tuple[int, int],
                  header: int, title: str, frame_size: tuple[int, int]) -> Path:
    path = out_dir / "overlay.png"
    build_overlay(layout, library, cell, header, title,
                  frame_size[0], frame_size[1] + header).save(path)
    return path


def encode_video(frames_dir: Path, out_path: Path, overlay: Path, header: int,
                 frame_size: tuple[int, int]) -> None:
    """逐帧 jpg + 静态文字层 → mp4。表头用 pad 补在最上方，标签层全程叠加。

    yuv420p 要求宽高均为偶数，表头高度与总高在这里就近取偶，否则编码器直接拒绝。
    """
    w, h = frame_size
    total_h = h + header
    if total_h % 2:
        total_h += 1
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-framerate", str(FPS),
            "-i", str(frames_dir / "f%04d.jpg"),
            "-loop", "1", "-framerate", str(FPS), "-i", str(overlay),
            "-filter_complex",
            "[0:v]pad={w}:{th}:0:{pad}:color=0x0d1218[base];"
            "[base][1:v]overlay=0:0,format=yuv420p[v]".format(
                w=w, th=total_h, pad=header),
            "-map", "[v]",
            "-frames:v", str(FPS * 600),
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-crf", "20", "-preset", "medium", "-movflags", "+faststart",
            str(out_path),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--still-only", action="store_true")
    parser.add_argument("--with-props", action="store_true")
    parser.add_argument("--seconds", type=float, default=SECONDS)
    parser.add_argument("--reuse-frames", action="store_true",
                        help="复用已有的逐帧图，只重做标签层与编码（改标签样式时用，省一次渲染）")
    args = parser.parse_args()

    out_root = ROOT / "outputs" / "anim_showcase_v001"
    work = ROOT.parent / "_scratch" / "anim_showcase" / "work"
    out_root.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)

    library = json.loads(LIBRARY.read_text(encoding="utf-8"))
    suffix = "_props" if args.with_props else ""

    # ① 总览静帧
    still_layout = build_layout(library, STILL_CELL)
    still_layout_path = work / "layout_still.json"
    still_layout_path.write_text(json.dumps(still_layout, ensure_ascii=False), encoding="utf-8")
    still_raw = work / "still_raw"
    if still_raw.exists():
        shutil.rmtree(still_raw)
    run_godot(still_layout_path, still_raw, 1, True, args.with_props)
    still_out = out_root / "角色全动画总览{}.jpg".format(suffix)
    compose(still_raw / "still.jpg", still_out, still_layout, library, STILL_CELL,
            int(STILL_CELL[1] * 0.44), "弹壳风暴2 · 兔子本体全动画总览")
    w, h = Image.open(still_out).size
    print("总览图 ->", still_out)
    print("  格子 {} 个（{} 列 × {} 行），画面 {}×{}".format(
        len(still_layout["slots"]), still_layout["cols"], still_layout["rows"], w, h))

    if args.still_only:
        return

    # ② 循环视频
    video_layout = build_layout(library, VIDEO_CELL)
    video_layout_path = work / "layout_video.json"
    video_layout_path.write_text(json.dumps(video_layout, ensure_ascii=False), encoding="utf-8")
    video_raw = work / "video_raw"
    frames = int(round(args.seconds * FPS))
    cached = len(list(video_raw.glob("f*.jpg"))) if video_raw.exists() else 0
    if args.reuse_frames and cached >= frames:
        print("[showcase] 复用已有 {} 帧，跳过渲染".format(cached))
    else:
        # 只清自己写出的逐帧图，不整目录删除（批量删除会被安全护栏拦下）
        for old in video_raw.glob("f*.jpg"):
            old.unlink()
        run_godot(video_layout_path, video_raw, frames, False, args.with_props)

    video_header = int(VIDEO_CELL[1] * 0.46)
    first = video_raw / "f0000.jpg"
    frame_size = Image.open(first).size
    overlay = write_overlay(video_raw, video_layout, library, VIDEO_CELL, video_header,
                            "弹壳风暴2 · 兔子本体全动画演示", frame_size)
    video_out = out_root / "角色全动画演示{}.mp4".format(suffix)
    encode_video(video_raw, video_out, overlay, video_header, frame_size)
    print("演示视频 -> {}（{} 帧 @{}fps ≈ {} 秒，{:.1f} MB）".format(
        video_out, frames, FPS, args.seconds, video_out.stat().st_size / 1e6))

    cover = out_root / "角色全动画演示_封面{}.jpg".format(suffix)
    compose(first, cover, video_layout, library, VIDEO_CELL, video_header,
            "弹壳风暴2 · 兔子本体全动画演示")
    print("视频封面 ->", cover)


if __name__ == "__main__":
    main()
