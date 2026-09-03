shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float noise_amt : hint_range(0.0, 1.0) = 0.14;
uniform float dropout : hint_range(0.0, 1.0) = 0.0;
uniform float flicker : hint_range(0.0, 2.0) = 1.0;
uniform vec4 phosphor : source_color = vec4(0.22, 0.95, 0.32, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	float row = floor(UV.y * 40.0);
	float tear_n = hash(vec2(row, floor(TIME * 8.0)));
	if (dropout > 0.35 && tear_n > 0.82) {
		uv.x = fract(uv.x + (tear_n - 0.82) * 0.9);
	}
	vec4 src = texture(TEXTURE, uv);
	float lum = dot(src.rgb, vec3(0.30, 0.59, 0.11));
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
