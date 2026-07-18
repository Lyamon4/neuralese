shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// tweak to taste (start around 0.25)
uniform float smoothing : hint_range(0.0, 1.0) = 0.25;
// your text color
uniform vec4 font_color : source_color = vec4(1.0);

// median of three values
float median3(float a, float b, float c) {
	return max(min(a, b), min(max(a, b), c));
}

void fragment() {
	// sample the MSDF in the font atlas
	vec3 sdf = texture(TEXTURE, UV).rgb;
	// reconstruct signed distance
	float dist = median3(sdf.r, sdf.g, sdf.b);
	// estimate pixel-space smoothing width
	float width = fwidth(dist) * smoothing;
	// build a smooth alpha ramp at the 0.5 edge
	float alpha = smoothstep(0.5 - width, 0.5 + width, dist);
	// output text color
	COLOR = font_color * alpha;
}
