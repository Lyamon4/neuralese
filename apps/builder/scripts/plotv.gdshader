shader_type canvas_item;
render_mode world_vertex_coords;

uniform float corner_radius : hint_range(0.0, 100.0) = 8.0;

/* Rect bounds in the SAME space as VERTEX.xy */
uniform vec2 rect_pos;   // top-left (canvas/world space)
uniform vec2 rect_size;  // size (canvas/world space)

varying vec2 v_pos;      // interpolated world position

float rounded_rect_sdf(vec2 p, vec2 half, float r) {
	vec2 q = abs(p) - (half - vec2(r));
	return length(max(q, vec2(0.0)))
	     + min(max(q.x, q.y), 0.0)
	     - r;
}

void vertex() {
	/* With world_vertex_coords, VERTEX is already in canvas/world space */
	v_pos = VERTEX.xy;
}

void fragment() {
	vec2 half = rect_size * 0.5;

	/* Local rect-centered coordinates in WORLD space */
	vec2 p = v_pos - rect_pos - half;

	float sdf = rounded_rect_sdf(p, half, corner_radius);
	float aa  = fwidth(sdf);

	COLOR.a *= smoothstep(0.0, -aa, sdf);
}
