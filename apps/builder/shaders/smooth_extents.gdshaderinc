
instance uniform vec4 extents = vec4(0.0, 0.0, 0.0, 0.0);
uniform float smoothness = 20.0;

float alphamult(vec2 v){
	float a = 1.0;

	// Top fade
	if (abs(extents.x)>0.01) {
		a *= smoothstep(extents.x - smoothness * 0.35, extents.x + smoothness * 0.65, v.y);
	}

	// Bottom fade
	if (abs(extents.y)>0.01) {
		a *= 1.0 - smoothstep(extents.y - smoothness, extents.y, v.y);
	}

	// Left fade
	if (abs(extents.z)>0.01) {
		a *= smoothstep(extents.z - smoothness * 0.35, extents.z + smoothness * 0.65, v.x);
	}

	// Right fade
	if (abs(extents.w)>0.01) {
		a *= 1.0 - smoothstep(extents.w - smoothness, extents.w, v.x);
	}

	return a;
}