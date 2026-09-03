import bpy


print('FILE', bpy.data.filepath)
print('ACTIVE_CAMERA', bpy.context.scene.camera.name if bpy.context.scene.camera else None)
print('TARGET_COLLECTIONS')
for collection in bpy.data.collections:
    name = collection.name.lower()
    if any(token in name for token in ('楼梯', 'underloft', '长凳', '公告', '留言', '设备柜', '层架', '收纳')):
        print(collection.name, len(collection.objects), len(collection.children))

print('LEFT_STAIR_SPATIAL_OBJECTS')
for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
    x, y, z = obj.location
    if -15.2 <= x <= -4.0 and 5.0 <= y <= 15.2 and -0.2 <= z <= 7.4:
        print(
            obj.name,
            obj.type,
            tuple(round(value, 3) for value in obj.location),
            tuple(round(value, 3) for value in obj.dimensions),
            [collection.name for collection in obj.users_collection],
        )

print('RIGHT_STAIR_SPATIAL_OBJECTS')
for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
    x, y, z = obj.location
    if 11.8 <= x <= 14.8 and 9.8 <= y <= 15.2 and 5.8 <= z <= 9.6:
        print(
            obj.name,
            obj.type,
            tuple(round(value, 3) for value in obj.location),
            tuple(round(value, 3) for value in obj.dimensions),
            [collection.name for collection in obj.users_collection],
        )
