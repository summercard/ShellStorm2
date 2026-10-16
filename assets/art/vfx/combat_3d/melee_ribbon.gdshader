shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.6,0.9,1.0,1.0);
uniform float opacity = 1.0;
uniform float arc = 0.7;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 float a = (atan(local_position.z, local_position.x) + 3.141593) / 6.283186;
 if (a > arc) { discard; }
 float edge = smoothstep(0.0,0.06,a) * (1.0-smoothstep(arc-0.12,arc,a));
 ALBEDO = tint.rgb; EMISSION = tint.rgb * 0.35;
 ALPHA = opacity * tint.a * edge;
}
