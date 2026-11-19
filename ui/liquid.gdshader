shader_type canvas_item;
// A HUD gauge's fill as a liquid in its glass: translucent, darker at the
// bottom, a shine band rippling along its top and small bubbles drifting up.
// On the ProgressBar itself, so only its own drawing (the fill) takes it:
// the frame, a child, keeps its own material.

uniform float top = 6.0;  // the fill's top, in the bar's pixels (hud.gd RIM)
uniform float height = 16.0;  // the fill's height, in pixels
uniform float alpha = 0.86;  // see-through: the game shows under it

varying vec2 pos;  // in the bar's pixels

void vertex() {
	pos = VERTEX;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float y = clamp((pos.y - top) / height, 0.0, 1.0);  // 0 top, 1 bottom
	float t = TIME;
	float wave = sin(pos.x * 0.09 + t * 1.8) * 0.6 + sin(pos.x * 0.23 - t * 2.7) * 0.4;
	vec3 c = COLOR.rgb * mix(1.2, 0.75, y);  // depth
	c += 0.28 * smoothstep(0.16, 0.0, abs(y - 0.22 - wave * 0.07));  // the rippling shine
	// Bubbles: one per 14 px cell drifting left, each rising at its own pace.
	float x = pos.x + t * 9.0;
	float cell = floor(x / 14.0);
	float rise = fract(t * (0.25 + 0.35 * hash(cell)) + hash(cell + 7.0));
	vec2 b = vec2(fract(x / 14.0) * 14.0 - 4.0 - 6.0 * hash(cell + 3.0), (1.0 - rise) * height + top - pos.y);
	c += 0.35 * smoothstep(1.8, 0.6, length(b)) * sin(rise * 3.14159);
	COLOR = vec4(c, COLOR.a * alpha);
}
