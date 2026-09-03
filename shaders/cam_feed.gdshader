shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float noise_amt : hint_range(0.0, 1.0) = 0.06;
uniform float dropout : hint_range(0.0, 1.0) = 0.0;
uniform float flicker : hint_range(0.0, 2.0) = 1.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.18;
uniform vec4 phosphor : source_color = vec4(0.22, 0.95, 0.32, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;

	// Occasional CRT event. Slot ~6s, window ~0.7s. glitch raises the hit rate.
	float slot = floor(TIME / 6.0);
	float local = fract(TIME / 6.0);
	float window = step(local, 0.12) * (1.0 - smoothstep(0.09, 0.12, local));
	float pick = hash(vec2(slot, 9.2));
	float fire = step(0.74 - glitch * 0.52, pick) * window;
	float kind = hash(vec2(slot, 2.4));

	// Vertical roll (V-sync lost, picture walks).
	if (fire > 0.5 && kind > 0.38) {
		float roll = (local / max(0.12, 0.001)) * (0.18 + glitch * 0.28);
		uv.y = fract(uv.y + roll);
	}

	// H-sync: a band of rows shears in X.
	if (fire > 0.5 && kind < 0.62) {
		float band_y = hash(vec2(slot, 4.1));
		float row = floor(uv.y * 80.0);
		if (abs(uv.y - band_y) < 0.07 + glitch * 0.05) {
			uv.x = fract(uv.x + (hash(vec2(row, slot)) - 0.5) * (0.10 + glitch * 0.16));
		}
	}

	float row = floor(uv.y * 40.0);
	float tear_n = hash(vec2(row, floor(TIME * 8.0)));
	if (dropout > 0.35 && tear_n > 0.82) {
		uv.x = fract(uv.x + (tear_n - 0.82) * 0.9);
	}

	vec4 src = texture(TEXTURE, uv);
	float lum = dot(src.rgb, vec3(0.30, 0.59, 0.11));

	// Blanking bar during a roll — dim, not snow. Silhouette stays.
	if (fire > 0.5) {
		float bar = fract(local * 3.4 + kind);
		if (abs(uv.y - bar) < 0.018) {
			lum *= 0.12;
		}
	}

	vec3 g = phosphor.rgb * lum * flicker;
	float sl = 0.78 + 0.22 * step(0.5, fract(UV.y * 80.0));
	g *= sl;
	float n = hash(UV * vec2(76.0, 80.0) + vec2(TIME * 19.0, TIME * 7.0));
	g += phosphor.rgb * (n - 0.5) * noise_amt;
	float snow = hash(vec2(floor(UV.x * 76.0), floor(UV.y * 80.0 + TIME * 22.0)));
	g = mix(g, phosphor.rgb * snow, dropout);
	float vig = smoothstep(1.15, 0.35, length(UV - vec2(0.5)));
	g *= vig;
	g = clamp(g, vec3(0.0), phosphor.rgb * 1.05);
	COLOR = vec4(g, 1.0);
}
