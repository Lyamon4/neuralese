shader_type canvas_item;
render_mode world_vertex_coords;

uniform float mult = 0.5;
uniform float width   = 2.0;   // dot diameter in world units
uniform float spacing = 10.0;  // grid spacing in world units
uniform vec4 grid_color : source_color;
uniform vec4 bg_color   : source_color;

uniform float aa_pixels = 1.0;

varying vec2 vert;
void vertex() { vert = VERTEX; }

void fragment() {
	// Offset into a centered spacing cell so (0,0) is the nearest grid point
	vec2 p = mod(vert + 0.5 * spacing, spacing) - 0.5 * spacing;

	float dist = length(p);              // distance to nearest grid intersection
	float half_w = 0.5 * width;          // dot radius

	// Convert AA thickness from pixels to world units via screen-space derivatives
	vec2 fw = fwidth(vert);
	float px_world = aa_pixels * max(fw.x, fw.y);

	// Soft circle edge
	float a = 1.0 - smoothstep(half_w - px_world, half_w + px_world, dist);

	COLOR = mix(bg_color, grid_color, a) ;
	COLOR.rgb *= mult;
}
