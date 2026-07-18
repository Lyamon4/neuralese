shader_type canvas_item;

instance uniform vec4 vals = vec4(0,0,0,0);
uniform float lumi_boost_intensity : hint_range(0.0, 10.0) = 1.0;

void fragment() {
	float brightness      = vals.x;
	float contrast        = vals.y;
	float lumi_threshold  = clamp(vals.z, 0.0, 1.0);

	vec4 color = texture(TEXTURE, UV);
	vec3 rgb = color.rgb;

	// --- Brightness / contrast ---

	// --- Luminance ---
	float l = dot(rgb, vec3(0.299, 0.587, 0.114));

	// --- Smooth mask for boosting only above threshold ---
	float edge0 = lumi_threshold;
	float edge1 = min(1.0, lumi_threshold + 0.2);
	float t = smoothstep(edge0, edge1, l);

	// --- Push toward white instead of multiplying ---
	float boost = clamp(t * (lumi_boost_intensity / 10.0), 0.0, 1.0);
	rgb = mix(rgb, vec3(1.0), boost);
	rgb += vec3(brightness);
	rgb = (rgb - 0.5) * contrast + 0.5;
	rgb = clamp(rgb, 0.0, 1.0);

	COLOR.rgb = rgb;
	COLOR.a = color.a;
}
