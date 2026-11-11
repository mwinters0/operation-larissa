shader_type canvas_item;
// The walls of the "modern" example skin, kept sharp. The skin draws with a smooth (linear) texture filter, but the walls are the
// original's small pixel-art tiles cut from one atlas: drawn smooth, a hairline of the neighbouring tile shows between two tiles.
// This shader looks every point of a wall up at the centre of its own pixel of the atlas, which is what the nearest filter does,
// so the walls stay the sharp tiles they are while every other picture of the skin is smooth.
//
// IT IS ONLY A PICTURE. The walls the rules read are the screen's tile bytes (`TileGrid`); this changes how the tiles look.

void fragment() {
	vec2 pixels = 1.0 / TEXTURE_PIXEL_SIZE;                    // the atlas's size in its own pixels
	COLOR = texture(TEXTURE, (floor(UV * pixels) + 0.5) / pixels);
}
