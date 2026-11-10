// Mixes the sub's picture towards a colour. A skin's shader is text the game checks (ModShader) and compiles.
shader_type canvas_item;

uniform float strength = 0.5;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.2, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(mix(c.rgb, tint.rgb, strength), c.a);
}
