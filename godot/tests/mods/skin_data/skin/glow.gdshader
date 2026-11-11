// The shader a data skin puts on a layer of the original presenter (`layers` of its manifest). A mod's shader is text the game checks (ModShader) and compiles; the game sets `phase` (its time, ticks plus the fraction of the current tick).
shader_type canvas_item;

uniform float phase = 0.0;
uniform float glint : hint_range(0.0, 1.0) = 0.25;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform vec2 size = vec2(608.0, 288.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float wave = 0.5 + 0.5 * sin(phase * 0.5 + UV.y * size.y * 0.05);
	COLOR = vec4(mix(c.rgb, tint.rgb, glint * wave), c.a);
}
