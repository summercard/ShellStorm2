import os

import bpy

KEEP_COLLECTION = '02_STAIRWELLS'
collection = bpy.data.collections.get(KEEP_COLLECTION)
if collection is None:
    raise RuntimeError(f'缺少白盒楼梯集合: {KEEP_COLLECTION}')

keep_objects = set(collection.all_objects)
removed = 0
for obj in list(bpy.context.scene.objects):
    if obj not in keep_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
        removed += 1

changed = True
while changed:
    changed = False
    for candidate in list(bpy.data.collections):
        if candidate == collection or candidate.name in {'02A_STAIR_SPECIAL_ROOFTOP_TO_FACILITY', '02B_STAIR_GENERIC_ROTATABLE'}:
            continue
        if not candidate.objects and not candidate.children:
            bpy.data.collections.remove(candidate)
            changed = True

for _ in range(3):
    try:
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except RuntimeError:
        break

bpy.context.scene['whitebox_scope'] = 'stairs_only'
bpy.context.scene['whitebox_cleanup_removed_objects'] = removed
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(bpy.data.filepath), check_existing=False)
print(f'WHITEBOX_CLEANUP_RESULT kept={len(bpy.context.scene.objects)} removed={removed}')
