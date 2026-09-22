# -*- coding: utf-8 -*-
"""actor.face 支持「朝向一个目标点」（房间相对 / 显式世界坐标）。

给目标点就压过 `yaw_deg` / `relative`；不给则行为一字不变。
"""
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeAdapter3D.gd"

# ---- 1) 在 _actor_face 前插入两个 helper ----
ANCHOR_FN = "func _actor_face(params: Dictionary) -> Dictionary:\n"

HELPERS = '''## 解析 `actor.face` 的目标点：给了就返回世界坐标 `Vector3`，没给返回 `null`
## （= 走 `yaw_deg` 老通道）。
## · `to_point_room` + `to_point_offset` —— **房间相对**（推荐）。房间是运行时生成的，
##   写死世界坐标会在换布局后**静默指偏**；世界坐标 = `room.to_global(offset)`。
## · `point_m` —— 显式世界坐标 `[x, y, z]`（优先级最高）。
## 为什么要有这条：「对着地上的某件东西说」不能写死相对角度 ——
## 玩家出生朝向由鼠标决定、不确定，只有目标点反解出来的绝对方位才稳。
func _resolve_face_point(params: Dictionary) -> Variant:
	var raw_point: Variant = params.get("point_m", null)
	if raw_point is Array and (raw_point as Array).size() == 3:
		var point: Array = raw_point
		return Vector3(float(point[0]), float(point[1]), float(point[2]))
	var room_id := str(params.get("to_point_room", ""))
	if room_id.is_empty():
		return null
	var room := room_node(room_id)
	if room == null:
		_warn("actor.face：找不到房间 %s，退回 yaw_deg。" % room_id)
		return null
	var raw_offset: Variant = params.get("to_point_offset", null)
	if not (raw_offset is Array) or (raw_offset as Array).size() != 3:
		_warn("actor.face：to_point_offset 需要 [x, y, z]，退回 yaw_deg。")
		return null
	var offset: Array = raw_offset
	return room.to_global(Vector3(float(offset[0]), float(offset[1]), float(offset[2])))


## 世界点 → `aim_yaw`。与 `Player3D` 同口径（`aim_yaw = atan2(-dir.x, -dir.z)`），
## 只取水平分量；点与角色重合时保持当前朝向不动（不产生 NaN）。
func _yaw_towards(from: Vector3, to: Vector3) -> float:
	var delta := to - from
	delta.y = 0.0
	if delta.length_squared() <= 0.0001:
		return float(_facing_base_yaw)
	delta = delta.normalized()
	return atan2(-delta.x, -delta.z)


'''

# ---- 2) _actor_face 里的 yaw 解算改成三分支 ----
YAW_OLD = (
    "\tvar target_yaw := deg_to_rad(float(params.get(\"yaw_deg\", 0.0)))\n"
    "\tif bool(params.get(\"relative\", false)):\n"
    "\t\ttarget_yaw += _facing_base_yaw\n"
)
YAW_NEW = (
    "\tvar target_yaw := deg_to_rad(float(params.get(\"yaw_deg\", 0.0)))\n"
    "\tvar face_point: Variant = _resolve_face_point(params)\n"
    "\tif face_point != null:\n"
    "\t\t# 给了目标点就是**绝对**朝向，压过 yaw_deg / relative。\n"
    "\t\ttarget_yaw = _yaw_towards(actor.global_position, face_point as Vector3)\n"
    "\telif bool(params.get(\"relative\", false)):\n"
    "\t\ttarget_yaw += _facing_base_yaw\n"
)


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "_resolve_face_point" in text:
        print("ALREADY PATCHED")
        return 0

    n_fn = text.count(ANCHOR_FN)
    if n_fn != 1:
        print("ABORT: _actor_face 锚点命中 %d" % n_fn)
        return 3
    text = text.replace(ANCHOR_FN, HELPERS + ANCHOR_FN)

    n_yaw = text.count(YAW_OLD)
    if n_yaw != 1:
        print("ABORT: yaw 解算锚点命中 %d" % n_yaw)
        return 4
    text = text.replace(YAW_OLD, YAW_NEW)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 5
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
