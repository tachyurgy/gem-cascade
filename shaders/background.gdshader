// background.gdshader — a slow living gradient with drifting glow blobs and a
// vignette, so the play area never feels static behind the board.
shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.05, 0.06, 0.16, 1.0);
uniform vec4 color_b : source_color = vec4(0.18, 0.09, 0.30, 1.0);
uniform vec4 glow     : source_color = vec4(0.35, 0.28, 0.65, 1.0);

void fragment() {
	vec2 uv = UV;
	float g = uv.y + 0.12 * sin(uv.x * 3.0 + TIME * 0.25);
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(g, 0.0, 1.0));

	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(0.5 + 0.42 * sin(TIME * 0.18 + fi * 2.1),
		              0.5 + 0.42 * cos(TIME * 0.15 + fi * 1.7));
		float dd = distance(uv, c);
		col += (0.05 / (dd * 7.0 + 0.35)) * glow.rgb;
	}

	col *= smoothstep(1.25, 0.25, distance(uv, vec2(0.5)));
	COLOR = vec4(col, 1.0);
}
