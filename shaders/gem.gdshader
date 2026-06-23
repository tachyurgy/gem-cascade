// gem.gdshader — a vivid glossy jewel drawn entirely in the fragment shader.
// Procedural, tinted per-instance. Lustre = a slow broad sheen + a crisp static
// gloss dot. Selection = a bright rim + an outward bloom halo (alpha is computed
// jointly with the body mask so the glow can live outside the gem).
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float selected = 0.0;   // 0..1 selection pulse
uniform int special = 0;        // 0 normal, 1 stripe, 2 colour-bomb
uniform float shimmer = 1.0;    // global sheen intensity

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;                      // -1 .. 1
	float d = rounded_box(uv, vec2(0.80), 0.26);
	float aa = fwidth(d) * 1.5;
	float mask = 1.0 - smoothstep(0.0, aa, d);

	// Selection: outward bloom drives extra alpha beyond the body.
	float bloom = selected * (1.0 - smoothstep(0.0, 0.34, max(d, 0.0)));
	float alpha = max(mask, bloom * 0.7);
	if (alpha <= 0.004) { discard; }

	// --- body: top-lit vertical gradient + center pop, vivid edges ---
	float rad = length(uv);
	vec3 col = base_color.rgb;
	vec3 body = mix(mix(col, vec3(1.0), 0.42), col * 0.38, smoothstep(-0.9, 1.0, uv.y));
	body = mix(body, mix(col, vec3(1.0), 0.55), smoothstep(0.7, 0.0, rad) * 0.35);

	// Beveled darker edge for a cut-gem read.
	body *= 1.0 - smoothstep(0.18, 0.0, abs(d + 0.04)) * 0.22;

	// Broad soft sheen — the "lustre". Wide, low-contrast, slow drift.
	float band = sin((uv.x - uv.y) * 1.25 - TIME * 0.7);
	body += smoothstep(0.25, 1.0, band) * 0.08 * shimmer;

	// Crisp glossy specular dot (upper-left) + a tight soft halo around it.
	float spec = smoothstep(0.18, 0.0, length((uv - vec2(-0.34, -0.40)) * vec2(1.0, 1.25)));
	body += spec * 0.95;
	body += smoothstep(0.6, 0.0, length(uv - vec2(-0.26, -0.32))) * 0.12;

	// Bottom inner rim bounce light.
	float rim = smoothstep(-0.1, 0.7, uv.y) * smoothstep(0.35, 0.05, abs(d + 0.03));
	body += rim * mix(col, vec3(1.0), 0.35) * 0.55;

	// Special markers.
	if (special == 1) {                            // stripe blast
		body = mix(body, vec3(1.0), smoothstep(0.15, 0.08, abs(uv.y)) * 0.85);
	} else if (special == 2) {                     // colour bomb
		float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
		body = mix(body, vec3(1.0), smoothstep(0.5, 0.0, rad) * (0.4 + 0.4 * pulse));
	}

	// Selection: bright rim along the body edge + inner brighten.
	float sel_ring = selected * smoothstep(0.09, 0.0, abs(d + 0.02));
	body += mix(col, vec3(1.0), 0.7) * sel_ring * 0.9;
	body += col * selected * 0.22;

	// Compose: the bloom colour shows where the body mask is absent.
	vec3 bloom_col = mix(base_color.rgb, vec3(1.0), 0.65);
	vec3 final = mix(bloom_col, body, mask);
	COLOR = vec4(final, alpha);
}
