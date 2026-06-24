shader_type canvas_item;

// 공용 상태 아이콘 radial 게이지 (2D 하단 HUD Control 용).
// 로직은 status_radial_3d.gdshader 와 동일 — 중심 아이콘 + 가장자리 시계방향 ring.

uniform float value : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;            // 0 = FILL_UP, 1 = DEPLETE
uniform vec4 tint : source_color = vec4(1.0, 0.37, 0.69, 1.0);
uniform sampler2D icon_tex : source_color, hint_default_white;
uniform bool has_icon = false;

const float CORE_R = 0.58;
const float RING_OUT = 0.98;
const float TWO_PI = 6.28318530718;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;

	vec3 col = tint.rgb;
	float a = 0.0;

	if (r <= CORE_R) {
		if (has_icon) {
			vec4 t = texture(icon_tex, UV);
			col = t.rgb * tint.rgb;
			a = t.a;
		} else {
			col = tint.rgb;
			a = 1.0 - smoothstep(CORE_R - 0.06, CORE_R, r);
		}
	} else if (r <= RING_OUT) {
		float ang = atan(p.x, -p.y);
		float frac = ang / TWO_PI;
		if (frac < 0.0) {
			frac += 1.0;
		}
		bool active = frac <= value;
		if (active) {
			col = tint.rgb;
			a = 1.0;
		} else {
			col = tint.rgb * 0.22;
			a = 0.85;
		}
	} else {
		a = 0.0;
	}

	COLOR = vec4(col, a * tint.a);
}
