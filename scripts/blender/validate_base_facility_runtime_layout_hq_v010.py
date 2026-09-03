#!/usr/bin/env python3
"""Task-level validation for Base 99 loft/stair pass v010."""
import hashlib, json
from pathlib import Path
import bpy

PROJECT=Path("/Users/summercards/ShellStorm2")
V009=PROJECT/"source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v009.blend"
V010=PROJECT/"source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
ROOT=PROJECT/"source/art/blender/base_facility_layout/component_packages_v010"
REPORT=PROJECT/"outputs/verification/base_facility_runtime_layout_hq_v010/base_facility_runtime_layout_hq_v010_validation.json"
OUT9="02_游戏输出_独立资产包_v009"; OUT10="02_游戏输出_独立资产包_v010"
OLD={"metal_bed_storage","bed_privacy_curtain","loft_bar_table","loft_bar_stool_01","loft_bar_stool_02","loft_workbench","loft_computer_terminal","loft_radio","loft_first_aid_kit","loft_fire_extinguisher","loft_supply_cabinet"}
REQ={"loft_bed_and_bedding","loft_nightstand","loft_bedside_lamp","loft_bedside_rug","loft_striped_privacy_curtain","loft_lounge_sofa","loft_coffee_table","loft_lounge_rug","loft_pouf_01","loft_pouf_02","loft_side_table","loft_computer_workstation","loft_office_chair","loft_good_vibes_neon","loft_medical_cabinet","loft_battery_cabinet","loft_food_cabinet","loft_storage_crate_01","loft_storage_crate_02","loft_wall_utility_decor","loft_hanging_plant","east_upper_transition_stair"}

def packs(root):
    out=[]
    def walk(c):
        if c.get("资产包"): out.append(c)
        for q in c.children: walk(q)
    walk(root); return out

def sig(o):
    data=None
    if o.type=="MESH":
        cs=tuple(round(float(c),6) for v in o.data.vertices for c in v.co)
        data=(len(o.data.vertices),len(o.data.polygons),hashlib.sha256(repr(cs).encode()).hexdigest(),tuple(m.name if m else None for m in o.data.materials),hashlib.sha256(bytes(p.material_index%256 for p in o.data.polygons)).hexdigest())
    anim=[]
    if o.animation_data and o.animation_data.action:
        for f in o.animation_data.action.fcurves: anim.append((f.data_path,f.array_index,tuple((round(k.co.x,4),round(k.co.y,6)) for k in f.keyframe_points)))
    return {"type":o.type,"parent":o.parent.name if o.parent else None,"matrix":[round(float(c),7) for row in o.matrix_world for c in row],"dimensions":[round(float(c),7) for c in o.dimensions],"data":data,"animation":anim}

def capture(path,outname,target_names=None):
    bpy.ops.wm.open_mainfile(filepath=str(path)); root=bpy.data.collections[outname]; ps=packs(root); targets=set(target_names or ())
    if outname==OUT9:
        for p in ps:
            if p.get("资产包键") in OLD: targets.update(o.name for o in p.objects)
    d={}
    for p in ps:
        for o in p.objects:
            if o.name not in targets and not o.get("v010_scope"): d[o.name]=sig(o)
    return d,targets

def rd(o,a): return [round(float(v),3) for v in getattr(o,a)]

def main():
    before,targets=capture(V009,OUT9); after,_=capture(V010,OUT10,targets); errors=[]
    changed=sorted(k for k in before.keys()&after.keys() if before[k]!=after[k]); added=sorted(after.keys()-before.keys()); removed=sorted(before.keys()-after.keys())
    if changed or added or removed: errors.append(f"locked mismatch changed={changed[:10]} added={added[:10]} removed={removed[:10]}")
    root=bpy.data.collections[OUT10]; ps=packs(root); slugs=[p.get("资产包键") for p in ps]
    if len(ps)!=102: errors.append(f"packages={len(ps)} expected=102")
    if len(slugs)!=len(set(slugs)): errors.append("duplicate slugs")
    miss=sorted(REQ-set(slugs));
    if miss: errors.append(f"missing={miss}")
    empty=[p.name for p in ps if not p.objects]
    if empty: errors.append(f"empty={empty}")
    floor=sum(p.get("资产类别")=="floor" for p in ps)
    if floor!=36: errors.append(f"floor={floor}")
    owners={}
    for p in ps:
        for o in p.objects: owners.setdefault(o.name,[]).append(p.name)
    multi={n:x for n,x in owners.items() if len(x)!=1}
    if multi: errors.append(f"multi ownership={dict(list(multi.items())[:10])}")
    manifests=list(ROOT.glob("*/*/asset_manifest.json"))
    if len(manifests)!=102: errors.append(f"manifests={len(manifests)}")
    mslugs={json.loads(p.read_text(encoding="utf-8"))["asset_slug"] for p in manifests}
    if mslugs!=set(slugs): errors.append("manifest/catalog slug mismatch")
    expected={
      "二楼床_厚重金属床框":([-.3,11.5,6.57],[4.55,2.25,.3]),
      "二楼沙发_加厚底座":([6.05,11.6,6.43],[4.05,1.75,.55]),
      "二楼茶几_木质台面":([6.1,8.75,6.72],[3.0,1.45,.18]),
      "二楼工位_厚实桌面":([9.3,13.6,6.88],[4.1,1.15,.18]),
      "L梯_西北转角平台":([-13.8,13.8,2.925],[2.0,2.0,.24]),
      "L梯_阁楼顶层接驳平台":([-6.52,13.8,6.045],[3.44,2.0,.09]),
      "二楼东侧上行梯_底部无缝压板":([13.15,9.37,6.08],[1.82,.32,.055]),
      "二楼东侧上行梯_顶部接驳平台":([13.15,14.45,8.94],[2.05,1.05,.16]),
    }
    transforms={}
    for n,(l,d) in expected.items():
        o=bpy.data.objects.get(n)
        if not o: errors.append(f"missing key={n}"); continue
        transforms[n]={"location":rd(o,"location"),"dimensions":rd(o,"dimensions")}
        if rd(o,"location")!=l or rd(o,"dimensions")!=d: errors.append(f"transform {n}={transforms[n]} expected={(l,d)}")
    # East stair and storage remain separated; lower plate overlaps platform edge slightly for a seamless interface.
    crate=bpy.data.objects.get("二楼收纳箱02_主体"); step=bpy.data.objects.get("二楼东侧上行梯_踏步_10")
    clearance=round((step.location.x-step.dimensions.x/2)-(crate.location.x+crate.dimensions.x/2),3) if crate and step else -1
    if clearance<.2: errors.append(f"east stair/storage clearance={clearance}")
    sign=bpy.data.objects.get("L梯v010_STAY_CURIOUS标识_自发光")
    if not sign or round(float(sign.rotation_euler.z),4)!=round(-3.141592653589793/2,4): errors.append("west-wall stair sign orientation")
    report={"asset_id":"ENV-BASE99-ART-LAYOUT-3D","version":"v010","scope":"loft facilities and stairs only","status":"PASS" if not errors else "FAIL","locked_object_count_v009":len(before),"locked_object_count_v010":len(after),"locked_changed":changed,"locked_added":added,"locked_removed":removed,"package_count":len(ps),"floor_tile_package_count":floor,"manifest_count":len(manifests),"v010_scope_object_count":sum(bool(o.get("v010_scope")) for o in bpy.data.objects),"east_stair_storage_clearance_m":clearance,"key_transforms":transforms,"errors":errors}
    REPORT.parent.mkdir(parents=True,exist_ok=True); REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); print(json.dumps(report,ensure_ascii=False,indent=2))
    if errors: raise RuntimeError("v010 validation failed")

if __name__=="__main__": main()
