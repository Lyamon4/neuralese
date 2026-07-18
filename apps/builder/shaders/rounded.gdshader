shader_type canvas_item;

uniform float corner_radius : hint_range(0.0, 100.0) = 8.0;

void fragment() {
	vec2 rect_size = vec2(1) / TEXTURE_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * rect_size;

	vec2 q = abs(p) - (rect_size * 0.5 - vec2(corner_radius));
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;

	float px = fwidth(sdf);
	float alpha = smoothstep(0.0, -px, sdf);

	COLOR.a *= alpha;
}
