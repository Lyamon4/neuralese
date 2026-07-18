shader_type canvas_item;
render_mode world_vertex_coords;

uniform float corner_radius : hint_range(0.0, 100.0) = 8.0;
uniform bool bg_fill = true;

/* OUTLINE */
uniform float outline_width : hint_range(0.0, 20.0) = 2.0; // object units
uniform vec4 outline_color : source_color = vec4(1.0, 0.3, 0.2, 1.0);

/* BACKGROUND (outside) */
uniform vec4 background_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);

/* World → object helpers */
varying mat2 inv_model_v;
varying vec2 origin_v;
varying vec2 world_v;

void vertex() {
	// Cache inverse linear transform (rotation + scale)
	mat2 model2 = mat2(
		MODEL_MATRIX[0].xy,
		MODEL_MATRIX[1].xy
	);
	inv_model_v = inverse(model2);

	origin_v = MODEL_MATRIX[3].xy;
	world_v  = VERTEX;
}

void fragment() {
	/* Object-space position */
	vec2 obj_pos = inv_model_v * (world_v - origin_v);

	/* Reconstruct UV → object Jacobian */
	mat2 A = mat2(dFdx(obj_pos), dFdy(obj_pos));
	mat2 B = mat2(dFdx(UV),      dFdy(UV));
	mat2 J = A * inverse(B);

	/* Object-space size */
	vec2 ux = J * vec2(1.0, 0.0);
	vec2 uy = J * vec2(0.0, 1.0);

	vec2 size = vec2(length(ux), length(uy));
	vec2 half = size * 0.5;

	/* Centered coordinate (CRITICAL FIX) */
	vec2 p = (UV - vec2(0.5)) * size;

	/* Radii in OBJECT units (no zoom dependency) */
	float r  = max(corner_radius, 0.0);
	float ow = max(outline_width, 0.0);

	/* Clamp radius */
	r = min(r, min(half.x, half.y) - 0.0001);

	/* Rounded rect SDF */
	vec2 q = abs(p) - (half - vec2(r));
	float sdf = length(max(q, vec2(0.0)))
	          + min(max(q.x, q.y), 0.0)
	          - r;

	/* Proper AA in sdf units */
	float aa = max(fwidth(sdf), 1e-6);

	/* ===== REGIONS ===== */

	/* Fill: sdf < -ow */
	float fill_alpha = smoothstep(-ow - aa, -ow + aa, sdf);

	/* Outline: -ow ≤ sdf ≤ 0 */
	float outline_alpha =
		smoothstep(-ow - aa, -ow + aa, sdf) *
		(1.0 - smoothstep(-aa, aa, sdf));

	/* Background: sdf > 0 */
	float bg_alpha = smoothstep(-aa, aa, sdf);

	/* ===== COMPOSITION ===== */

	vec4 col = vec4(0.0);

	/* Background */
	col.rgb = background_color.rgb;
	col.a   = background_color.a * bg_alpha;

	/* Outline */
	col.rgb = mix(col.rgb, outline_color.rgb, outline_alpha * outline_color.a);
	col.a   = max(col.a, outline_alpha * outline_color.a);

	/* Fill */
	if (bg_fill) {
		col.rgb = mix(col.rgb, COLOR.rgb, fill_alpha * COLOR.a);
		col.a   = max(col.a, fill_alpha * COLOR.a);
	}

	if (!bg_fill) {
		COLOR *= col;
	} else {
		COLOR = col;
	}
}
