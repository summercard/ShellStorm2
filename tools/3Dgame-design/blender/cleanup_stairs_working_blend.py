import os
import sys

import bpy

KEEP_COLLECTIONS = ['楼梯A_100至99层_资产包', '楼梯B_99至98层_资产包']
missing = [name for name in KEEP_COLLECTIONS if bpy.data.collections.get(name) is None]
if missing:
    raise RuntimeError(f'缺少楼梯资产包集合: {missing}')

keep_objects = set()
for name in KEEP_COLLECTIONS:
    keep_objects.update(bpy.data.collections[name].all_objects)

for obj in list(bpy.context.scene.objects):
    if obj not in keep_objects:
        bpy.data.objects.remove(obj, do_unlink=True)

changed = True
while changed:
    changed = False
    for collection in list(bpy.data.collections):
        if collection.name in KEEP_COLLECTIONS:
            continue
        if not collection.objects and not collection.children:
            bpy.data.collections.remove(collection)
            changed = True

for _ in range(3):
    try:
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except RuntimeError:
        break

bpy.context.scene['3dgame_design_cleanup'] = 'only_stairwell_asset_packages'
bpy.context.scene['3dgame_design_cleanup_removed_objects'] = 117
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(bpy.data.filepath), check_existing=False)
print(f'CLEANUP_RESULT objects={len(bpy.context.scene.objects)} collections={len(bpy.data.collections)}')
