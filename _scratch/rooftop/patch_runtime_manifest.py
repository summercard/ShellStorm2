import sys

P = (
    "assets/art/environments/tower_zones/rooftop/runtime/"
    "rooftop_100f_decorated_runtime_manifest.json"
)
b = open(P, "rb").read()


def B(s: str) -> bytes:
    return s.encode("utf-8")


subs = [
    B('"visual_instance_count": 112,'),
    B('"pipe_risers": 8'),
    B('"instance_count": 112,'),
    B('    "rotation_axis": "+Y",\r\n'),
    B("地砖组不重放 ⇒ 实机整块砖厚悬空。"),
]
news = [
    B('"visual_instance_count": 120,'),
    B('"pipe_risers": 16'),
    B('"instance_count": 120,'),
    B(
        '    "rotation_axis": "+Y (yaw)",\r\n'
        '    "tilt_axis": "+X (rotation_x_deg)",\r\n'
        '    "rotation_euler_contract": "Blender 默认 XYZ 序（Rz@Rx@Ry）；Godot 默认 YXZ 序'
        '（Ry@Rx@Rz）。同一实例同时给 ry 与 rz 会反转 Rx/Rz 次序 ⇒ 布局源只用 rotation_x_deg '
        '+ rotation_y_deg 两轴（rz 恒 0），两式逐角等价、1:1 透传；GLB 导入已把 Blender '
        '+Z（风扇）映射到 Godot +Y。",\r\n'
    ),
    B(
        "地砖组不重放 ⇒ 实机整块砖厚悬空。2026-09-21 二次修正：立管（pipe_riser）改为两段堆叠"
        "（下段 rotation_x_deg=180 倒装），合起来覆盖 0~9.89m 并落地 y=0；墙挂空调 "
        "rotation_x_deg=90 使顶部风扇朝外。"
    ),
]

for old, new in zip(subs, news):
    n = b.count(old)
    if n != 1:
        print("PATCH_FAIL count=%d for %r" % (n, old[:48].decode("utf-8", "replace")))
        sys.exit(1)
    b = b.replace(old, new)

open(P, "wb").write(b)
print("PATCH_OK bytes=%d CR=%d CRCRLF=%d" % (len(b), b.count(b"\r"), b.count(b"\r\r\n")))
