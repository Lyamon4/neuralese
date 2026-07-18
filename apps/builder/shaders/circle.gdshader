shader_type canvas_item;

uniform float outline_width : hint_range(0.0, 0.2) = 0.02;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float d = length(UV - center);
	float aa = max(fwidth(d), 0.005);
	float mask = 1.0 - smoothstep(0.495 - aa, 0.495 + aa, d);
	COLOR.a *= mask;
	float r = 0.495;
	float hw = max(outline_width * 0.5, 0.0);
	float inner = smoothstep(r - hw - aa, r - hw + aa, d);
	float outer = 1.0 - smoothstep(r + hw - aa, r + hw + aa, d);
	float ring = clamp(inner * outer, 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, outline_color.rgb, ring * outline_color.a);
}
