shader_type canvas_item;

global uniform sampler2D bg;

void fragment() {
	COLOR = texture(bg, SCREEN_UV);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
