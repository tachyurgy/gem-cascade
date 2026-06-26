// background.gdshader — a living gradient with drifting glow blobs, a faint
// twinkling sparkle field and a vignette, so the play area always feels alive and
// "produced" behind the board (never a flat backdrop).
shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.05, 0.06, 0.16, 1.0);
uniform vec4 color_b : source_color = vec4(0.20, 0.10, 0.34, 1.0);
uniform vec4 glow     : source_color = vec4(0.40, 0.30, 0.72, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Vertical gradient with a slow horizontal wave.
	float g = uv.y + 0.12 * sin(uv.x * 3.0 + TIME * 0.25);
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(g, 0.0, 1.0));

	// Four drifting soft glow blobs — the "nebula".
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 c = vec2(0.5 + 0.44 * sin(TIME * 0.16 + fi * 2.1),
		              0.5 + 0.44 * cos(TIME * 0.13 + fi * 1.7));
		float dd = distance(uv, c);
		col += (0.055 / (dd * 6.5 + 0.32)) * glow.rgb;
	}

	// Faint twinkling star field (cheap hashed grid, animated brightness).
	vec2 gp = floor(uv * 28.0);
	float star = hash(gp);
	if (star > 0.93) {
		float tw = 0.5 + 0.5 * sin(TIME * 2.5 + star * 40.0);
		col += vec3(0.7, 0.75, 1.0) * (star - 0.93) * 9.0 * tw * 0.25;
	}

	// Vignette focuses the eye on the board.
	col *= smoothstep(1.3, 0.28, distance(uv, vec2(0.5)));
	COLOR = vec4(col, 1.0);
}
