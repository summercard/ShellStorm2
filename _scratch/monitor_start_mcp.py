import bpy,addon_utils
addon_utils.enable('addon',default_set=False,persistent=True)
bpy.context.scene.blendermcp_port=9876
bpy.ops.blendermcp.start_server()
print('MONITOR_MCP_READY',bpy.data.filepath)
