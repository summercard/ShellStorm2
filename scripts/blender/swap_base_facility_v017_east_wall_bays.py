#!/usr/bin/env python3
"""Swap the adjacent east-wall door and plain bays in v017.

The north bay receives the door-wall assembly.  The adjacent SUPPLY 24H asset
travels to the south bay by itself; nearby Battery/Emergency cabinets are
outside scope and remain signature locked.
"""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "east_wall_bay_swap_acceptance.json"
ASSEMBLY = ROOT / "component_sets/east_door_wall_set/assembly_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve(): raise RuntimeError("must run with v017 open")
spec = importlib.util.spec_from_file_location("reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec); spec.loader.exec_module(reorg)

door_wall = reorg.package_by_slug("east_door_wall_module")
door = reorg.package_by_slug("east_personnel_security_door")
access = reorg.package_by_slug("east_door_access_control")
supply = reorg.package_by_slug("east_supply_24h_station")
retained = reorg.package_by_slug("retained_wall_system")
door_src = bpy.data.collections["v017_源资产包_east_personnel_security_door"]
access_src = bpy.data.collections["v017_源资产包_east_door_access_control"]
supply_src = bpy.data.collections["v017_源资产包_east_supply_24h_station"]
wall_src = bpy.data.collections["v017_源资产包_east_door_wall_module"]

south_anchor = bpy.data.objects.get("保留东墙_02")
north_anchor = bpy.data.objects.get("保留东墙_03")
door_root = bpy.data.objects.get("ENV-BASE99-WALL-DOOR-5X9_输出根节点.002")
door_mesh = bpy.data.objects.get("带门墙体_主体_金属哑光反光.002")
plain_root = next((o for o in north_anchor.children if "WALL-PLAIN-5X9_输出根节点" in o.name), None) if north_anchor else None
plain_mesh = next((o for o in plain_root.children if "普通墙体_主体" in o.name), None) if plain_root else None
if not all((south_anchor, north_anchor, door_root, door_mesh, plain_root, plain_mesh)):
    raise RuntimeError("adjacent east wall bay hierarchy is incomplete")

# Explicit allowed set: only the two wall bays, door assembly, and vending
# package may change.  Cabinets beside the old back-wall door are never added.
allowed = set(door_wall.objects) | set(door.objects) | set(access.objects) | set(supply.objects)
allowed |= set(door_src.objects) | set(access_src.objects) | set(supply_src.objects) | set(wall_src.objects)
allowed |= {south_anchor, north_anchor, plain_root, plain_mesh}
locked_before = {o.name: reorg.signature(o) for o in bpy.data.objects if o not in allowed}

# Swap *module contents* between stable east-wall anchors.  This retains the
# grid index and coordinate identity of each bay while exchanging visual type.
door_root.parent = north_anchor
plain_root.parent = south_anchor
reorg.move_object(south_anchor, retained)
reorg.move_object(north_anchor, door_wall)

# The lift door/control gear tracks the moved door wall (south -> north), while
# only the SUPPLY24H asset travels to the vacant southern bay.
door_delta = Vector((0.0, 5.0, 0.0))
supply_delta = Vector((0.0, -5.0, 0.0))
for obj in list(door.objects) + list(door_src.objects) + list(access.objects) + list(access_src.objects): obj.location += door_delta
for obj in list(supply.objects) + list(supply_src.objects): obj.location += supply_delta

# The editable wall source mirror follows the north door-wall anchor.  Its
# source-output mapping remains unique after the anchor rename.
source_anchor = bpy.data.objects.get("保留东墙_02__源")
if source_anchor is None: raise RuntimeError("missing door-wall source anchor")
source_anchor.name = "保留东墙_03__源"
source_anchor.location.y += 5.0

for package, anchor in ((door_wall, [15.0, 2.5, 0.0]), (door, [15.0, 2.5, 0.0]), (access, [15.0, 2.5, 0.0])):
    package["组件组锚点_m"] = anchor
door_wall["本批次范围"] = "v017相邻东墙格互换：带门墙模块移至北段保留东墙_03"
door["本批次范围"] = "v017随带门墙模块北移至东墙_03门洞"
access["本批次范围"] = "v017随东墙北段带门组件组北移；不合并入门体"
supply["本批次范围"] = "v017仅SUPPLY24H整包南移至原门墙南段；不带动电池柜与Emergency柜"

bpy.context.view_layer.update()
door_center, door_dims = reorg.bbox([bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"], bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光"]])
wall_center, wall_dims = reorg.bbox([door_mesh])
body = bpy.data.objects.get("SUPPLY24H_主体外壳")
if door_center != [15.0, 2.5, 1.25] or door_dims != [0.325, 2.2, 2.5]: raise RuntimeError(f"door bay interface mismatch {door_center} {door_dims}")
if wall_center != [15.0, 2.5, 4.5] or wall_dims != [1.1712, 5.0, 9.0]: raise RuntimeError(f"door wall bay mismatch {wall_center} {wall_dims}")
if body is None or (Vector(body.location) - Vector((13.52, -3.45, 1.78))).length > .001: raise RuntimeError(f"supply location mismatch {body.location if body else None}")

reorg.write_catalog(reorg.packages())
extra = {
 "architecture/east_door_wall_module": {"component_set":"base99_east_door_wall_set","component_set_role":"door_wall_module","scene_anchor_m":[15.0,2.5,0.0],"scene_bay":"保留东墙_03（北段）","swapped_with":"retained_wall_system/保留东墙_02"},
 "east_facilities/east_personnel_security_door": {"component_set":"base99_east_door_wall_set","component_set_role":"lift_door","host_wall_asset":"east_door_wall_module","scene_anchor_m":[15.0,2.5,0.0],"scene_bay":"保留东墙_03（北段）"},
 "east_facilities/east_door_access_control": {"component_set":"base99_east_door_wall_set","component_set_role":"door_access_control","host_wall_asset":"east_door_wall_module","scene_anchor_m":[15.0,2.5,0.0],"scene_bay":"保留东墙_03（北段）"},
 "east_facilities/east_supply_24h_station": {"component_set":None,"anchor_after_m":[13.52,-3.45,0.0],"moved_with":"east wall bay swap; package-only","excluded_nearby_assets":["battery cabinet","emergency cabinet"]},
}
for relative, additions in extra.items():
    path = ROOT / relative / "asset_manifest.json"; data=json.loads(path.read_text(encoding="utf-8")); data.update(additions); path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
assembly=json.loads(ASSEMBLY.read_text(encoding="utf-8")); assembly["anchor_m"]=[15.0,2.5,0.0]; assembly["east_wall_bay"]="保留东墙_03（北段）"; assembly["swap_note"]="带门墙组件由保留东墙_02移动到保留东墙_03；SUPPLY24H单独南移5m，未携带旁侧柜体。"; ASSEMBLY.write_text(json.dumps(assembly,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
catalog=json.loads(reorg.CATALOG.read_text(encoding="utf-8")); catalog["source"]="v017 east wall adjacent-bay swap"; catalog["scope"]="Door-wall component set moved from east bay 02 to adjacent north bay 03; only SUPPLY24H moved with the swap; nearby cabinets locked."; reorg.CATALOG.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

locked_after={o.name:reorg.signature(o) for o in bpy.data.objects if o.name in locked_before}
mismatches={n:{"before":locked_before[n],"after":locked_after.get(n)} for n in locked_before if locked_before[n]!=locked_after.get(n)}
if mismatches: raise RuntimeError(f"outside-scope changes: {sorted(mismatches)[:8]}")
packages=reorg.packages(); owners={}
for p in packages:
    for o in p.objects: owners.setdefault(o.name,[]).append(p.get("资产包键"))
multi={n:v for n,v in owners.items() if len(v)!=1}
if multi: raise RuntimeError(f"multi package objects: {multi}")
result={"status":"pass","lock":{"locked_count":len(locked_before),"locked_match":True,"mismatches":{}},"component_set":"base99_east_door_wall_set","door_wall":{"bay":"保留东墙_03","center_m":wall_center,"dimensions_m":wall_dims,"objects":sorted(o.name for o in door_wall.objects)},"door":{"center_m":door_center,"dimensions_m":door_dims},"supply":{"body_location_m":[round(float(v),4) for v in body.location],"moved_package_only":True},"excluded_cabinets_locked":True,"package_count":len(packages),"empty_packages":[p.get("资产包键") for p in packages if not p.objects],"multi_owner":multi}
REPORT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
bpy.context.scene["v017_iteration"]="east_wall_adjacent_bay_swap"; bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print(json.dumps(result,ensure_ascii=False))
