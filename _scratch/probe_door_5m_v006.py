import bpy
import sys

BLEND = r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_zones\battle\source\common_components\v006\env_battle_common_components_source_v006.blend"

bpy.ops.wm.open_mainfile(filepath=BLEND)

print("=" * 70)
print("BLEND:", BLEND)
print("=" * 70)

print("\n=== 全部 collections ===")
for c in bpy.data.collections:
    print("  ", repr(c.name), "objects=", len(c.objects))

print("\n=== 寻找 door_5m 相关 collection ===")
targets = [c for c in bpy.data.collections if "door_5m" in c.name]
for c in targets:
    print(f"\n--- collection {c.name!r} ---")
    print("  objects:", [o.name for o in c.objects])
    for o in c.objects:
        print(f"    obj={o.name!r} type={o.type}")
        print(f"      loc={tuple(round(v,4) for v in o.location)}")
        print(f"      rot_euler={tuple(round(v,4) for v in o.rotation_euler)}")
        print(f"      scale={tuple(round(v,4) for v in o.scale)}")
        print(f"      dimensions={tuple(round(v,4) for v in o.dimensions)}")
        if o.type == 'MESH':
            me = o.data
            print(f"      verts={len(me.vertices)} polys={len(me.polygons)}")
            print(f"      material_slots={[s.material.name if s.material else None for s in o.material_slots]}")
            print(f"      uv_layers={[u.name for u in me.uv_layers]}")
            print(f"      has_custom_normals={me.has_custom_normals}")
        if o.parent:
            print(f"      parent={o.parent.name!r} parent_type={o.parent_type}")
    print("  children collections:", [ch.name for ch in c.children])

print("\n=== 场景里跟门扇有关的对象（按名字）===")
for o in bpy.data.objects:
    if "门扇" in o.name or "door_5m" in o.name:
        colls = [c.name for c in o.users_collection]
        print(f"  {o.name!r} type={o.type} collections={colls} hide_viewport={o.hide_viewport} hide_render={o.hide_render}")

print("\n=== 全部材质 ===")
for m in bpy.data.materials:
    print("  ", repr(m.name), "use_nodes=", m.use_nodes)

print("\n=== 全部 scene ===")
for s in bpy.data.scenes:
    print("  ", repr(s.name), "objects=", len(s.objects))

print("\nDONE")
