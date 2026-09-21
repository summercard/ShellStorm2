import math
from mathutils import Euler, Vector


def show(order, tip_deg, yaw_deg):
    e = Euler((math.radians(tip_deg), 0.0, math.radians(yaw_deg)), order)
    m = e.to_matrix()

    def col(i):
        return Vector((m[0][i], m[1][i], m[2][i]))

    print(
        "B_ORDER order=%s tip=%s yaw=%s  +X->%s  +Y->%s  +Z->%s"
        % (
            order,
            tip_deg,
            yaw_deg,
            tuple(round(v, 4) for v in col(0)),
            tuple(round(v, 4) for v in col(1)),
            tuple(round(v, 4) for v in col(2)),
        )
    )


show("XYZ", 90, 0)
show("XYZ", 90, 90)
show("XYZ", 90, -90)
show("XYZ", -90, 0)
