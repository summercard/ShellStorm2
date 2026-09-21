import shutil, os, sys

out = []
def log(*a):
    s = " ".join(str(x) for x in a)
    out.append(s.encode("ascii", "replace").decode("ascii"))

try:
    log("== shutil.which ==")
    for name in ("blender", "blender.exe"):
        try:
            loc = shutil.which(name)
            log("  %s -> %s" % (name, loc))
        except Exception as e:
            log("  %s ERR %s" % (name, e))

    roots = [
        "C:/Program Files",
        "C:/Program Files (x86)",
        "C:/Blender Foundation",
        "C:/Users/zhuangmenghong/AppData/Local",
        "C:/Users/zhuangmenghong/AppData/Roaming",
        "C:/Users/zhuangmenghong/.workbuddy",
        "C:/Users/zhuangmenghong",
        "D:/Program Files",
        "D:/Program Files (x86)",
        "C:/",
    ]
    log("== bounded scan (max depth 6) ==")
    hits = set()
    for r in roots:
        if not os.path.isdir(r):
            continue
        try:
            for dirpath, dirnames, filenames in os.walk(r):
                if "blender.exe" in filenames:
                    hits.add(os.path.join(dirpath, "blender.exe"))
                d = dirpath[len(r):].count(os.sep)
                if d > 6:
                    dirnames[:] = []
        except Exception as e:
            log("  scan %s ERR %s" % (r, e))
    for h in sorted(hits):
        log("  HIT %s" % h)
    if not hits:
        log("  NONE")

    # also check common WorkBuddy/portable installs
    log("== extra checks ==")
    for p in os.environ.get("PATH", "").split(os.pathsep):
        if "blender" in p.lower():
            log("  PATH has blender dir: %s" % p)
except Exception as e:
    log("FATAL %s" % e)

with open("I:/工作项目/shellstrom2/ShellStorm2/_scratch/find_blender_result.log", "w", encoding="ascii") as f:
    f.write("\n".join(out) + "\n")
