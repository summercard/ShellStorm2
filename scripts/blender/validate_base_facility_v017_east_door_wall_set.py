#!/usr/bin/env python3
"""Acceptance checks for the v017 east wall-door assembly contract."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
ASSEMBLY = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017/component_sets/east_door_wall_set/assembly_manifest.json"
REPORT = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017/east_door_wall_set_acceptance.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")
spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec); spec.loader.exec_module(reorg)
errors = []
required = {slug: reorg.package_by_slug(slug) for slug in ("east_door_wall_module", "east_personnel_security_door", "east_door_access_control", "east_supply_24h_station", "retained_wall_system")}
sources = {slug: bpy.data.collections.get(f"v017_源资产包_{slug}") for slug in ("east_door_wall_module", "east_personnel_security_door", "east_door_access_control", "east_supply_24h_station")}
if any(value is None for value in sources.values()): errors.append("missing source mirror package")
wall_names = {"保留东墙_03", "ENV-BASE99-WALL-DOOR-5X9_输出根节点.002", "带门墙体_主体_金属哑光反光.002"}
if {o.name for o in required["east_door_wall_module"].objects} != wall_names: errors.append("wall package content mismatch")
if any(name in required["retained_wall_system"].objects for name in wall_names): errors.append("east wall module remains mixed into retained-wall package")
door_names = {"东墙标准滑升门_主体_金属哑光反光", "东墙标准滑升门_状态灯_柔和自发光", "东墙滑升门_状态照明"}
if {o.name for o in required["east_personnel_security_door"].objects} != door_names: errors.append("door package content mismatch")
if len(required["east_door_access_control"].objects) != 17: errors.append("door access package object count mismatch")
if len(sources["east_door_wall_module"].objects) != 3 or len(sources["east_personnel_security_door"].objects) != 3 or len(sources["east_door_access_control"].objects) != 17: errors.append("source mirror count mismatch")

def box(objects):
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    lo = [min(p[i] for p in points) for i in range(3)]; hi = [max(p[i] for p in points) for i in range(3)]
    return [round((lo[i]+hi[i])/2,4) for i in range(3)], [round(hi[i]-lo[i],4) for i in range(3)]
wall_center, wall_dims = box([bpy.data.objects["带门墙体_主体_金属哑光反光.002"]])
door_center, door_dims = box([bpy.data.objects[n] for n in door_names if bpy.data.objects[n].type == "MESH"])
if wall_center != [15.0,2.5,4.5] or wall_dims != [1.051,5.0,9.0]: errors.append(f"wall interface mismatch {wall_center} {wall_dims}")
if door_center != [15.0,2.5,1.27] or door_dims != [0.898,2.04,2.34]: errors.append(f"door interface mismatch {door_center} {door_dims}")
for label, obj, half_depth in (("wall", bpy.data.objects["带门墙体_主体_金属哑光反光.002"], 0.5255), ("door", bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"], 0.4375)):
    values = [vertex.co.y for vertex in obj.data.vertices]
    if round(min(values), 4) != -half_depth or round(max(values), 4) != half_depth:
        errors.append(f"{label} is not the required symmetric double-sided geometry")
if (Vector(bpy.data.objects["SUPPLY24H_主体外壳"].location)-Vector((13.52,-3.45,1.78))).length > .001: errors.append("vending station occupies wrong current-v017 anchor")
for name in ("东墙标准滑升门_主体_金属哑光反光", "东墙标准滑升门_状态灯_柔和自发光", "东墙标准滑升门_主体_金属哑光反光__源", "东墙标准滑升门_状态灯_柔和自发光__源"):
    mesh = bpy.data.objects[name].data; uv = mesh.uv_layers.get("PaletteUV")
    if [u.name for u in mesh.uv_layers] != ["PaletteUV"] or mesh.uv_layers.active != uv or not uv.active_render: errors.append(f"palette layer contract failed {name}")
    for poly in mesh.polygons:
        values = [uv.data[i].uv for i in poly.loop_indices]; cols={int(v.x*10) for v in values}; rows={int(v.y*10) for v in values}
        area=abs(sum(values[i].x*values[(i+1)%len(values)].y-values[(i+1)%len(values)].x*values[i].y for i in range(len(values))))*.5
        if len(cols)!=1 or len(rows)!=1 or area<1e-7: errors.append(f"palette face failed {name}:{poly.index}"); break
lamp = bpy.data.objects["东墙滑升门_状态照明"]
if lamp.name not in required["east_personnel_security_door"].objects: errors.append("local state lamp not grouped with door")
if [round(float(v),4) for v in lamp.location] != [15.0,2.5,2.05]: errors.append("local state lamp is not centred in the double-sided east door")
manifest = json.loads(ASSEMBLY.read_text(encoding="utf-8")) if ASSEMBLY.is_file() else None
if not manifest or [m["asset_slug"] for m in manifest["members"]] != ["east_door_wall_module","east_personnel_security_door","east_door_access_control"]: errors.append("assembly manifest mismatch")
owners = {o.name:[c.get("资产包键") for c in o.users_collection if c.get("资产包")] for o in bpy.data.objects}
multiple = {n:v for n,v in owners.items() if len(v)>1}
if multiple: errors.append("multi-package object ownership")
result={"status":"pass" if not errors else "fail","component_set":"base99_east_door_wall_set","revision":"v017_east_copies_west_double_sided_003","package_count":len(reorg.packages()),"wall":{"center_m":wall_center,"dimensions_m":wall_dims,"core_depth_m":0.36},"door":{"center_m":door_center,"dimensions_m":door_dims,"slab_depth_m":0.62},"double_sided":True,"supply_body_location_m":[round(float(v),4) for v in bpy.data.objects["SUPPLY24H_主体外壳"].location],"light_owner":lamp.users_collection[0].name,"errors":errors}
REPORT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result,ensure_ascii=False))
if errors: raise RuntimeError("east wall-door set validation failed")
