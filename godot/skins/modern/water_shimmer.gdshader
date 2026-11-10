shader_type canvas_item;
// The water of the "modern" skin: a gentle shimmer over the PICTURE BEHIND a screen (the background sprite, nothing else). Two
// things happen to that picture, both slowly and both small:
//
//   1. WAVER. Every point of the picture is looked up a little to the side of where it is (sines of position and time), so the
//      rocks and the far coral wobble as if seen through moving water. At most `waver` pixels of the picture, and the look-up
//      is kept inside the picture, so the border never shows an edge.
//   2. CAUSTICS. The bright, net-like lines that sunlight makes in shallow water (two layers of waves that cross each other;
//      where the crests meet they add up) are laid over the picture as a faint lightening, stronger near the top of the screen
//      (where the light comes from) and gone by the bottom.
//
// IT IS ONLY A PICTURE. The walls are the screen's tile bytes and the rules look at those (`TileGrid`), the creatures, the sub and
// the decorations are other nodes drawn over this one, and this shader changes none of them. Nothing here reads a rule or is read
// by one; a skin that changes its look cannot change the game (`tests/engine/test_skins_dont_change_the_game.gd`).
//
// TIME IS THE GAME'S. `phase` is not `TIME`: the presenter sets it every frame to "ticks so far + the fraction of the current tick"
// (modern_presenter.gd). The water therefore moves at the speed of the game clock and STANDS STILL when the clock is held (a
// message box, a problem, the sub dissolving, a pause) or stepped by hand - which `TIME` cannot do, it never stops. The same scene
// at the same tick always has the same water, which also makes a screenshot repeatable.

// Game ticks so far, with the fraction of the current one (so it grows smoothly: 12.17 per second).
uniform float phase = 0.0;
// The size of the picture in its own units (the playfield: 38 x 18 tiles of 16 pixels). Distances below are in these units, so
// the same shader suits a 608 x 288 picture and a 4x one: it never counts the file's own pixels.
uniform vec2 picture_size = vec2(608.0, 288.0);
// How far, in picture pixels, the waver moves a point at most (each way).
uniform float waver : hint_range(0.0, 4.0, 0.1) = 2.0;
// How much light the caustics add (0 = none) and how large their cells are, in picture pixels.
uniform float glint : hint_range(0.0, 0.5, 0.01) = 0.10;
uniform float cell : hint_range(16.0, 200.0, 1.0) = 72.0;


// One layer of the caustic net: a bright thin line wherever a sum of two sines is near zero.
float net(vec2 p, float t) {
	float a = sin(p.x * 1.0 + sin(p.y * 0.8 + t * 0.9) * 1.6 + t * 0.7);
	float b = sin(p.y * 1.2 + sin(p.x * 0.6 - t * 0.8) * 1.4 - t * 0.6);
	return pow(1.0 - abs(a + b) * 0.5, 6.0);          // 1 on the lines, quickly less beside them
}

void fragment() {
	vec2 at = UV * picture_size;                              // where this point is, in picture pixels
	float t = phase * 0.05;                                   // slow: the sines below multiply it by 2 to 6

	// 1. waver
	vec2 shift = vec2(
			sin(at.y * 0.045 + t * 3.0) + 0.5 * sin(at.y * 0.11 - t * 4.1 + at.x * 0.02),
			cos(at.x * 0.04 + t * 2.3) + 0.5 * sin(at.x * 0.09 + t * 3.7 - at.y * 0.03)) * (waver / 1.5);
	vec2 look = clamp(UV + shift / picture_size, vec2(0.0), vec2(1.0));
	vec4 water = texture(TEXTURE, look);

	// 2. caustics, from the unshifted position so the net moves by itself
	vec2 p = at * (TAU / cell);
	float lines = net(p, t * 4.0) * 0.6 + net(p * 1.7 + 3.0, t * 5.2) * 0.4;
	float from_above = 1.0 - smoothstep(0.0, 0.85, UV.y);      // 1 at the top of the picture, 0 near the bottom
	water.rgb += vec3(0.75, 0.95, 1.0) * lines * glint * (0.35 + 0.65 * from_above) * water.a;

	COLOR = water;
}
