shader_type canvas_item;

uniform sampler2D msdf_tex;
uniform vec4 font_color    : source_color = vec4(1.0,1.0,1.0,1.0);
uniform vec4 outline_color : source_color = vec4(0.0,0.0,0.0,1.0);
uniform float outline_thickness : hint_range(0.0,0.5) = 0.25;

float median(float a, float b, float c) {
	// return the middle of three values
	return max(min(a,b), min(max(a,b), c));
}

void fragment() {
	// sample msdf and shift to signed distance
	vec3 msdf = texture(msdf_tex, UV).rgb;
	float sd = median(msdf.r, msdf.g, msdf.b) - 0.5;

	// compute pixel‐size for smoothstep
	float smoothing = fwidth(sd);

	// core glyph alpha
	float glyph_alpha = clamp(sd / smoothing + 0.5, 0.0, 1.0);

	// outline by offsetting sd by thickness
	float o = outline_thickness;
	float outline_alpha = clamp((sd + o) / smoothing + 0.5, 0.0, 1.0)
	                     - clamp((sd - o) / smoothing + 0.5, 0.0, 1.0);

	// blend outline behind glyph
	vec4 col = mix(outline_color * outline_alpha, font_color * glyph_alpha, glyph_alpha);

	COLOR = col;
}
