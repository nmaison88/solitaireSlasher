shader_type canvas_item;

// Main menu backdrop: COLOR (the ColorRect's theme color) is the base tint, darkened
// toward the top, warmed with dust near the bottom, with drifting haze, a pulsing glow
// behind the selected game, vignette and film grain.

uniform vec2 glow_center = vec2(0.5, 0.45);
uniform vec4 glow_color : source_color = vec4(0.9, 0.18, 0.14, 1.0);
uniform float glow_radius = 0.2;
uniform vec4 haze_color : source_color = vec4(0.35, 0.75, 0.2, 1.0);
uniform float aspect = 0.5; // width / height of the rect

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = COLOR.rgb * mix(0.5, 1.05, smoothstep(0.0, 0.75, uv.y));
	col += vec3(0.12, 0.06, 0.02) * smoothstep(0.55, 1.0, uv.y);

	vec2 p = vec2(uv.x * aspect, uv.y) * 3.0;
	float haze = fbm(p + vec2(TIME * 0.03, -TIME * 0.02));
	haze = smoothstep(0.45, 0.9, haze) * smoothstep(0.15, 1.0, uv.y);
	col += haze_color.rgb * haze * 0.18;

	vec2 d = uv - glow_center;
	d.x *= aspect;
	float glow = exp(-dot(d, d) / max(glow_radius * glow_radius, 0.0001));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	col += glow_color.rgb * glow * 0.55 * pulse;

	vec2 v = (uv - 0.5) * vec2(1.2, 1.0);
	col *= mix(0.45, 1.0, smoothstep(0.85, 0.25, length(v)));

	col += (hash(floor(UV * vec2(512.0, 1024.0)) + floor(fract(TIME) * 24.0)) - 0.5) * 0.035;

	// Clamp: negative values in the canvas buffer break blending of everything drawn on top
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
