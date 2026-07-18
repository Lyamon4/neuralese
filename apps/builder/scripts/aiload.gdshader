shader_type canvas_item;

// ===== Dynamics =====
uniform float speed : hint_range(0.1, 5.0) = 1.1;
uniform float alpha_power : hint_range(0.0, 1.0) = 1.0;
uniform float breathe_amp : hint_range(0.0, 0.25) = 0.06;

// ===== Geometry =====
uniform float ring_radius : hint_range(0.12, 0.48) = 0.36;
uniform float ring_thickness : hint_range(0.02, 0.25) = 0.10;
uniform float ring_softness : hint_range(0.0, 0.10) = 0.04;

// ===== Warping & Flow =====
uniform float warp_freq : hint_range(2.0, 12.0) = 6.0;
uniform float warp_amp  : hint_range(0.0, 0.20) = 0.07;
uniform float thickness_amp   : hint_range(0.0, 1.0) = 0.35;
uniform float thickness_lobes : hint_range(1.0, 12.0) = 3.0;
uniform float softness_amp : hint_range(0.0, 1.0) = 0.35;
uniform float softness_freq : hint_range(0.5, 8.0) = 2.0;
uniform float flow_density : hint_range(1.0, 8.0) = 3.0;
uniform float flow_amp : hint_range(0.0, 0.08) = 0.02;

// ===== Bloom / Glow =====
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.6;
uniform float bloom_width     : hint_range(0.001, 0.25) = 0.06;
uniform float bloom_var_amp   : hint_range(0.0, 1.0) = 0.35;
uniform float glow : hint_range(0.0, 2.0) = 0.75;

// ===== Color =====
uniform vec4 c0 : source_color = vec4(0.08, 0.28, 0.95, 1.0);
uniform vec4 c1 : source_color = vec4(0.00, 0.75, 0.78, 1.0);
uniform vec4 c2 : source_color = vec4(0.68, 0.15, 0.85, 1.0);

// ==== Utils ====
float hash11(float n){ return fract(sin(n)*43758.5453123); }
vec2 hash22(vec2 p){
	vec2 q = vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453123);
}
float noise2(vec2 x){
	vec2 i=floor(x);
	vec2 f=fract(x);
	vec2 u=f*f*(3.0-2.0*f);
	return mix(
		mix(dot(hash22(i+vec2(0,0)),f-vec2(0,0)),
		    dot(hash22(i+vec2(1,0)),f-vec2(1,0)),u.x),
		mix(dot(hash22(i+vec2(0,1)),f-vec2(0,1)),
		    dot(hash22(i+vec2(1,1)),f-vec2(1,1)),u.x),
		u.y);
}
float fbm(vec2 p){
	float a=0.0,w=0.6;
	for(int i=0;i<2;i++){a+=w*noise2(p);p*=2.03;w*=0.55;}
	return a;
}
float soft_mask(float d,float k){ return clamp(0.5-d/k,0.0,1.0); }

// ==== Signed distance ring (warped, flowing, variable thickness) ====
float ring_sdf_raw(vec2 p,float base_R,float base_T,float time){
	vec2 flow = vec2(
		fbm(p*flow_density + vec2(time*0.30, -time*0.17)),
		fbm(p*flow_density + vec2(-time*0.22,  time*0.21))
	) - 0.5;
	p += flow * flow_amp;

	float ang = atan(p.y,p.x);
	float rad = length(p);

	float n  = max(2.0,floor(warp_freq+0.5));
	float n2 = max(1.0,floor(thickness_lobes+0.5));

	float w = warp_amp*(0.6*sin(n*ang+time*1.1)+0.4*sin(2.0*n*ang-time*0.7));
	rad += w;

	float tmod = 1.0 + thickness_amp*(0.6*sin(n2*ang+time*0.9)+0.4*sin(2.0*n2*ang-time*0.6));

	float breathe = 1.0 + breathe_amp*sin(time*0.9);
	float R = base_R * breathe;
	float T = base_T * tmod * (1.0 + 0.5*breathe_amp*sin(time*1.3+1.7));

	return abs(rad-R) - T;
}

// ==== Main ====
void fragment(){
	vec2 uv = UV;
	// --- aspect-invariant square coords ---
	vec2 tex_px = TEXTURE_PIXEL_SIZE;
	if (tex_px.x == 0.0 || tex_px.y == 0.0) {
		tex_px = vec2(1.0 / (1.0 / SCREEN_PIXEL_SIZE.x),
		              1.0 / (1.0 / SCREEN_PIXEL_SIZE.y));
	}
	float node_aspect = tex_px.y / tex_px.x;
	vec2 p = (uv - 0.5) * 2.0;
	p.x *= node_aspect;

	float time = TIME * speed;

	float d = ring_sdf_raw(p, ring_radius, ring_thickness, time);

	vec2 angdir = normalize(p + 1e-6);
	vec2 soft_uv = angdir * softness_freq + vec2(time*0.2, -time*0.2);
	float soft_jitter = (fbm(soft_uv) - 0.5) * 2.0;
	float soft_local = ring_softness * max(0.2, 1.0 + softness_amp * soft_jitter);

	float mask = soft_mask(d, soft_local);

	// ---- Color field ----
	float ang = atan(p.y, p.x);
	vec3 base = mix(c0.rgb, c1.rgb, 0.5 + 0.5*sin(ang + time*0.35));
	base       = mix(base, c2.rgb, 0.35 + 0.35*sin(2.0*ang - time*0.23));
	float energy = 0.5 + 0.5 * sin(3.0 * fbm(p*2.5 + vec2(time*0.4,-time*0.33)) + time*1.1);
	vec3 col = base + energy * 0.22;

	// ---- Rim glow ----
	float r = length(p);
	float rim_outer = smoothstep(ring_radius + ring_thickness + soft_local*0.6,
	                             ring_radius + ring_thickness - soft_local*0.8, r);
	float rim_inner = smoothstep(ring_radius - ring_thickness - soft_local*0.6,
	                             ring_radius - ring_thickness + soft_local*0.8, r);
	float rim = clamp(rim_outer + rim_inner, 0.0, 1.0);
	col += rim * glow * 0.35;

	// ---- Bloom fade-to-alpha ----
	float sigma = bloom_width * max(0.15, 1.0 + bloom_var_amp *
		(fbm(p*1.7 + vec2(-time*0.25,time*0.31)) - 0.5) * 2.0);
	float bloom_mask = exp(-pow(abs(d)/max(1e-4,sigma), 2.0));
	float bloom_alpha = bloom_mask * bloom_intensity;

	COLOR.rgb = col;
	COLOR.a *= clamp(mask + bloom_alpha * (1.0 - mask), 0.0, 1.0) * alpha_power;
}
