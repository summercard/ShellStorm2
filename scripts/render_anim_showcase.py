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
    """全量：128 个剪辑按族分区铺成 12 列。"""
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


## —— 单主题版面：一排 = 各武器族并列，每族一格代表动作 ——
##
## 2026-10-26 业主：「不需要那么多的，只要一个就行了」→ 每族只留一个代表动作。
## 下面两组完整变体清单**保留但不参与排版**：它们是把单族展开成表格时用的，
## 需要回退成全量版面时改 build_*_layout 即可。
MOVE_VARIANTS = [
    "walking_forward", "walking_backward", "walking_strafe_left", "walking_strafe_right",
    "moving_forward", "moving_backward", "moving_strafe_left", "moving_strafe_right",
]
FIRE_VARIANTS = ["fire_idle"] + ["fire_" + v for v in MOVE_VARIANTS]
## 有方向变体的族。
ARMED_FAMILIES = ["unarmed", "sidearm", "longgun", "machinegun"]
GUN_FAMILIES = ["sidearm", "longgun", "machinegun"]


def _slots_to_layout(slots: list[dict], cols: int, cell_px: tuple[int, int]) -> dict:
    rows = max((s["row"] for s in slots), default=0) + 1
    ordered = [s["clip"] for s in sorted(slots, key=lambda s: (s["row"], s["col"]))]
    return {"cols": cols, "rows": rows, "cell_px": list(cell_px), "slots": slots, "order": ordered}


## 每族的**唯一代表动作**（业主 2026-10-26：「不需要那么多，只要一个就行了」）。
## 一个代表动作 = 一族一格：横向只比族别，不再铺方向。
REPRESENTATIVE = {
    "run": "moving_forward",   # 跑步取「跑」而不是「走」，且只取正前方向
    "fire": "fire_idle",       # 开火取站立开火的稳态
}


def build_run_layout(library: dict, cell_px: tuple[int, int]) -> dict:
    """跑步：一排 4 格 = 空手 / 短枪 / 长枪 / 机枪 各一个代表动作。"""
    clips = library["clips"]
    variant = REPRESENTATIVE["run"]
    slots: list[dict] = []
    for col, fam in enumerate(ARMED_FAMILIES):
        name = "{}_{}".format(fam, variant)
        if name in clips:
            slots.append({"row": 0, "col": col, "clip": name})
    return _slots_to_layout(slots, len(slots), cell_px)


def build_reload_layout(library: dict, cell_px: tuple[int, int]) -> dict:
    """换弹：一排 3 格 = 短枪 / 长枪 / 机枪。换弹本身每族只有一个剪辑，天然就是代表动作。"""
    clips = library["clips"]
    slots = []
    for col, fam in enumerate(GUN_FAMILIES):
        name = fam + "_reload"
        if name in clips:
            slots.append({"row": 0, "col": col, "clip": name})
    return _slots_to_layout(slots, len(slots), cell_px)


def build_fire_layout(library: dict, cell_px: tuple[int, int]) -> dict:
    """开火：一排 3 格 = 短枪 / 长枪 / 机枪 各一个站立开火。"""
    clips = library["clips"]
    variant = REPRESENTATIVE["fire"]
    slots = []
    for col, fam in enumerate(GUN_FAMILIES):
        name = "{}_{}".format(fam, variant)
        if name in clips:
            slots.append({"row": 0, "col": col, "clip": name})
    return _slots_to_layout(slots, len(slots), cell_px)


## 三个单主题交付：每份**每族一格**（4 / 3 / 3 格），格子放大看清细节。
TOPICS = {
    "run": {
        "file": "角色跑步动画",
        "title": "弹壳风暴2 · 兔子跑步动画",
        "builder": build_run_layout,
        "still_cell": (480, 440),
        "video_cell": (440, 400),
        "seconds": 8.0,
        "playback": 1.0,
        # 25°：扫 0~90° 量「相邻相位帧间差」，25° 与 15° 并列最高（约 15.4），
        # 正视 14.3、纯侧视仅 8.1 —— 略侧一点步幅读得最清楚。
        "avatar_yaw": 25.0,
        "still_phase": 0.30,
        # 挂枪：不挂时四族的画面差异只有 4~8（同一剪辑不同相位是 15 量级），
        # 空手/短枪/长枪/机枪 肉眼几乎分不出来；挂上后族间差升到 5.8~9.0，
        # 一眼能对上「哪一格是哪把枪在跑」。腿仍看得见（枪在腰线以上）。
        "with_props": True,
        "note": "每族一个代表动作（跑·正前）· 位移约 0.23 m / 步态周期 0.7 s · 视角 25° 略侧，看步幅",
    },
    "reload": {
        "file": "角色换弹动画",
        "title": "弹壳风暴2 · 兔子换弹动画",
        "builder": build_reload_layout,
        # 格子刻意做宽（横向 > 纵向）：枪往前伸约 1 m，75° 侧视后几乎全占横向。
        "still_cell": (660, 500),
        "video_cell": (600, 460),
        "seconds": 8.0,
        "playback": 0.75,
        # 0.55：左手正离开枪身去够弹匣，最能读出「在换弹」的相位（扫过 0.10~0.85 后选定）。
        "still_phase": 0.55,
        # 75° 侧视：正视时枪口正对镜头只剩一个圆盘，看不出是哪种枪。
        "avatar_yaw": 75.0,
        "with_props": True,
        "note": "每族一个换弹动作 · 双手位移 0.49~0.55 m / 单次 2.0 s · 播放 0.75× 放慢 · 75° 侧视看左手取弹匣",
    },
    "fire": {
        "file": "角色开火动画",
        "title": "弹壳风暴2 · 兔子开火动画",
        "builder": build_fire_layout,
        # 同上：宽格给枪留横向余量，避免缩角色。
        "still_cell": (620, 460),
        "video_cell": (560, 420),
        "seconds": 10.0,
        "playback": 0.5,
        "still_phase": 0.25,
        # 不挂枪时三族开火的手部只差 0.08 m（长枪 vs 机枪），画面几乎一模一样；
        # 必须挂枪才看得出族别。75° 侧视才能把枪身长度读出来。
        "avatar_yaw": 75.0,
        "with_props": True,
        "note": "每族一个站立开火 · 后坐位移仅 0.03~0.04 m · 播放 0.5× 放慢 · 挂各族正式枪械，75° 侧视",
    },
}



def run_godot(layout_path: Path, out_dir: Path, frames: int, still: bool, with_props: bool,
              playback: float = 1.0, avatar_yaw: float = AVATAR_YAW,
              still_phase: float = -1.0) -> None:
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
        str(avatar_yaw),
        "--with-props" if with_props else "--no-weapons",
        "--playback",
        str(playback),
        "--phase",
        str(still_phase),
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
    # 字号只看格子的**短边**：宽格（换弹 620×460）若按宽算，标题会被撑到 89px，
    # 表头里三行挤成一团。按短边算，同一份排版在任何格形下都读得开。
    scale = min(cell[0] / STILL_CELL[0], cell[1] / STILL_CELL[1])
    return (
        ImageFont.truetype(FONT_BOLD_PATH, max(13, int(46 * scale))),
        ImageFont.truetype(FONT_PATH, max(10, int(21 * scale))),
        ImageFont.truetype(FONT_BOLD_PATH, max(9, int(15 * scale))),
        ImageFont.truetype(FONT_PATH, max(8, int(13 * scale))),
    )


def header_height(cell: tuple[int, int], has_note: bool) -> int:
    """表头高度按实际字号与行数算出来，不用「格高 × 系数」这种拍脑袋的写法。

    行序：标题 → 一行说明 → 可选的技术备注 → 族图例。系数 0.52 那种写法在
    格高一变（460 vs 560）就会让标题压在副标题上。
    """
    title_font, sub_font, _name_font, meta_font = fonts(cell)
    scale = min(cell[0] / STILL_CELL[0], cell[1] / STILL_CELL[1])
    pad = max(8, int(12 * scale))
    title_h = int(title_font.size * 1.30)
    sub_h = int(sub_font.size * 1.75)
    note_h = int(meta_font.size * 1.75) if has_note else 0
    legend_h = max(10, int(16 * scale))
    return pad + title_h + sub_h + note_h + legend_h + pad


def build_overlay(layout: dict, library: dict, cell: tuple[int, int],
                  header: int, title: str, width: int, height: int,
                  note: str = "") -> Image.Image:
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
    scale = min(cell[0] / STILL_CELL[0], cell[1] / STILL_CELL[1])
    version = str(library.get("version", "?")).lstrip("vV")

    # 表头自上而下**逐行累加**，每行的 y 由上一行的实际字高推进，
    # 不再用 header 的百分比——格高一变就会压字。
    pad = max(8, int(12 * scale))
    y = pad
    draw.text((int(24 * scale), y), title, font=title_font, fill=(236, 242, 248, 255))
    y += int(title_font.size * 1.30)
    draw.text(
        (int(26 * scale), y),
        "{} 个剪辑 · 动画库 v{} · 每格按剪辑自身时长循环，与玩家状态机无关 · 正交视图统一尺度".format(
            len(layout["order"]), version
        ),
        font=sub_font,
        fill=(142, 160, 178, 255),
    )
    y += int(sub_font.size * 1.75)
    if note:
        draw.text((int(26 * scale), y), note, font=meta_font, fill=(126, 186, 214, 255))
        y += int(meta_font.size * 1.75)

    cursor = int(26 * scale)
    chip = max(8, int(11 * scale))
    for key, label, color in FAMILIES:
        count = sum(1 for c in layout["order"] if family_of(c) == key)
        if count == 0:
            continue
        draw.rectangle([cursor, y + int(2 * scale), cursor + chip, y + chip + int(2 * scale)],
                       fill=(color[0], color[1], color[2], 255))
        text = "{} {}".format(label, count)
        draw.text((cursor + chip + int(5 * scale), y - int(1 * scale)), text,
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
            cell: tuple[int, int], header: int, title: str, note: str = "") -> None:
    base = Image.open(frame_path).convert("RGBA")
    canvas = Image.new("RGBA", (base.width, base.height + header), (13, 18, 24, 255))
    canvas.paste(base, (0, header))
    overlay_path = frame_path.parent / "overlay.png"
    if overlay_path.exists():
        canvas = Image.alpha_composite(canvas, Image.open(overlay_path).convert("RGBA"))
    else:
        canvas = Image.alpha_composite(
            canvas, build_overlay(layout, library, cell, header, title,
                                  canvas.width, canvas.height, note))
    canvas.convert("RGB").save(out_path, quality=94)


def write_overlay(out_dir: Path, layout: dict, library: dict, cell: tuple[int, int],
                  header: int, title: str, frame_size: tuple[int, int],
                  note: str = "") -> Path:
    path = out_dir / "overlay.png"
    build_overlay(layout, library, cell, header, title,
                  frame_size[0], frame_size[1] + header, note).save(path)
    return path


def encode_video(frames_dir: Path, out_path: Path, overlay: Path, header: int,
                 frame_size: tuple[int, int], frames: int) -> None:
    """逐帧 jpg + 静态文字层 → mp4。表头用 pad 补在最上方，标签层全程叠加。

    两个必须写对的地方：
    - yuv420p 要求宽高均为偶数，表头高度在这里就近取偶，否则编码器直接拒绝。
    - 标签层是 `-loop 1` 的无限输入，**必须**用真实帧数卡住输出（`-frames:v frames`）。
      写成固定上限（例如 600 s）会让首段入帧耗尽后继续输出冻结尾帧，
      实测会产出 10 分钟的假长视频。
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
            "-frames:v", str(frames),
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-crf", "20", "-preset", "medium", "-movflags", "+faststart",
            str(out_path),
        ],
        check=True,
    )


def render_case(name: str, case: dict, library: dict, work: Path, out_root: Path,
                args: argparse.Namespace) -> None:
    """渲染一份交付：静帧总览 + 循环视频 + 视频封面。"""
    builder = case["builder"]
    still_cell = case["still_cell"]
    video_cell = case["video_cell"]
    title = case["title"]
    suffix = "_props" if args.with_props else ""
    print("\n=== {} ===".format(name))

    # ① 总览静帧
    still_layout = builder(library, still_cell)
    still_layout_path = work / "layout_{}_still.json".format(name)
    still_layout_path.write_text(json.dumps(still_layout, ensure_ascii=False), encoding="utf-8")
    still_raw = work / "{}_still".format(name)
    for old in still_raw.glob("*.jpg"):
        old.unlink()
    avatar_yaw = case.get("avatar_yaw", AVATAR_YAW)
    with_props = case.get("with_props", False) or args.with_props
    run_godot(still_layout_path, still_raw, 1, True, with_props, 1.0, avatar_yaw,
              case.get("still_phase", -1.0))
    still_header = header_height(still_cell, bool(case.get('note', '')))
    note = case.get("note", "")
    still_out = out_root / "{}{}.jpg".format(case["file"], suffix)
    compose(still_raw / "still.jpg", still_out, still_layout, library, still_cell, still_header, title, note)
    w, h = Image.open(still_out).size
    print("  总览图 -> {}（{} 格，{}×{}，{} 列 × {} 行）".format(
        still_out.name, len(still_layout["slots"]), w, h,
        still_layout["cols"], still_layout["rows"]))

    if args.still_only:
        return

    # ② 循环视频
    video_layout = builder(library, video_cell)
    video_layout_path = work / "layout_{}_video.json".format(name)
    video_layout_path.write_text(json.dumps(video_layout, ensure_ascii=False), encoding="utf-8")
    seconds = args.seconds if args.seconds else case["seconds"]
    frames = int(round(seconds * FPS))
    # 帧目录按渲染参数签名命名：参数变了就换一个新目录，不再原地删旧帧。
    # （原地批量删除会触发本环境的安全护栏，而且旧帧本来就不该被覆盖复用。）
    signature = "{}_y{:.0f}_p{:.2f}_{}x{}_n{}".format(
        name, avatar_yaw, case.get("playback", 1.0), video_cell[0], video_cell[1], frames)
    video_raw = work / "frames" / signature
    video_raw.mkdir(parents=True, exist_ok=True)
    cached = len(list(video_raw.glob("f*.jpg")))
    if args.reuse_frames and cached >= frames:
        print("  复用已有 {} 帧，跳过渲染".format(cached))
    else:
        run_godot(video_layout_path, video_raw, frames, False, with_props,
                  case.get("playback", 1.0), avatar_yaw)

    video_header = header_height(video_cell, bool(case.get('note', '')))
    first = video_raw / "f0000.jpg"
    frame_size = Image.open(first).size
    overlay = write_overlay(video_raw, video_layout, library, video_cell, video_header, title,
                            frame_size, note)
    video_out = out_root / "{}{}.mp4".format(case["file"], suffix)
    encode_video(video_raw, video_out, overlay, video_header, frame_size, frames)
    print("  演示视频 -> {}（{}×{}，{} 帧 @{}fps = {}s，{:.1f} MB）".format(
        video_out.name, frame_size[0], frame_size[1] + video_header, frames, FPS,
        seconds, video_out.stat().st_size / 1e6))

    cover = out_root / "{}_封面{}.jpg".format(case["file"], suffix)
    compose(first, cover, video_layout, library, video_cell, video_header, title, note)
    print("  视频封面 -> {}".format(cover.name))


def render_all(library: dict, work: Path, out_root: Path, args: argparse.Namespace) -> None:
    """完整版：128 个剪辑一屏。"""
    suffix = "_props" if args.with_props else ""
    print("\n=== all ===")
    still_layout = build_layout(library, STILL_CELL)
    still_layout_path = work / "layout_still.json"
    still_layout_path.write_text(json.dumps(still_layout, ensure_ascii=False), encoding="utf-8")
    still_raw = work / "still_raw"
    for old in still_raw.glob("*.jpg"):
        old.unlink()
    run_godot(still_layout_path, still_raw, 1, True, args.with_props, 1.0, AVATAR_YAW, -1.0)
    still_out = out_root / "角色全动画总览{}.jpg".format(suffix)
    compose(still_raw / "still.jpg", still_out, still_layout, library, STILL_CELL,
            header_height(STILL_CELL, False), "弹壳风暴2 · 兔子本体全动画总览")
    w, h = Image.open(still_out).size
    print("  总览图 -> {}（{} 格，{}×{}）".format(still_out.name, len(still_layout["slots"]), w, h))
    if args.still_only:
        return

    video_layout = build_layout(library, VIDEO_CELL)
    video_layout_path = work / "layout_video.json"
    video_layout_path.write_text(json.dumps(video_layout, ensure_ascii=False), encoding="utf-8")
    seconds = args.seconds if args.seconds else SECONDS
    frames = int(round(seconds * FPS))
    video_raw = work / "frames" / "all_{}x{}_n{}".format(VIDEO_CELL[0], VIDEO_CELL[1], frames)
    video_raw.mkdir(parents=True, exist_ok=True)
    cached = len(list(video_raw.glob("f*.jpg")))
    if args.reuse_frames and cached >= frames:
        print("  复用已有 {} 帧，跳过渲染".format(cached))
    else:
        run_godot(video_layout_path, video_raw, frames, False, args.with_props)

    video_header = int(VIDEO_CELL[1] * 0.46)
    first = video_raw / "f0000.jpg"
    frame_size = Image.open(first).size
    overlay = write_overlay(video_raw, video_layout, library, VIDEO_CELL, video_header,
                            "弹壳风暴2 · 兔子本体全动画演示", frame_size)
    video_out = out_root / "角色全动画演示{}.mp4".format(suffix)
    encode_video(video_raw, video_out, overlay, video_header, frame_size, frames)
    print("  演示视频 -> {}（{} 帧 = {}s，{:.1f} MB）".format(
        video_out.name, frames, seconds, video_out.stat().st_size / 1e6))
    cover = out_root / "角色全动画演示_封面{}.jpg".format(suffix)
    compose(first, cover, video_layout, library, VIDEO_CELL, video_header,
            "弹壳风暴2 · 兔子本体全动画演示")
    print("  视频封面 -> {}".format(cover.name))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="角色动画演示：全量一屏，或按跑步/换弹/开火单独出片。")
    parser.add_argument("--topic", default="run,reload,fire",
                        help="要渲染的主题，逗号分隔；可用 {} 或 all".format("/".join(TOPICS)))
    parser.add_argument("--still-only", action="store_true")
    parser.add_argument("--with-props", action="store_true")
    parser.add_argument("--seconds", type=float, default=0.0,
                        help="覆盖视频时长（默认每个主题自带）")
    parser.add_argument("--reuse-frames", action="store_true",
                        help="复用已有的逐帧图，只重做标签层与编码（改标签样式时用，省一次渲染）")
    args = parser.parse_args()

    out_root = ROOT / "outputs" / "anim_showcase_v001"
    work = ROOT.parent / "_scratch" / "anim_showcase" / "work"
    out_root.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)

    library = json.loads(LIBRARY.read_text(encoding="utf-8"))
    requested = [t.strip() for t in args.topic.split(",") if t.strip()]
    if "all" in requested:
        render_all(library, work, out_root, args)
        return
    unknown = [t for t in requested if t not in TOPICS]
    if unknown:
        raise SystemExit("未知主题 {}，可用：{}".format(", ".join(unknown), ", ".join(TOPICS)))
    for name in requested:
        render_case(name, TOPICS[name], library, work, out_root, args)


if __name__ == "__main__":
    main()
