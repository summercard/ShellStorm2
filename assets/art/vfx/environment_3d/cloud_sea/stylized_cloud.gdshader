shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

// A bounded, softly rounded cloud volume. All motion happens inside the authored box.
uniform vec4 highlight_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.54, 0.68, 0.82, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.80;
uniform float density_scale : hint_range(0.1, 12.0) = 7.0;
uniform float shape_seed = 1.0;
uniform float flow_time = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint = vec3(1.0);

varying vec3 local_surface;
varying vec3 local_camera;

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float soft_noise(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(cell), hash31(cell + vec3(1,0,0)), f.x),
                   mix(hash31(cell + vec3(0,1,0)), hash31(cell + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash31(cell + vec3(0,0,1)), hash31(cell + vec3(1,0,1)), f.x),
                   mix(hash31(cell + vec3(0,1,1)), hash31(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

float ellipsoid(vec3 p, vec3 center, vec3 radius) {
    return length((p - center) / radius);
}

float cloud_density(vec3 p) {
    float phase = shape_seed * 1.731;
    vec3 flow = vec3(flow_time * 0.005, sin(flow_time * 0.021 + phase) * 0.15, -flow_time * 0.003);
    // Broad domain warping gives slow fluid motion without fine, realistic smoke detail.
    float n = soft_noise(p * 5.0 + flow + vec3(phase));
    vec3 warp = vec3(sin(p.z * 9.0 + phase + flow_time * 0.030),
                     sin(p.x * 8.0 + flow_time * 0.026 + phase),
                     cos(p.x * 7.0 + flow_time * 0.022 + phase)) * 0.020;
    vec3 q = p + warp;
    float d = ellipsoid(q, vec3(-0.24, -0.06, -0.04), vec3(0.23, 0.30, 0.32));
    d = min(d, ellipsoid(q, vec3(-0.02, 0.07, 0.01), vec3(0.27, 0.35, 0.36)));
    d = min(d, ellipsoid(q, vec3(0.24, -0.07, -0.04), vec3(0.23, 0.29, 0.31)));
    d = min(d, ellipsoid(q, vec3(-0.13, -0.17, 0.20), vec3(0.26, 0.23, 0.24)));
    d = min(d, ellipsoid(q, vec3(0.15, -0.16, 0.18), vec3(0.25, 0.23, 0.25)));
    d = min(d, ellipsoid(q, vec3(0.12, -0.13, -0.22), vec3(0.25, 0.25, 0.22)));
    float shape = 1.0 - smoothstep(0.67, 1.02 + (n - 0.5) * 0.13, d);
    // The fade reaches zero inside the static box, so deformation cannot cross its boundary.
    float edge = 1.0 - smoothstep(0.455, 0.495, max(max(abs(p.x), abs(p.y)), abs(p.z)));
    return shape * edge * mix(0.76, 1.0, n);
}

void vertex() {
    local_surface = VERTEX;
    local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
    vec3 ray = normalize(local_surface - local_camera);
    vec3 inv_ray = 1.0 / (sign(ray) * max(abs(ray), vec3(0.00001)));
    vec3 a = (-vec3(0.5) - local_camera) * inv_ray;
    vec3 b = (vec3(0.5) - local_camera) * inv_ray;
    vec3 near_axis = min(a, b);
    vec3 far_axis = max(a, b);
    float near_t = max(max(near_axis.x, near_axis.y), near_axis.z);
    float far_t = min(min(far_axis.x, far_axis.y), far_axis.z);
    near_t = max(near_t, 0.0);
    float step_size = max(far_t - near_t, 0.0) / 28.0;
    vec3 rgb = vec3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 28; i++) {
        vec3 p = local_camera + ray * (near_t + (float(i) + 0.5) * step_size);
        float density = cloud_density(p);
        float sample_alpha = 1.0 - exp(-density * density_scale * step_size);
        float height_light = smoothstep(-0.30, 0.27, p.y);
        float shade = clamp(height_light * 0.82 + 0.18 + (1.0 - density) * 0.10, 0.0, 1.0);
        vec3 color = mix(shadow_color.rgb, highlight_color.rgb, shade);
        color *= mix(vec3(0.19, 0.27, 0.41), vec3(1.0), daylight) * tint;
        rgb += color * sample_alpha * (1.0 - alpha);
        alpha += sample_alpha * (1.0 - alpha);
    }
    if (alpha < 0.005) { discard; }
    ALBEDO = rgb / max(alpha, 0.001);
    ALPHA = alpha * cloud_opacity;
}
