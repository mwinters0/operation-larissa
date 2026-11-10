shader_type canvas_item;
// The "tank lost" dissolve of the sub (see DissolvePattern and Sub.show_dissolve).
//
// `pass_mask` has one pixel per pixel of the dissolve box; its value says in which pass that pixel stops showing the
// sub (0..15, 16 = the closing full copy). `passes_done` counts the passes that have run so far: a pixel whose pass
// is lower is already replaced by the scene behind the sub, so it is simply not drawn. Pixels outside the box
// are left alone.

uniform sampler2D pass_mask : filter_nearest, repeat_disable;
// Where the box starts and how big it is, in the same (canvas) coordinates as the sprite's position.
uniform vec2 box_origin;
uniform vec2 box_size;
uniform float passes_done = 0.0;

varying vec2 canvas_position;

void vertex() {
	canvas_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 inside = (canvas_position - box_origin) / box_size;
	if (inside.x >= 0.0 && inside.y >= 0.0 && inside.x < 1.0 && inside.y < 1.0) {
		float pass_of_pixel = floor(texture(pass_mask, inside).r * 255.0 + 0.5);
		if (pass_of_pixel < passes_done) {
			COLOR.a = 0.0;
		}
	}
}
