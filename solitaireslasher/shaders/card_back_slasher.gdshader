shader_type canvas_item;

// Procedural Solitaire Slasher card back: oxblood crosshatch, bone inset trim and a
// slashed diamond emblem, with rounded corners. The TextureRect's texture is ignored.

uniform vec2 card_size = vec2(120.0, 160.0);
uniform float radius = 10.0;
uniform vec3 base_color : source_color = vec3(0.34, 0.05, 0.04);
uniform vec3 trim_color : source_color = vec3(0.86, 0.77, 0.58);

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - (half_size - vec2(r));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * card_size;
	vec2 c = px - card_size * 0.5;
	float outer = sd_round_rect(c, card_size * 0.5, radius);
	float a = 1.0 - smoothstep(-1.0, 1.0, outer);

	// Oxblood, darker toward the edges
	vec3 col = mix(base_color, base_color * 0.4, smoothstep(0.0, 0.6, length(c / card_size)));

	// Diagonal crosshatch
	float h1 = abs(fract((px.x + px.y) / 12.0) - 0.5);
	float h2 = abs(fract((px.x - px.y) / 12.0) - 0.5);
	float hatch = clamp((1.0 - smoothstep(0.04, 0.1, h1)) + (1.0 - smoothstep(0.04, 0.1, h2)), 0.0, 1.0);
	col = mix(col, col * 0.55, hatch * 0.6);

	// Inset trim line, with a darker band outside it
	float inset = sd_round_rect(c, card_size * 0.5 - vec2(9.0), radius - 4.0);
	col *= mix(1.0, 0.7, step(0.0, inset));
	col = mix(col, trim_color, (1.0 - smoothstep(0.8, 1.8, abs(inset))) * 0.8);

	// Central diamond emblem with a slash through it
	vec2 q = c / vec2(26.0, 36.0);
	float diamond = abs(q.x) + abs(q.y);
	float fill = 1.0 - smoothstep(0.95, 1.0, diamond);
	col = mix(col, base_color * 1.5, fill * 0.9);
	col = mix(col, trim_color, 1.0 - smoothstep(0.05, 0.11, abs(diamond - 1.0)));
	float slash_dist = abs(dot(c, vec2(0.8, 0.6)));
	float slash = (1.0 - smoothstep(1.0, 2.2, slash_dist)) * (1.0 - smoothstep(1.2, 1.3, diamond));
	col = mix(col, trim_color, slash);

	// Dark outer border, matching the card faces
	float border = smoothstep(-5.0, 0.0, outer) * a;
	col = mix(col, vec3(0.0), border * 0.75);

	COLOR = vec4(col, a);
}
