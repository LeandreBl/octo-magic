shader_type canvas_item;
// The mage's chosen color (Profile.look.hat) as a tint: a dyed pixel takes its
// hue and at most its saturation, and keeps its own value (the art's shading).
// On a tentacle (body off) every pixel is dyed; on the body sprite (body on)
// only the hat's gold ribbon and the pink tentacle gripping the staff.

uniform vec4 dye : source_color = vec4(1.0);
uniform bool on = false;  // off: the art's own colors
uniform bool body = false;
uniform float frames = 8.0;  // the body strip's frames, side by side
uniform float staff_x = 0.6;  // in a frame's width: the staff's gold is right of it, the ribbon left
uniform vec4 status = vec4(0.0);  // a status filter (frozen, poisoned, burnt...): rgb its color, a its strength

varying vec4 tint;  // the vertex color (a status tint, modulate), applied after the dye

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(c.rgb);
	float h = hsv.x * 360.0;
	bool hit = on;
	if (on && body) {
		bool ribbon = h > 25.0 && h < 50.0 && hsv.y > 0.5 && fract(UV.x * frames) < staff_x;
		bool grip = h > 295.0 && h < 335.0 && hsv.y > 0.3;
		hit = ribbon || grip;
	}
	if (hit) {
		vec3 d = rgb2hsv(dye.rgb);
		c.rgb = hsv2rgb(vec3(d.x, min(hsv.y, d.y), hsv.z));
	}
	// The status filter: every pixel toward its color, keeping the art's shading.
	c.rgb = mix(c.rgb, status.rgb * (0.35 + 0.9 * rgb2hsv(c.rgb).z), status.a);
	COLOR = c * tint;
}
