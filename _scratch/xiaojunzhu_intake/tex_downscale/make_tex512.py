"""小僵尸 basecolor 贴图 2K -> 512。生成唯一权威 512 PNG，供源图 / GLB 内嵌 / blend 内嵌三处共用。"""
import hashlib
import pathlib

from PIL import Image

ROOT = pathlib.Path(r"I:\工作项目\shellstrom2\ShellStorm2")
PKG = ROOT / "assets/art/enemies/normal_enemy_3d/melee_chaser"
SRC_2K = PKG / "source/model/textures/enm_melee_fungboar01_basecolor_v002.png"
OUT_DIR = ROOT / "_scratch/tex512"
OUT = OUT_DIR / "enm_melee_fungboar01_basecolor_v002.png"

TARGET = 512

OUT_DIR.mkdir(parents=True, exist_ok=True)

im = Image.open(SRC_2K)
print("source:", im.size, im.mode, "icc=", bool(im.info.get("icc_profile")))
assert im.size == (2048, 2048), im.size

im512 = im.resize((TARGET, TARGET), Image.LANCZOS)
im512.save(OUT, format="PNG", optimize=True, compress_level=9)

raw = OUT.read_bytes()
print("out:", OUT)
print("bytes:", len(raw), "sha256:", hashlib.sha256(raw).hexdigest())

chk = Image.open(OUT)
print("verify:", chk.size, chk.mode, "png hdr ok:", raw[:8].hex())
