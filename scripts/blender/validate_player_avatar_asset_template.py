"""Validate the open ShellStorm2 player/avatar template without mutating it."""

import bpy
import json


required_collections = {
    "角色资产规范母版_中文管理",
    "01_尺寸方向参照_只读",
    "02_制作组件_可编辑",
    "03_挂点与导出根",
    "90_展示环境",
}
required_sockets = {
    "SOCKET_Weapon", "SOCKET_StowedWeaponPrimary", "SOCKET_StowedWeaponSecondary",
    "SOCKET_Backpack", "SOCKET_LowerBody", "SOCKET_Hat", "SOCKET_Glasses",
    "SOCKET_EarL", "SOCKET_EarR",
}
root = bpy.data.objects.get("CHR_PlayerAvatar_Template_Source_v001")
failures = []
if root is None:
    failures.append("missing template root")
else:
    if abs(float(root.get("character_height_m", 0.0)) - 1.5) > 0.0001:
        failures.append("character height contract is not 1.5m")
    if root.get("blender_forward") != "-Y" or root.get("godot_forward") != "-Z":
        failures.append("forward-axis contract mismatch")
    if float(root.get("runtime_root_scale", 0.0)) != 1.0:
        failures.append("runtime root scale is not 1")
missing_collections = sorted(required_collections - {value.name for value in bpy.data.collections})
missing_sockets = sorted(required_sockets - {value.name for value in bpy.data.objects})
failures.extend("missing collection: " + value for value in missing_collections)
failures.extend("missing socket: " + value for value in missing_sockets)
payload = {
    "valid": not failures,
    "failures": failures,
    "unit_system": bpy.context.scene.unit_settings.system,
    "scale_length": bpy.context.scene.unit_settings.scale_length,
    "collection_count": len(bpy.data.collections),
    "socket_count": len(required_sockets - set(missing_sockets)),
}
print("PLAYER_AVATAR_TEMPLATE_VALIDATION=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
if failures:
    raise RuntimeError("; ".join(failures))
