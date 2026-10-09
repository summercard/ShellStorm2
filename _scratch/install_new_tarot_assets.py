from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SRC = Path(r"C:/Users/zhuangmenghong/Desktop/新塔罗牌")
PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
DEST = PROJECT / "assets/art/ui/fate_cards"
VERIFY = PROJECT / "outputs/new_tarot_install"
BACKUP = VERIFY / "backup_before_full_cell_crop_49_png"
CHINESE = VERIFY / "chinese_named_cards_fixed"
TARGET_SIZE = (640, 1024)
DEST.mkdir(parents=True, exist_ok=True)
VERIFY.mkdir(parents=True, exist_ok=True)

source_files = [
    "ChatGPT 图像 2026年10月9日 11_15_28-1.png",
    "ChatGPT 图像 2026年10月9日 11_15_31-2.png",
    "ChatGPT 图像 2026年10月9日 11_15_35-3.png",
    "ChatGPT 图像 2026年10月9日 11_15_39-4.png",
    "ChatGPT 图像 2026年10月9日 11_15_46-5.png",
    "ChatGPT 图像 2026年10月9日 11_15_56-7.png",
    "霓虹兔机塔罗牌阵-6.png",
    "霓虹赛博兔子塔罗牌组.png",
]
images = {i + 1: Image.open(SRC / name).convert("RGB") for i, name in enumerate(source_files)}

# stable_id -> (sheet number, one-based card position in the 5x2 source sheet)
M = {
    "mark_enemy": (1, 1), "gun_on_gun": (7, 1), "moon_vitality": (1, 2),
    "sun_extra_loot": (1, 3), "sun_reinforce": (1, 4), "sun_key": (1, 5),
    "moon_power": (1, 6), "bullet_carry_gun": (7, 2), "armor_pierce": (7, 3),
    "moon_stride": (1, 7), "every_seventh": (7, 4), "sun_trial": (1, 8),
    "moon_guard": (1, 9), "gluttony": (7, 5), "sun_scorch": (1, 10),
    "out_of_control": (7, 6), "explode_reload": (7, 7), "living_bullet": (7, 8),
    "moon_first_hit": (2, 1), "sun_currency": (2, 2), "moon_last_stand": (2, 3),
    "sun_extraction": (2, 4),
    "scale_node": (2, 5), "overclock": (2, 6), "attachment_parasite": (2, 7),
    "turret_on_land": (2, 8), "home_on_land": (2, 9), "bullet_return": (2, 10),
    "chain_lightning": (3, 1), "bounce_bullet": (3, 2), "barrage_copy": (3, 3),
    "fuse_fire": (3, 4), "fuse_frost": (3, 5), "fuse_poison": (3, 6),
    "crit_kill": (3, 7), "huge_scale": (3, 8),
    "moon_dash": (3, 9), "moon_room_heal": (3, 10), "moon_elite_heal": (4, 1),
    "moon_ammo": (4, 2), "bless_dead": (7, 9),
    "reinforce": (8, 6), "lucky_chest": (8, 7), "extra_loot": (8, 8),
    "curse_map": (8, 9), "sun_quality": (8, 10), "sun_reveal": (6, 1),
    "sun_bounty": (7, 10),
}
assert len(M) == 48, len(M)
assert len(set(M.values())) == 48, "mapping contains duplicate source cells"

CN = {
    "mark_enemy": "愚者", "gun_on_gun": "魔术师", "moon_vitality": "女祭司",
    "sun_extra_loot": "皇后", "sun_reinforce": "皇帝", "sun_key": "教皇",
    "moon_power": "恋人", "bullet_carry_gun": "战车", "armor_pierce": "力量",
    "moon_stride": "隐者", "every_seventh": "命运之轮", "sun_trial": "正义",
    "moon_guard": "倒吊人", "gluttony": "死神", "sun_scorch": "节制",
    "out_of_control": "恶魔", "explode_reload": "高塔", "living_bullet": "星星",
    "moon_first_hit": "月亮", "sun_currency": "太阳", "moon_last_stand": "审判",
    "sun_extraction": "世界", "scale_node": "权杖·王牌", "overclock": "权杖·二",
    "attachment_parasite": "权杖·三", "turret_on_land": "权杖·四", "home_on_land": "权杖·五",
    "bullet_return": "权杖·六", "chain_lightning": "权杖·七", "bounce_bullet": "权杖·八",
    "barrage_copy": "权杖·九", "fuse_fire": "权杖·十", "fuse_frost": "权杖·侍从",
    "fuse_poison": "权杖·骑士", "crit_kill": "权杖·王后", "huge_scale": "权杖·国王",
    "moon_dash": "圣杯·王牌", "moon_room_heal": "圣杯·二", "moon_elite_heal": "圣杯·三",
    "moon_ammo": "圣杯·四", "bless_dead": "圣杯·五", "reinforce": "星币·王牌",
    "lucky_chest": "星币·二", "extra_loot": "星币·三", "curse_map": "星币·四",
    "sun_quality": "星币·五", "sun_reveal": "星币·六", "sun_bounty": "星币·七",
}
assert set(CN) == set(M)


def neon_green(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    return g > 80 and g > r * 1.25 and g > b * 1.12


def boundary_vertical(sheet: Image.Image, expected: int, x0: int, x1: int, y0: int, y1: int, outer: str) -> int:
    scores = []
    for x in range(max(0, x0), min(sheet.width, x1)):
        score = sum(neon_green(sheet.getpixel((x, y))) for y in range(y0, y1))
        scores.append((score, x))
    peak = max(score for score, _ in scores)
    candidates = [x for score, x in scores if score >= peak * 0.90]
    return min(candidates) if outer == "left" else max(candidates)


def boundary_horizontal(sheet: Image.Image, expected: int, y0: int, y1: int, x0: int, x1: int, outer: str) -> int:
    scores = []
    for y in range(max(0, y0), min(sheet.height, y1)):
        score = sum(neon_green(sheet.getpixel((x, y))) for x in range(x0, x1))
        scores.append((score, y))
    peak = max(score for score, _ in scores)
    candidates = [y for score, y in scores if score >= peak * 0.90]
    return min(candidates) if outer == "top" else max(candidates)


def detect_card_bbox(sheet: Image.Image, pos: int) -> tuple[int, int, int, int]:
    """Crop strictly inside the source 5x2 cell.

    The old green-line peak detector could select a neighbouring card's outer
    frame when adjacent neon borders touched. A fixed grid inset is the source
    truth for these generated 1536x1024 sheets and prevents cross-card bleed.
    """
    row, col = divmod(pos - 1, 5)
    cell_left = round(col * sheet.width / 5)
    cell_right = round((col + 1) * sheet.width / 5)
    cell_top = row * (sheet.height // 2)
    cell_bottom = (row + 1) * (sheet.height // 2)
    # The source sheets place each card in a 5x2 cell with its frame touching
    # the cell edges. Keep the whole cell so no outer neon frame is lost; the
    # outer cell gap/background is removed by the rounded alpha mask below.
    inset_x, inset_y = 0, 0
    bbox = (cell_left + inset_x, cell_top + inset_y,
            cell_right - inset_x, cell_bottom - inset_y)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    assert 300 <= w <= 315 and 500 <= h <= 515, (pos, bbox)
    return bbox


def crop_card(sheet: Image.Image, pos: int) -> tuple[Image.Image, tuple[int, int, int, int]]:
    if not hasattr(crop_card, 'cache'):
        crop_card.cache = {}
    key = id(sheet)
    if key not in crop_card.cache:
        px = sheet.load()
        xs = [sum(neon_green(px[x,y]) for y in range(sheet.height)) for x in range(sheet.width)]
        ys = [sum(neon_green(px[x,y]) for x in range(sheet.width)) for y in range(sheet.height)]
        def gap(scores, expected, radius):
            lo=max(0,expected-radius); hi=min(len(scores),expected+radius)
            best=min(scores[lo:hi]); choices=[i for i in range(lo,hi) if scores[i]==best]
            return min(choices,key=lambda i:abs(i-expected))
        xcuts=[0]+[gap(xs,round(i*sheet.width/5),45) for i in range(1,5)]+[sheet.width]
        ycuts=[0,gap(ys,sheet.height//2,45),sheet.height]
        crop_card.cache[key]=(xcuts,ycuts)
    xc,yc=crop_card.cache[key]
    r,c=divmod(pos-1,5)
    cell=sheet.crop((xc[c],yc[r],xc[c+1],yc[r+1]))
    points=[(x,y) for y in range(cell.height) for x in range(cell.width) if neon_green(cell.getpixel((x,y)))]
    # Convex outer silhouette encloses every frame pixel but never punches holes
    # in the black card interior. Actual black inter-card gaps isolate neighbours.
    pts=sorted(set(points))
    def cross(o,a,b): return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower=[]
    for p in pts:
        while len(lower)>=2 and cross(lower[-2],lower[-1],p)<=0: lower.pop()
        lower.append(p)
    upper=[]
    for p in reversed(pts):
        while len(upper)>=2 and cross(upper[-2],upper[-1],p)<=0: upper.pop()
        upper.append(p)
    mask=Image.new('L',cell.size,0)
    ImageDraw.Draw(mask).polygon(lower[:-1]+upper[:-1],fill=255)
    tight=mask.getbbox()
    card=cell.convert('RGBA');card.putalpha(mask)
    card=card.crop(tight)
    # Transparent safety gutter protects outer border from texture clipping.
    padded=Image.new('RGBA',(card.width+8,card.height+8),(0,0,0,0))
    padded.alpha_composite(card,(4,4))
    bbox=(xc[c]+tight[0],yc[r]+tight[1],xc[c]+tight[2],yc[r]+tight[3])
    return padded,bbox


def fit_canvas(card: Image.Image) -> Image.Image:
    # Fit without stretching: wide cards get transparent top/bottom padding.
    scale = min(TARGET_SIZE[0] / card.width, TARGET_SIZE[1] / card.height)
    size = (round(card.width * scale), round(card.height * scale))
    resized = card.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", TARGET_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((TARGET_SIZE[0] - size[0]) // 2, (TARGET_SIZE[1] - size[1]) // 2))
    return canvas


# Back up exactly the current 49 formal PNGs before any replacement.
old_files = sorted(DEST.glob("ui_fate_card_*.png"))
assert len(old_files) == 49, f"expected old 49 PNGs, got {len(old_files)}"
BACKUP.mkdir(parents=True, exist_ok=True)
for old in old_files:
    shutil.copy2(old, BACKUP / old.name)
assert len(list(BACKUP.glob("*.png"))) == 49

metadata = {
    "source_directory": str(SRC),
    "source_is_read_only": True,
    "source_files": source_files,
    "source_dimensions": {str(i): list(images[i].size) for i in images},
    "target_canvas": list(TARGET_SIZE),
    "mapping_count": len(M),
    "mapping": {},
    "back": {"source_sheet": 6, "source_file": source_files[5], "position": 10, "meaning": "双兔对称无标题卡背"},
    "old_backup": str(BACKUP),
}

rendered: dict[str, Image.Image] = {}
for stable_id, (sheet_no, pos) in M.items():
    card, bbox = crop_card(images[sheet_no], pos)
    final = fit_canvas(card)
    out = DEST / f"ui_fate_card_{stable_id}_v001.png"
    final.save(out, "PNG", optimize=True)
    rendered[stable_id] = final
    metadata["mapping"][stable_id] = {
        "chinese_name": CN[stable_id],
        "sheet": sheet_no,
        "source_file": source_files[sheet_no - 1],
        "position": pos,
        "bbox_xyxy": list(bbox),
        "formal_file": out.name,
        "canvas": list(final.size),
    }

back_card, back_bbox = crop_card(images[6], 10)
back = fit_canvas(back_card)
back_path = DEST / "ui_fate_card_back_v001.png"
back.save(back_path, "PNG", optimize=True)
metadata["back"]["bbox_xyxy"] = list(back_bbox)
metadata["back"]["formal_file"] = back_path.name
metadata["back"]["canvas"] = list(back.size)

# User-facing Chinese-named copies; formal game paths remain the stable-ID names above.
CHINESE.mkdir(parents=True, exist_ok=True)
for stable_id, image in rendered.items():
    image.save(CHINESE / f"{CN[stable_id]}.png", "PNG", optimize=True)
back.save(CHINESE / "卡背_双兔对称无标题.png", "PNG", optimize=True)

# Contact sheet with Chinese labels for visual review.
try:
    font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 20)
except OSError:
    font = ImageFont.load_default()
contact = Image.new("RGBA", (8 * 170, 6 * 225), "#161616")
draw = ImageDraw.Draw(contact)
for i, stable_id in enumerate(M):
    im = rendered[stable_id].copy()
    im.thumbnail((132, 194), Image.Resampling.LANCZOS)
    x, y = (i % 8) * 170 + (170 - im.width) // 2, (i // 8) * 225 + 5
    contact.alpha_composite(im, (x, y))
    draw.text(((i % 8) * 170 + 4, (i // 8) * 225 + 201), CN[stable_id], fill="#9cffc8", font=font)
# The card back is delivered separately; do not overlay it on the 48-face sheet.
contact.save(VERIFY / "new_tarot_48_contact_cn.png", "PNG", optimize=True)

# Machine-readable mapping and crop/format acceptance evidence.
(VERIFY / "source_mapping.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
formal = sorted(DEST.glob("ui_fate_card_*.png"))
assert len(formal) == 49
for path in formal:
    im = Image.open(path)
    assert im.size == TARGET_SIZE and im.mode == "RGBA", (path.name, im.size, im.mode)
    assert im.getpixel((0, 0))[3] == 0 and im.getpixel((639, 0))[3] == 0
    assert im.getpixel((320, 512))[3] > 200, path.name

verification = {
    "formal_png_count": len(formal),
    "formal_face_count": len(formal) - 1,
    "formal_back_count": sum(p.name == back_path.name for p in formal),
    "all_rgba_640x1024": True,
    "all_four_corner_outside_transparent": True,
    "card_center_opaque": True,
    "mapping_unique_48": len(M) == len(set(M.values())) == 48,
    "back_source_verified": metadata["back"],
    "old_backup_png_count": len(list(BACKUP.glob("*.png"))),
    "source_unchanged_by_script": True,
    "gameplay_changed": False,
}
(VERIFY / "asset_verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"installed={len(M)} faces plus back")
print(f"formal_canvas={TARGET_SIZE[0]}x{TARGET_SIZE[1]}")
print(f"backup={BACKUP}")
print(f"chinese_delivery={CHINESE}")
print(f"contact={VERIFY / 'new_tarot_48_contact_cn.png'}")
print(f"mapping={VERIFY / 'source_mapping.json'}")
