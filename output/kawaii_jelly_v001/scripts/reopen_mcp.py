import bpy

def start():
 if not (hasattr(bpy.types,'blendermcp_server') and bpy.types.blendermcp_server and bpy.types.blendermcp_server.running):bpy.ops.blendermcp.start_server()
 return None
bpy.app.timers.register(start,first_interval=1.5)
