shader_type canvas_item;

// --- Controls ---
uniform float intensity       : hint_range(0.0,1.0) = 0.45;
uniform float border_width    : hint_range(-0.6,0.6) = 0.22; // fraction of half of min(screen side)
uniform float softness        : hint_range(0.01,0.6) = 0.25; // fraction of half of min(screen side)
uniform float flow_speed      : hint_range(0.0,2.0) = 0.4;
uniform float flow_scale      : hint_range(0.5,8.0) = 3.0;
uniform float warp_strength   : hint_range(0.0,1.0) = 0.3;
uniform float bokeh_variance  : hint_range(0.0,1.0) = 0.3;
uniform float blur_amount     : hint_range(0.0,6.0) = 1.1;   // pixels
uniform float blur_speed      : hint_range(0.0,2.0) = 0.4;

// NEW: seam smoother — all in pixels (no corner rounding of the silhouette)
uniform float seam_smooth_px  : hint_range(0.0,64.0) = 8.0;  // soft-min strength
uniform float seam_blend_px   : hint_range(0.0,64.0) = 6.0;  // how far from the edge we start blending

uniform vec4 color_a : source_color = vec4(0.10,0.30,0.95,1.0);
uniform vec4 color_b : source_color = vec4(0.65,0.20,0.90,1.0);

// === fbm noise ===
float hash11(float n){ return fract(sin(n)*43758.5453123); }
vec2 hash22(vec2 p){
	vec2 q = vec2(dot(p, vec2(127.1,311.7)), dot(p, vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453123);
}
float noise(vec2 x){
	vec2 i=floor(x), f=fract(x);
	vec2 u=f*f*(3.0-2.0*f);
	return mix(
		mix(dot(hash22(i+vec2(0,0)),f-vec2(0,0)),
		    dot(hash22(i+vec2(1,0)),f-vec2(1,0)),u.x),
		mix(dot(hash22(i+vec2(0,1)),f-vec2(0,1)),
		    dot(hash22(i+vec2(1,1)),f-vec2(1,1)),u.x),
		u.y);
}
float fbm(vec2 p){
	float a=0.0, w=0.6;
	for(int i=0;i<3;i++){ a+=w*noise(p); p*=2.03; w*=0.45; }
	return a;
}

// Polynomial soft-min (Inigo Quilez style); k in pixels, larger = smoother
float smin(float a, float b, float k){
	if (k <= 0.0) return min(a, b);
	float h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
	return mix(b, a, h) - k*h*(1.0 - h);
}

void fragment(){
	vec2 uv = UV;
	float t = TIME * flow_speed;

	// --- screen metrics (pixels) ---
	vec2 res_px = 1.0 / SCREEN_PIXEL_SIZE;
	float min_side_px = min(res_px.x, res_px.y);
	float half_min_px = 0.5 * min_side_px;

	// Pixel-space coords centered at (0,0); box half-extents
	vec2 p_px   = (uv - 0.5) * res_px;
	vec2 half_b = 0.5 * res_px;

	// Breathing thickness (still relative to min side)
	float n_field = fbm(uv * flow_scale + vec2(t*0.6, -t*0.5));
	float local_w   = border_width * (1.0 + 0.15 * sin(t + n_field*3.14159));
	float border_px = local_w * half_min_px;
	float soft_px   = softness * half_min_px;

	// Exact inside distances to the two orthogonal edges (px, >=0 inside)
	float dx_in = half_b.x - abs(p_px.x);
	float dy_in = half_b.y - abs(p_px.y);
	dx_in = max(dx_in, 0.0);
	dy_in = max(dy_in, 0.0);

	// Exact "distance to border inside the box"
	float dist_exact = min(dx_in, dy_in);

	// Soft-min for seam smoothing (affects only inside the band)
	float dist_soft = smin(dx_in, dy_in, seam_smooth_px);

	// Blend factor that is 0 at the border (keeps silhouette sharp) and
	// ramps to 1 a few pixels inward, so only the inner band is smoothed.
	float s = smoothstep(0.0, seam_blend_px, dist_exact);

	// Final seam-free inside distance (no silhouette rounding)
	float dist_in = mix(dist_exact, dist_soft, s);

	// Apply warp uniformly to the *distance field* (keeps smoothness)
	float warp = fbm(uv * (flow_scale * 0.8) + vec2(t, -t*0.7)) - 0.5;
	dist_in += warp * warp_strength * 0.25 * half_min_px;

	// Edge band: opaque at border, fade over [border_px .. border_px + soft_px]
	float mask = 1.0 - smoothstep(border_px, border_px + soft_px, dist_in);
	mask = pow(mask, 1.15);

	// Organic modulation (does not change band thickness)
	float blob_mod = fbm(uv * flow_scale * 1.5 + vec2(t*0.9, -t*1.1));
	mask *= 0.85 + 0.15 * sin(blob_mod * 6.28318 + t*0.7);

	// Shimmer
	float alpha_mod = 1.0 - bokeh_variance * (0.5 + 0.5*sin((blob_mod + t)*3.14159));
	mask *= alpha_mod;

	// Aspect-correct inward blur in pixel space
	vec2 to_ctr_px = (vec2(0.5) - uv) / SCREEN_PIXEL_SIZE;
	float L = length(to_ctr_px);
	vec2 dir_px = L > 1e-5 ? (to_ctr_px / L) : vec2(0.0);

	vec3 acc = vec3(0.0);
	const int steps = 3;
	for (int i = 0; i < steps; i++) {
		float off_px  = (float(i) - float(steps-1)/2.0) * blur_amount;
		float anim    = (0.5 + 0.5*sin(t*blur_speed));
		vec2 delta_uv = (dir_px * off_px) * SCREEN_PIXEL_SIZE * anim;

		vec2 suv = clamp(uv + delta_uv, vec2(0.0), vec2(1.0));
		float w = 1.0 - abs(float(i) - float(steps-1)/2.0) / float(steps);
		vec3 c = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5*sin(t*0.4 + blob_mod*2.0));
		acc += c * w;
	}
	vec3 blurred = acc / float(steps);

	vec4 edge   = vec4(blurred, 1.0);
	vec4 trans  = vec4(blurred, 0.0);
	vec4 final_col = mix(trans, edge, mask);

	COLOR *= final_col * intensity;
}
