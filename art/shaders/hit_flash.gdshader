shader_type canvas_item;

// White hit-flash. `modulate` can only multiply, so it can darken but never
// brighten; mixing toward a colour is the only way to make a dark pixel white
// for 0.08s (GDD §5). Drives FlashComponent.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	// Weighted by alpha so transparent pixels stay transparent instead of
	// flashing as a solid silhouette block.
	base.rgb = mix(base.rgb, flash_color.rgb, flash_amount * base.a);
	COLOR = base;
}
