shader_type spatial;
render_mode unshaded, cull_disabled;

// 关卡入口边框：常亮描边 + 悬停时沿线框环绕的流光。
// HologramCity3D._line 用 Basis.looking_at 建框，线段局部 -Z 指向 b 端，
// 所以 VERTEX.z 可直接归一化成沿线参数 u（0 → a 端，1 → b 端）。
// 四条边各自写入 arc_span（该边占周长的比例）与 flow_offset（该边在周长上的起点），
// 合起来就是一条沿整圈边框跑动的光带。
uniform float clock = 0.0;
uniform float hover = 0.0;
uniform float flow_offset = 0.0;
uniform float arc_span = 1.0;
uniform float flow_speed = 0.42;
uniform float line_length = 1.0;
uniform vec4 tint : source_color = vec4(0.02, 0.72, 1.0, 1.0);

varying float edge_u;

void vertex() {
	edge_u = clamp(0.5 - VERTEX.z / max(line_length, 0.0001), 0.0, 1.0);
}

void fragment() {
	float phase = fract(flow_offset + edge_u * arc_span - clock * flow_speed);
	// 拖尾亮头：phase 归零处最亮并向前拖出长尾。头部约占周长三分之一、
	// 尾部再压暗延伸到整圈，因此在一两像素宽的边框上仍能看出光带在跑。
	float head = pow(max(0.0, 1.0 - phase * 3.0), 2.0);
	float tail = pow(max(0.0, 1.0 - phase), 3.0) * 0.55;
	float flow = clamp(head + tail, 0.0, 1.0) * hover;
	// 常态 2.0 与旧 _material(color, 2.0) 的发光当量一致，悬停再抬高整体并叠加流光。
	float energy = 2.0 + 1.2 * hover + flow * 9.0;
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * energy;
}
