import bpy, sys
paths=sys.argv[sys.argv.index('--')+1:]
TARGET_COLLECTIONS={"63_设备蒸汽动效组_资产包","v017_源资产包_equipment_steam_fx"}

def is_target_collection(name: str) -> bool:
    lowered=name.lower()
    return name in TARGET_COLLECTIONS or "equipment_steam" in lowered or "设备蒸汽" in name

def is_target_object(name: str) -> bool:
    return "equipment_steam" in name.lower() or name.startswith("设备蒸汽_") or "设备蒸汽" in name
for path in paths:
    bpy.ops.wm.open_mainfile(filepath=path)
    removed_objects=[]
    removed_collections=[]
    for collection in list(bpy.data.collections):
        if not is_target_collection(collection.name):
            continue
        for obj in list(collection.objects):
            removed_objects.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
        removed_collections.append(collection.name)
        bpy.data.collections.remove(collection)
    for obj in list(bpy.data.objects):
        if is_target_object(obj.name):
            removed_objects.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)
    print('STEAM_REMOVED',path,'collections',len(removed_collections),'objects',len(removed_objects))
