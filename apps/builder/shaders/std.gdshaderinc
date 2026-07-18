
vec4 alpha_blend(vec4 o, vec4 n) {
	float sum = n.a + o.a;
	sum = clamp(sum, 0.0001, 1.0);
	float rate = n.a / sum;
	vec4 res = mix(o, n, rate);
	res.a = clamp(n.a + o.a, 0.0, 1.0);
	return res;
}