shader_type canvas_item;

// === Parameters ===
uniform float speed : hint_range(0.1,5.0)=0.5;
uniform float density : hint_range(0.0,20.0)=4.0;
uniform float fluidity : hint_range(0.0,2.0)=0.5;
uniform float blob_radius : hint_range(0.1,1.0)=0.45;
uniform float edge_softness : hint_range(0.0,1.0)=0.05;
uniform float grain_amount : hint_range(0.0,0.2)=0.03;
uniform float alpha_power : hint_range(0.0,1.0)=1.0;

// New uniforms
uniform vec2 scale = vec2(1.0, 1.0); // global universe scale
uniform float blob_count : hint_range(0.5, 10.0) = 1.0;       // increases count, keeps size constant

uniform vec4 color_primary   : source_color = vec4(0.1,0.3,0.9,1.0);
uniform vec4 color_secondary : source_color = vec4(0.0,0.7,0.7,1.0);
uniform vec4 color_tertiary  : source_color = vec4(0.6,0.1,0.8,1.0);

// --- varyings ---
varying vec2 world_uv;


vec2 random2(vec2 p){
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),
	                      dot(p,vec2(269.5,183.3))))*43758.5453);
}

float noise(vec2 st){
	vec2 i=floor(st);
	vec2 f=fract(st);
	vec2 u=f*f*(3.0-2.0*f);
	return mix(
		mix(dot(random2(i+vec2(0,0)),f-vec2(0,0)),
		    dot(random2(i+vec2(1,0)),f-vec2(1,0)),u.x),
		mix(dot(random2(i+vec2(0,1)),f-vec2(0,1)),
		    dot(random2(i+vec2(1,1)),f-vec2(1,1)),u.x),
		u.y);
}

vec2 voronoi_blobs(vec2 uv,float time){
	vec2 i_uv=floor(uv);
	vec2 f_uv=fract(uv);
	float min_dist=1.0;
	float cell_id=0.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec2 n=vec2(float(x),float(y));
			vec2 p=random2(i_uv+n);
			vec2 pos=0.5+0.5*sin(time+6.2831*p);
			vec2 d=n+pos-f_uv;
			float dist=length(d);
			float pulse=0.5+0.5*sin(time*0.8+p.x*10.0);
			float apparent=dist/clamp(pulse,0.01,1.0);
			if(apparent<min_dist){
				min_dist=apparent;
				cell_id=p.x;
			}
		}
	}
	return vec2(min_dist,cell_id);
}

void vertex(){
	vec4 world_pos = MODEL_MATRIX * vec4(VERTEX,0.0,1.0);
	world_uv = world_pos.xy;
}

void fragment(){
	float time = TIME * speed;
	vec2 viewport_size = vec2(1.0) / SCREEN_PIXEL_SIZE;
	float aspect = viewport_size.x / viewport_size.y;

	// World-space normalized coords
	vec2 uv = world_uv / (200.0 * scale);
	uv.x *= aspect;

	// Accumulate multiple offset Voronoi fields
	vec2 blob_sum = vec2(0.0);
	float layer_weight = 1.0 / float(blob_count);
	for(int i = 0; i < int(blob_count); i++){
		// offset each layer slightly in random direction
		float angle = float(i) * 6.28318 / float(blob_count);
		vec2 offset = vec2(cos(angle), sin(angle)) * 0.5;
		vec2 warped_uv = (uv + offset) * density;
		warped_uv += vec2(
			noise(uv * 3.0 + time * 0.5 + float(i)*2.0),
			noise(uv * 3.0 - time * 0.5 + float(i)*1.7)
		) * fluidity;
		vec2 blob = voronoi_blobs(warped_uv, time + float(i)*0.5);
		// Blend distances by minimum to keep consistent shape size
		if(i==0 || blob.x < blob_sum.x){
			blob_sum = blob;
		}
	}

	float dist = blob_sum.x;
	float id = blob_sum.y;

	float outer = blob_radius;
	float inner = max(0.0, blob_radius - edge_softness);
	float shape = smoothstep(outer, inner, dist);

	// --- Color ---
	vec4 col = mix(color_primary, color_secondary, id);
	col = mix(col, color_tertiary, sin(id*10.0 + time)*0.5 + 0.5);
	col.rgb *= 1.0 + 0.2 * sin(time * 2.0 + id * 20.0);

	// --- Grain ---
	float noise_grain = random2(world_uv * 0.02 + vec2(TIME*5.0)).x;
	col.rgb += (noise_grain - 0.5) * grain_amount;

	COLOR = col;
	COLOR.a = shape * alpha_power;
}