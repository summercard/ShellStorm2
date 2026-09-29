shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float deployment = 0.0;
float hash(vec2 p) {return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);}
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
 vec2 p = (UV - 0.5) * 220.0 + vec2(5.0);
 float cloud = noise(p*2.0)*0.5 + noise(p*5.0)*0.3 + noise(p*13.0)*0.2;
 float band = exp(-abs(p.x - p.y*0.75 - 1.4)*0.8);
 vec2 cells = UV * 7200.0;
 float star = step(0.997,hash(floor(cells))) * pow(max(0.0,1.0-length(fract(cells)-0.5)*2.0),5.0);
 vec3 nebula = mix(vec3(0.001,0.004,0.016),vec3(0.012,0.065,0.24),pow(cloud,3.0)*band*2.0);
 ALBEDO = nebula + vec3(0.1,0.6,1.0)*star*3.5;
 ALPHA = smoothstep(0.1,0.9,deployment);
}
