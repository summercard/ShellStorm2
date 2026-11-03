shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float angle = atan(p.y, p.x);
    float rim = 0.86 + sin(angle * 7.0) * 0.05 + cos(angle * 11.0) * 0.03;
    float d = length(p);
    ALPHA = (1.0 - smoothstep(rim - 0.1, rim, d)) * 0.92;
    float slick = sin(p.x * 9.0 + p.y * 7.0 + sin(p.y * 12.0) + TIME * 0.25);
    ALBEDO = mix(vec3(0.018, 0.026, 0.035), vec3(0.11, 0.22, 0.24), slick * 0.5 + 0.5);
    METALLIC = 0.5;
    ROUGHNESS = 0.16;
    EMISSION = vec3(0.02, 0.055, 0.06) * smoothstep(0.65, 0.83, d);
}
