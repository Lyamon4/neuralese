shader_type canvas_item;
#include "res://shaders/std.gdshaderinc"
render_mode world_vertex_coords;

// shape: 0=rect,1=triangle,2=rhombus, 3=circle
uniform int shape: hint_range(0,2) = 0;

uniform vec4 mult_tuning: source_color = vec4(1.0);
instance uniform vec4 tuning: source_color = vec4(1.0);
uniform vec4 color_mult: source_color = vec4(1.0);

#include "res://shaders/smooth_extents.gdshaderinc"

global uniform float _view_scale = 1.0;
instance uniform vec2 corner_radius_width_add = vec2(0,0);
uniform float corner_radius: hint_range(0.0, 100.0) = 8.0;

// Per-corner additive radius offsets (in the same units as corner_radius):
// x=TopLeft, y=TopRight, z=BottomRight, w=BottomLeft
uniform vec4 corner_radius_corners = vec4(0.0);

uniform bool blurred_background = true;
uniform float outline_width: hint_range(0.0, 50.0) = 0.0;
uniform float mult = 2.0;
instance uniform vec4 outline_color: source_color = vec4(1.0);

uniform float blur_level: hint_range(-7.0, 7.0) = 2.5;
uniform float gaussian_mix: hint_range(0.0, 1.0) = 1.0;
uniform float gaussian_step: hint_range(0.0, 8.0) = 1.0;

global uniform sampler2D bg: filter_linear_mipmap_anisotropic;

varying vec2 view_scale;
varying vec2 vert_scale;
varying vec2 vert;
varying vec4 modulate;

// For rotation/scale-safe SDF reconstruction (no rect-size uniforms needed)
varying mat2 inv_model_v;
varying vec2 origin_v;
varying vec2 world_v;

void vertex() {
	vert = VERTEX;
	modulate = COLOR;

	// Cache inverse linear transform (rotation+scale) and origin.
	mat2 model2 = mat2(MODEL_MATRIX[0].xy,
	                   MODEL_MATRIX[1].xy);
	inv_model_v = inverse(model2);
	origin_v = MODEL_MATRIX[3].xy;

	// World-space position (since world_vertex_coords is enabled)
	world_v = VERTEX;

	view_scale = vec2(length(CANVAS_MATRIX[0].xy), length(CANVAS_MATRIX[1].xy));
	vert_scale = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
}

bool in_bounds(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

uniform bool use_bg = true;

uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;

vec4 sample_screen_safe(vec2 uv, float lod) {
	vec4 cont;
	if (use_bg){cont = textureLod(bg, uv, lod);}else{cont = textureLod(screen, uv, lod);}
	return in_bounds(uv) ? cont : vec4(cont.rgb, 0.0);
}

vec4 gaussian9_mip(vec2 uv, float lod, vec2 step_px) {
	vec2 sx = vec2(step_px.x, 0.0);
	vec2 sy = vec2(0.0, step_px.y);

	vec4 c  = sample_screen_safe(uv, lod) * 4.0;

	vec4 ax = sample_screen_safe(uv - sx, lod) * 2.0
	        + sample_screen_safe(uv + sx, lod) * 2.0;

	vec4 ay = sample_screen_safe(uv - sy, lod) * 2.0
	        + sample_screen_safe(uv + sy, lod) * 2.0;

	vec4 d  = sample_screen_safe(uv + sx + sy, lod)
	        + sample_screen_safe(uv + sx - sy, lod)
	        + sample_screen_safe(uv - sx + sy, lod)
	        + sample_screen_safe(uv - sx - sy, lod);

	return (c + ax + ay + d) / 16.0;
}

// Pick per-corner radius (top-left, top-right, bottom-right, bottom-left) based on p sign.
float corner_radius_for_p(vec2 p) {
	// p is centered: x<0 left, x>0 right; y<0 top, y>0 bottom (UV.y grows downward)
	if (p.x < 0.0) {
		return (p.y < 0.0) ? corner_radius_corners.x : corner_radius_corners.w;
	} else {
		return (p.y < 0.0) ? corner_radius_corners.y : corner_radius_corners.z;
	}
}

void fragment() {
	// Object-space position per fragment (undo rotation+scale from world coords)
	vec2 obj_pos = inv_model_v * (world_v - origin_v);

	// Reconstruct UV->object Jacobian (gives object-space size, no uniforms)
	mat2 A = mat2(dFdx(obj_pos), dFdy(obj_pos));
	mat2 B = mat2(dFdx(UV),      dFdy(UV));
	mat2 J = A * inverse(B);

	// Object-space basis vectors for one full UV unit in X/Y
	vec2 ux = J * vec2(1.0, 0.0);
	vec2 uy = J * vec2(0.0, 1.0);

	// Scalar size and centered p in object units
	vec2 size = vec2(length(ux), length(uy));
	vec2 half = size * 0.5;
	vec2 p = (UV - vec2(0.5)) * size;

	// Convert "pixel-ish" params (radius/outline) into object-space units.
	// We want radius_added=1 to mean ~1 screen pixel.
	float px_obj = max(length(dFdx(obj_pos)), length(dFdy(obj_pos)));
	px_obj = max(px_obj, 1e-6);

	// global add stays global (applies to all corners)
	float radius_added = corner_radius_width_add.x + corner_radius + corner_radius_for_p(p);

	// rotation/zoom invariant radius + outline width (object-space)
	float r = max(radius_added, 0.0);
float w = max(outline_width + corner_radius_width_add.y, 0.0);

	// clamp radius to avoid invalid geometry
	r = min(r, min(half.x, half.y) - 0.0001);

	// Rounded-rect SDF in centered object-space
	vec2 q = abs(p) - (half - vec2(r));
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;

	// Proper AA in sdf-units (fixes "thin gradient + empty center")
	float aa = max(fwidth(sdf), 1e-6);

	float mask = smoothstep( aa, -aa, sdf);
	float ol = smoothstep(w + aa, w - aa, abs(sdf));
	if (outline_width + corner_radius_width_add.y < 0.01) { ol = 0.0; }

	vec4 col;
	vec4 out_col = outline_color;

	if (blurred_background) {
		float lod = blur_level < 0.0 ? -blur_level : blur_level * _view_scale;

		vec2 step_px = SCREEN_PIXEL_SIZE * max(gaussian_step, 0.0001) * (1.0 + blur_level);

		vec4 bg_lod;
		if (use_bg){
			bg_lod = textureLod(bg, SCREEN_UV, lod);
		} else {
			bg_lod = textureLod(screen, SCREEN_UV, lod);
		}

		vec4 bg_gauss = gaussian9_mip(SCREEN_UV, lod, step_px);

		vec4 bg_ = mix(bg_lod, bg_gauss, gaussian_mix) * mult;

		if (ol < 0.999) {
			col = mix(alpha_blend(bg_, tuning * mult_tuning) * color_mult, out_col, ol);
		} else {
			col = out_col;
		}
	} else {
		col = mix(tuning * mult_tuning * color_mult, outline_color, ol);
	}

	col.a *= mask;
	COLOR = col * modulate;
	COLOR.a *= alphamult(vert);
}
