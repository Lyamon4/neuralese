shader_type canvas_item;
render_mode world_vertex_coords;

uniform vec4 data = vec4(0.0, 0.0, 0.0, 0.0); //blur_size, vertex_ox, vertex_oy

const float EPS = 1e-6;

varying vec2 view_scale;
varying vec2 vert_scale;
varying vec2 vert;
varying vec4 modulate;

void vertex() {
	vert = VERTEX;
	modulate = COLOR;
	view_scale = vec2(length(CANVAS_MATRIX[0].xy), length(CANVAS_MATRIX[1].xy));
	vert_scale = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
	VERTEX += vec2(data.y, data.z);
}

void fragment() {
	// Pixels-per-UV along each local axis (rotation-safe)
	vec2 gx = vec2(dFdx(UV.x), dFdy(UV.x));
	vec2 gy = vec2(dFdx(UV.y), dFdy(UV.y));
	float dux = max(length(gx), EPS); // UV change per 1 screen px
	float duy = max(length(gy), EPS);
	vec2 px_per_uv = 1.0 / vec2(dux, duy); // screen px per 1 UV unit

	// Work in pixel space to keep the blur circular in screen pixels
	vec2 uv_px = UV * px_per_uv;
	float r_px = data.x * min(view_scale.x, view_scale.y);

	// Interior rectangle (shrunk by r_px on all sides), in pixel space
	vec2 rect_min_px = vec2(r_px);
	vec2 rect_max_px = px_per_uv - vec2(r_px);

	// Nearest point inside the interior & pixel distance to it
	vec2 nearest_px = clamp(uv_px, rect_min_px, rect_max_px);
	float dist_px = length(uv_px - nearest_px);

	// Base falloff: 1 at interior edge, 0 at r_px out
	float alpha = 1.0 - smoothstep(0.0, r_px, dist_px);
	alpha = smoothstep(0.0, 1.0, alpha); // nicer rolloff
	alpha *= alpha;                      // extra softness

	// Ensure fade to 0 at the very border (also in pixel space)
vec2 edge_dist_uv = vec2(
    min(UV.x, 1.0 - UV.x),
    min(UV.y, 1.0 - UV.y)
);
	vec2 edge_dist_px = edge_dist_uv * px_per_uv;
	float min_edge_px = min(edge_dist_px.x, edge_dist_px.y);
	float edge_fade = smoothstep(0.0, r_px, min_edge_px);
	alpha *= edge_fade;

	COLOR *= vec4(COLOR.rgb, COLOR.a * clamp(alpha, 0.0, 1.0));
}
