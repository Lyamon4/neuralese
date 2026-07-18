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

void vertex() {
	vert = VERTEX;
	modulate = COLOR;
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

void fragment() {
	vec2 size_px = vec2(1.0 / dFdx(UV).x, 1.0 / dFdy(UV).y);
	vec2 half = size_px * 0.5;
	vec2 p = UV * size_px - half;

	float radius_added = corner_radius_width_add.x + corner_radius;
	float r = radius_added * min(view_scale.x, view_scale.y) * vert_scale.x;
	float w = (outline_width + corner_radius_width_add.y) * min(view_scale.x, view_scale.y) * vert_scale.y;

	float sdf;
	if (false) {
	} else {
		vec2 q = abs(p) - (half - vec2(r));
		sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	}

	float mask = smoothstep(1.0, -1.0, sdf);
	float ol = smoothstep(w + 1.0, w - 1.0, abs(sdf));
	if (outline_width + corner_radius_width_add.y < 0.01) { ol = 0.0; }

	vec4 col;
	vec4 out_col = outline_color;

	if (blurred_background) {
		float lod = blur_level < 0.0 ? -blur_level : blur_level * _view_scale;

		vec2 step_px = SCREEN_PIXEL_SIZE * max(gaussian_step, 0.0001) * (1.0 + blur_level);

		vec4 bg_lod;
		if (use_bg){
		bg_lod = textureLod(bg, SCREEN_UV, lod);
		}
		else{
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
