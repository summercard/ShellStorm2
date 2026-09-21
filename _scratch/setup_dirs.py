import os, shutil

out = []
def log(*a):
    out.append(" ".join(str(x) for x in a))

PROJ = "I:/工作项目/shellstrom2/ShellStorm2"
base = os.path.join(PROJ, "assets/art/enemies/normal_enemy_3d/ranged_caster")
dirs = [
    "source/model/textures",
    "source/animation",
    "components",
    "previews",
]
for d in dirs:
    p = os.path.join(base, d)
    os.makedirs(p, exist_ok=True)
    log("mkdir", p, os.path.isdir(p))

# copy FBX + JPEG (original untouched)
src_fbx = r"C:/Users/zhuangmenghong/Desktop/保安僵尸/tripo_convert_4b763a81-adc3-4d88-95dc-f269024b8c4b.fbx"
src_jpg = r"C:/Users/zhuangmenghong/Desktop/保安僵尸/tripo_convert_4b763a81-adc3-4d88-95dc-f269024b8c4b.fbm\安保警卫3d模型_basecolor.JPEG"
dst_fbx = os.path.join(base, "source/model/enm_ranged_sporeshooter01_source_v001.fbx")
dst_jpg = os.path.join(base, "source/model/textures/enm_ranged_sporeshooter01_basecolor_v001.jpeg")

for s, d in [(src_fbx, dst_fbx), (src_jpg, dst_jpg)]:
    if os.path.isfile(s):
        shutil.copy2(s, d)
        log("copy OK", s, "->", d, os.path.getsize(d))
    else:
        log("MISSING", s)

# list result
log("---- tree ----")
for root, ds, fs in os.walk(base):
    rel = os.path.relpath(root, PROJ)
    log(rel + "/")
    for f in sorted(fs):
        log("   " + f)

with open("I:/工作项目/shellstrom2/ShellStorm2/_scratch/setup_dirs_result.log", "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
