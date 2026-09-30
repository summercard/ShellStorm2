shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// Continuous world cloud + mist. Density, extinction and lighting are separate.
uniform vec4 highlight_color : source_color = vec4(0.90, 0.93, 0.97, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.28, 0.43, 0.62, 1.0);
uniform float cloud_opacity = 0.96;
uniform float density_scale = 0.060;
uniform float shape_seed = 1.0;
uniform float flow_time = 0.0;
uniform float daylight = 1.0;
uniform vec3 tint = vec3(1.0);
uniform vec3 light_direction = vec3(-0.4, 0.8, 0.3);
uniform sampler3D building_distance : filter_linear, repeat_disable;
uniform sampler3D shape_noise : filter_linear, repeat_enable;
uniform sampler2D billow_density : filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 mask_origin = vec3(-240.0, -110.0, -320.0);
uniform vec3 mask_size = vec3(480.0, 160.0, 540.0);
uniform float sheet_mode = 1.0;
uniform int ray_steps = 96;
uniform int light_steps = 4;
varying vec3 local_surface;
varying vec3 local_camera;

float building_clearance(vec3 w) {
    vec3 uv = (w - mask_origin) / mask_size;
    if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) { return 16.0; }
    return texture(building_distance, uv).r * 16.0;
}
vec3 field(vec3 w) {
    vec3 wind = vec3(flow_time * 0.18, sin(flow_time * 0.023) * 0.8, -flow_time * 0.11);
    return texture(shape_noise, (w + wind) / 168.0).rgb;
}
float raw_density(vec3 p, vec3 w) {
    float phase = shape_seed * 1.731;
    vec3 n = field(w);
    vec2 uv = (w.xz + vec2(flow_time * 0.12, -flow_time * 0.08)) / 90.0;
    // Mirrored repetition guarantees value continuity for the generated density field.
    float painted = textureLod(billow_density, abs(fract(uv * 0.5) * 2.0 - 1.0), 1.0).r;
    float density = 0.0;
    if (sheet_mode > 0.5) {
        float threshold = mix(0.20, 0.74, smoothstep(-52.0, -15.0, w.y));
        float structure = n.r * 0.73 + n.g * 0.12 + painted * 0.15;
        float erosion = (1.0 - n.b) * 0.09 * smoothstep(-62.0, -22.0, w.y);
        float cumulus = smoothstep(threshold - 0.045, threshold + 0.08, structure - erosion);
        float cloud_top = 1.0 - smoothstep(-21.0, -15.5, w.y);
        float under_mist = exp(-pow((w.y + 67.0) / 26.0, 2.0)) * (0.09 + 0.10 * n.g);
        float upper_mist = exp(-pow((w.y + 28.0) / 14.0, 2.0)) * 0.10 * cloud_top;
        density = cumulus * cloud_top + under_mist + upper_mist;
        float distance_to_building = building_clearance(w);
        float exterior = smoothstep(3.0, 7.0, distance_to_building);
        float upper_clearance = mix(0.50, 1.0, smoothstep(4.0, 16.0, distance_to_building));
        density *= exterior * mix(1.0, upper_clearance, smoothstep(-66.0, -28.0, w.y));
        float edge = 1.0 - smoothstep(0.30, 0.495, max(abs(p.x), abs(p.z)));
        return density * edge * smoothstep(-0.50, -0.35, p.y);
    }
    // Small clouds translate/bob inside static building-safe envelopes.
    vec3 drift = vec3(sin(flow_time * 0.035 + phase) * 0.075, sin(flow_time * 0.052 + phase) * 0.035, cos(flow_time * 0.029 + phase) * 0.055);
    vec3 q = p - drift;
    float d = length((q - vec3(-0.19, -0.06, 0.01)) / vec3(0.23, 0.27, 0.28));
    d = min(d, length((q - vec3(0.02, 0.07, -0.02)) / vec3(0.25, 0.34, 0.31)));
    d = min(d, length((q - vec3(0.23, -0.06, 0.04)) / vec3(0.19, 0.24, 0.24)));
    d = min(d, length((q - vec3(-0.04, -0.12, 0.20)) / vec3(0.29, 0.22, 0.20)));
    float soft_lobe = 1.0 - smoothstep(0.42, 1.03, d + (n.b - 0.5) * 0.16);
    float edge = 1.0 - smoothstep(0.34, 0.495, max(max(abs(p.x), abs(p.y)), abs(p.z)));
    float distance_to_building = building_clearance(w);
    return soft_lobe * edge * mix(0.65, 1.0, painted) * smoothstep(3.0, 7.0, distance_to_building);
}
void vertex() {
    local_surface = VERTEX;
    local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}
void fragment() {
    // Enter through near faces so the whole sea also works with 99F's 145m far clip.
    // Render exactly one boundary even when the camera is inside the volume.
    bool camera_inside = all(lessThan(abs(local_camera), vec3(0.5)));
    if (FRONT_FACING == camera_inside) { discard; }
    mat4 world_to_local = inverse(MODEL_MATRIX);
    vec3 ray = normalize(local_surface - local_camera);
    vec3 inv_ray = 1.0 / (sign(ray + vec3(0.0000001)) * max(abs(ray), vec3(0.00001)));
    vec3 a = (-vec3(0.5) - local_camera) * inv_ray;
    vec3 b = (vec3(0.5) - local_camera) * inv_ray;
    vec3 near_axis = min(a, b);
    vec3 far_axis = max(a, b);
    float near_t = max(max(max(near_axis.x, near_axis.y), near_axis.z), 0.0);
    float far_t = min(min(far_axis.x, far_axis.y), far_axis.z);
    float depth = texture(scene_depth, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z = depth * 2.0 - 1.0;
#endif
    vec4 world_depth = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    world_depth /= world_depth.w;
    vec3 local_depth = (world_to_local * world_depth).xyz;
    far_t = min(far_t, dot(local_depth - local_camera, ray));
    if (far_t <= near_t) { discard; }
    float step_size = (far_t - near_t) / float(ray_steps);
    float world_step = length((MODEL_MATRIX * vec4(ray * step_size, 0.0)).xyz);
    vec3 rgb = vec3(0.0);
    float alpha = 0.0;
    vec3 sun_direction = normalize(light_direction);
    float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
    for (int i = 0; i < 96; i++) {
        if (i >= ray_steps || alpha > 0.985) { break; }
        vec3 p = local_camera + ray * (near_t + (float(i) + 0.20 + jitter * 0.60) * step_size);
        vec3 w = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
        float density = raw_density(p, w);
        if (density < 0.002) { continue; }
        float sample_alpha = 1.0 - exp(-density * density_scale * world_step);
        float optical_depth = 0.0;
        for (int j = 0; j < 4; j++) {
            if (j >= light_steps) { break; }
            float light_length = 3.5 + float(j) * 6.0;
            vec3 light_point = w + sun_direction * light_length;
            vec3 light_local = (world_to_local * vec4(light_point, 1.0)).xyz;
            if (all(lessThan(abs(light_local), vec3(0.49)))) {
                optical_depth += raw_density(light_local, light_point) * 6.0 * density_scale;
            }
        }
        float transmission = exp(-optical_depth * 1.7);
        // Density gradient supplies a real curved surface response on billow boundaries.
        vec3 delta_x = vec3(1.5, 0.0, 0.0);
        vec3 delta_y = vec3(0.0, 1.5, 0.0);
        vec3 delta_z = vec3(0.0, 0.0, 1.5);
        vec3 gradient = vec3(
            raw_density((world_to_local * vec4(w + delta_x, 1.0)).xyz, w + delta_x) - density,
            raw_density((world_to_local * vec4(w + delta_y, 1.0)).xyz, w + delta_y) - density,
            raw_density((world_to_local * vec4(w + delta_z, 1.0)).xyz, w + delta_z) - density);
        vec3 normal = -gradient / max(length(gradient), 0.0001);
        float rounded_light = 0.35 + 0.65 * max(dot(normal, sun_direction), 0.0);
        float sky_fill = smoothstep(-80.0, -18.0, w.y) * 0.14;
        float lighting = clamp(0.16 + transmission * rounded_light * 0.70 + sky_fill, 0.0, 1.0);
        vec3 color = mix(shadow_color.rgb, highlight_color.rgb, lighting);
        color *= 0.80 * mix(vec3(0.16, 0.23, 0.38), vec3(1.0), daylight) * tint;
        rgb += color * sample_alpha * (1.0 - alpha);
        alpha += sample_alpha * (1.0 - alpha);
    }
    if (alpha < 0.003) { discard; }
    ALBEDO = rgb / max(alpha, 0.001);
    ALPHA = alpha * cloud_opacity;
}
