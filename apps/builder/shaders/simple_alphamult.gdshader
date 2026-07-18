shader_type canvas_item;
render_mode world_vertex_coords;
varying vec2 vert;

#include "res://shaders/smooth_extents.gdshaderinc"

varying vec2 vert_scale;
void vertex() {
	vert = VERTEX;
	vert_scale = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
}

void fragment() {
	COLOR.a *= alphamult(vert);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
