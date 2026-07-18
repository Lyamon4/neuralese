shader_type canvas_item;

uniform float corner_radius : hint_range(0.0, 100.0) = 8.0;
uniform vec2 rect_size = vec2(200.0, 100.0);

instance uniform vec4 p00_01 = vec4(0.0);
instance uniform vec4 p10_11 = vec4(0.0);

uniform bool use_pixel_points = true;
uniform int newton_iters = 5;
uniform float eps = 1e-6;
uniform float pixel_softness = 0.5; // 0=hard pixel grid, 1=smooth edges

void get_quad_uvs(out vec2 q00, out vec2 q10, out vec2 q01, out vec2 q11, vec2 psize) {
	if (use_pixel_points) {
		vec2 ts = psize;
		q00 = p00_01.xy * ts;
		q10 = p10_11.xy * ts;
		q01 = p00_01.zw * ts;
		q11 = p10_11.zw * ts;
	} else {
		q00 = p00_01.xy;
		q10 = p10_11.zy;
		q01 = p00_01.zw;
		q11 = p10_11.zw;
	}
}

vec2 bilinear_forward(vec2 st, vec2 q00, vec2 q10, vec2 q01, vec2 q11) {
	vec2 a = mix(q00, q10, st.x);
	vec2 b = mix(q01, q11, st.x);
	return mix(a, b, st.y);
}

void bilinear_jacobian(vec2 st, vec2 q00, vec2 q10, vec2 q01, vec2 q11,
					   out vec2 ds, out vec2 dt) {
	ds = (1.0 - st.y) * (q10 - q00) + st.y * (q11 - q01);
	vec2 a = mix(q00, q10, st.x);
	vec2 b = mix(q01, q11, st.x);
	dt = b - a;
}

vec2 solve2(vec2 a, vec2 b, vec2 r) {
	float det = a.x * b.y - a.y * b.x;
	if (abs(det) < 1e-12) return vec2(0.0);
	float inv = 1.0 / det;
	return inv * vec2(  b.y * r.x - b.x * r.y,
					   -a.y * r.x + a.x * r.y );
}

vec2 invert_bilinear(vec2 uv_target, vec2 q00, vec2 q10, vec2 q01, vec2 q11, vec2 uv) {
	vec2 d = q00 - q10 - q01 + q11;
	if (dot(d, d) < 1e-12) {
		vec2 c0 = q10 - q00;
		vec2 c1 = q01 - q00;
		vec2 rhs = uv_target - q00;
		float det = c0.x * c1.y - c0.y * c1.x;
		if (abs(det) < 1e-12) return clamp(uv, 0.0, 1.0);
		float inv = 1.0 / det;
		float s =  ( rhs.x * c1.y - rhs.y * c1.x) * inv;
		float t = (-rhs.x * c0.y + rhs.y * c0.x) * inv;
		return clamp(vec2(s, t), 0.0, 1.0);
	}

	vec2 st = clamp(uv_target, 0.0, 1.0);
	for (int i = 0; i < newton_iters; i++) {
		vec2 f = bilinear_forward(st, q00, q10, q01, q11) - uv_target;
		if (max(abs(f.x), abs(f.y)) < eps) break;
		vec2 js, jt;
		bilinear_jacobian(st, q00, q10, q01, q11, js, jt);
		vec2 delta = solve2(js, jt, f);
		st -= delta;
		st = clamp(st, -0.5, 1.5);
	}
	return clamp(st, 0.0, 1.0);
}

// safe texture read: return black if outside 0..1
vec4 safe_texture(sampler2D tex, vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	return texture(tex, uv);
}

void fragment() {
	vec2 uv_out = UV;
	vec2 uvv = floor(UV / TEXTURE_PIXEL_SIZE) * TEXTURE_PIXEL_SIZE;

	vec2 q00, q10, q01, q11;
	get_quad_uvs(q00, q10, q01, q11, TEXTURE_PIXEL_SIZE);

	vec2 st = invert_bilinear(uvv, q00, q10, q01, q11, uvv);

	// --- soft pixel snapping to avoid gaps ---
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 st_tex = st * tex_size;
	vec2 base = floor(st_tex);
	vec2 frac = st_tex - base;

	vec2 bias = clamp(frac / pixel_softness, 0.0, 1.0);
	vec4 c00 = safe_texture(TEXTURE, (base + vec2(0.5, 0.5)) / tex_size);
	vec4 c10 = safe_texture(TEXTURE, (base + vec2(1.5, 0.5)) / tex_size);
	vec4 c01 = safe_texture(TEXTURE, (base + vec2(0.5, 1.5)) / tex_size);
	vec4 c11 = safe_texture(TEXTURE, (base + vec2(1.5, 1.5)) / tex_size);

	vec4 cx0 = mix(c00, c10, bias.x);
	vec4 cx1 = mix(c01, c11, bias.x);
	vec4 color = mix(cx0, cx1, bias.y);

	COLOR = color;
	
	

	vec2 p = (UV - 0.5) * rect_size;

	vec2 q = abs(p) - (rect_size * 0.5 - vec2(corner_radius));
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;

	float px = fwidth(sdf);
	float alpha = smoothstep(0.0, -px, sdf);

	COLOR.a *= alpha;
}
