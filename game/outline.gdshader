shader_type canvas_item;
// A gold outline around the texture's opaque pixels, so a drop on the floor
// stands out. The rect is drawn `width` texels larger on each side (UV beyond
// 0..1): the outline has room even where the art touches the texture's edge.

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform float width = 3.0;  // texels

varying vec4 tint;  // the vertex color (modulate), applied last

float alpha(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = alpha(TEXTURE, UV) > 0.0 ? texture(TEXTURE, UV) : vec4(0.0);
	float o = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * PI / 4.0;
		o = max(o, alpha(TEXTURE, UV + vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE * width));
	}
	COLOR = vec4(mix(color.rgb, c.rgb, c.a), max(c.a, o * color.a)) * tint;
}
