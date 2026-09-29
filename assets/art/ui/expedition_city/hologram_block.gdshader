shader_type spatial;
render_mode unshaded, cull_back;
uniform float deployment = 0.0;
uniform float clock = 0.0;
uniform vec4 tint : source_color = vec4(0.01, 0.55, 1.0, 1.0);
uniform float wire_only = 0.0;
varying vec3 local;
varying vec3 surface_normal;
varying vec4 data;
varying float reveal;
void vertex() {
 local = VERTEX;
 surface_normal = NORMAL;
 data = INSTANCE_CUSTOM;
 float rise = smoothstep(data.x, data.x + 0.2, deployment);
 reveal = rise;
 float wave = 1.0 + 0.045 * sin(clock * 1.7 + data.y * 6.283) + 0.02 * sin(clock * 2.8 + data.x * 9.0);
 VERTEX.y = (VERTEX.y + 0.5) * max(0.001, rise) * wave - 0.5 - data.w * (1.0 - rise);
}
void fragment() {
 if (reveal < 0.002) { discard; }
 vec3 edge_dist = 0.5 - abs(local);
 vec3 n = abs(surface_normal);
 float edge = n.x > 0.5 ? min(edge_dist.y, edge_dist.z) : (n.y > 0.5 ? min(edge_dist.x, edge_dist.z) : min(edge_dist.x, edge_dist.y));
 float outline = 1.0 - smoothstep(0.004, 0.021, edge);
 float windows = step(0.87, fract(local.y * 11.0 + data.z * 5.0)) * step(0.83, fract((local.x + local.z) * 7.0 + data.y * 5.0));
 float scan = pow(max(0.0, 1.0 - abs(fract((local.y + 0.5) * 0.55 - clock * 0.24 + data.y) - 0.5) * 2.0), 28.0);
 vec3 color = tint.rgb * (mix(0.02, 0.008, wire_only) + outline * 4.5 + windows * 2.4 + scan * 0.7);
 ALBEDO = vec3(0.002, 0.004, 0.012) + color * smoothstep(0.0, 0.8, reveal);
 EMISSION = color * (0.55 + 0.45 * deployment);
}
