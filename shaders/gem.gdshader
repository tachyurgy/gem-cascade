// gem.gdshader — a vivid glossy jewel drawn entirely in the fragment shader, now
// ALIVE: each gem twinkles, its inner facets slowly rotate, a caustic shimmer
// drifts across the body, and a 4-point star glint periodically blooms. Every gem
// gets a random `phase` so the whole board sparkles out of sync like a treasure
// pile instead of pulsing in lockstep.
//
// Lustre = slow broad sheen + crisp gloss dot. Selection = bright rim + outward
// bloom halo (alpha computed jointly with the body mask so the glow lives outside
// the gem). Specials get their own animated markers.
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float selected = 0.0;   // 0..1 selection pulse
uniform int special = 0;        // 0 normal, 1 stripe, 2 colour-bomb
uniform float shimmer = 1.0;    // global sheen intensity
uniform float phase = 0.0;      // per-gem random phase so twinkles desync

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// A soft 4-point star kernel centred at `c`, used for the twinkle glint.
float star(vec2 p, float size) {
	p /= size;
	float r = length(p);
	float a = atan(p.y, p.x);
	// 4-arm star: brightest along the axes.
	float arms = pow(abs(cos(a * 2.0)), 6.0);
	float core = smoothstep(1.0, 0.0, r);
	return clamp(core * (0.35 + 0.65 * arms), 0.0, 1.0);
}

mat2 rot(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

void fragment() {
	float t = TIME + phase;
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

	// --- ANIMATED inner facets: a few slowly-rotating light planes inside the
	// gem give it living, refractive depth (caustics under glass). ---
	vec2 fuv = rot(t * 0.35) * uv;
	float facets = sin(fuv.x * 6.0 + t * 0.9) * sin(fuv.y * 6.0 - t * 0.7);
	body += smoothstep(0.45, 1.0, facets) * 0.12 * mask;
	// A second, finer counter-rotating layer for richness.
	vec2 guv = rot(-t * 0.22) * uv;
	float caustic = sin(guv.x * 9.0 - t * 1.3) * 0.5 + 0.5;
	body += smoothstep(0.6, 1.0, caustic) * mix(col, vec3(1.0), 0.7) * 0.10;

	// Broad soft sheen — the "lustre". Wide, low-contrast, slow drift.
	float band = sin((uv.x - uv.y) * 1.25 - t * 0.7);
	body += smoothstep(0.25, 1.0, band) * 0.08 * shimmer;

	// Crisp glossy specular dot (upper-left) + a tight soft halo around it.
	float spec = smoothstep(0.18, 0.0, length((uv - vec2(-0.34, -0.40)) * vec2(1.0, 1.25)));
	body += spec * 0.95;
	body += smoothstep(0.6, 0.0, length(uv - vec2(-0.26, -0.32))) * 0.12;

	// Bottom inner rim bounce light.
	float rim = smoothstep(-0.1, 0.7, uv.y) * smoothstep(0.35, 0.05, abs(d + 0.03));
	body += rim * mix(col, vec3(1.0), 0.35) * 0.55;

	// --- TWINKLE: a 4-point star glint that periodically blooms on the gem. It
	// rides a slow cycle (every ~3.3s, desynced by phase) and travels a little so
	// it reads as light catching a facet. ---
	float cyc = fract(t * 0.3);
	float tw = smoothstep(0.5, 0.0, abs(cyc - 0.18));   // sharp blink near cyc=.18
	vec2 tw_pos = vec2(-0.3 + 0.6 * fract(t * 0.11 + phase), -0.34);
	float glint = star((uv - tw_pos) * vec2(1.0, 1.1), 0.5) * tw;
	body += glint * vec3(1.0) * 1.4 * mask;

	// Special markers.
	if (special == 1) {                            // stripe blast
		float flow = 0.5 + 0.5 * sin(uv.x * 3.0 - t * 6.0);
		body = mix(body, vec3(1.0), smoothstep(0.15, 0.08, abs(uv.y)) * (0.6 + 0.35 * flow));
	} else if (special == 2) {                     // colour bomb
		float pulse = 0.5 + 0.5 * sin(t * 5.0);
		body = mix(body, vec3(1.0), smoothstep(0.5, 0.0, rad) * (0.4 + 0.4 * pulse));
		// swirling sparkle core
		float swirl = star(rot(t * 2.0) * uv, 0.7);
		body += swirl * vec3(1.0) * 0.5;
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
