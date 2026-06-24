shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

// 공용 상태 아이콘 radial 게이지 (3D 머리 위 빌보드 quad 용).
// 중심부(반경 < CORE_R) = 아이콘(has_icon 면 icon_tex, 아니면 단색 심볼).
// 가장자리 ring(CORE_R ~ 1.0) = 12시 시작 시계방향 radial 게이지.
//   mode 0 (FILL_UP) : frac <= value 인 부분만 풀밝기, 나머지는 어둡게(미충전).
//   mode 1 (DEPLETE) : frac <= value 인 남은 부분이 풀밝기(소진되며 비워짐).
// uv 사각 밖(반경 > 1.0) = 투명.

uniform float value : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;            // 0 = FILL_UP, 1 = DEPLETE
uniform vec4 tint : source_color = vec4(1.0, 0.37, 0.69, 1.0);
uniform sampler2D icon_tex : source_color, hint_default_white;
uniform bool has_icon = false;

const float CORE_R = 0.58;       // 중심 아이콘 반경
const float RING_OUT = 0.98;     // 게이지 ring 바깥 반경
const float TWO_PI = 6.28318530718;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;   // 0(중심) ~ ~1.41(코너). 0.5 반경을 1.0 으로 정규화.

	vec3 col = tint.rgb;
	float a = 0.0;

	if (r <= CORE_R) {
		// 중심 아이콘/심볼.
		if (has_icon) {
			vec4 t = texture(icon_tex, UV);
			col = t.rgb * tint.rgb;
			a = t.a;
		} else {
			// 플레이스홀더 심볼 — 단색 원판(틴트). 가장자리 살짝 페더.
			col = tint.rgb;
			a = 1.0 - smoothstep(CORE_R - 0.06, CORE_R, r);
		}
	} else if (r <= RING_OUT) {
		// 가장자리 게이지 ring. 12시(위) 시작, 시계방향 0~1.
		float ang = atan(p.x, -p.y);          // 12시=0, 시계방향 증가.
		float frac = ang / TWO_PI;
		if (frac < 0.0) {
			frac += 1.0;
		}
		bool active;
		if (mode == 1) {
			active = frac <= value;           // DEPLETE — 남은 분량.
		} else {
			active = frac <= value;           // FILL_UP — 채워진 분량.
		}
		if (active) {
			col = tint.rgb;
			a = 1.0;
		} else {
			col = tint.rgb * 0.22;            // 미충전(어두운 트랙).
			a = 0.85;
		}
	} else {
		a = 0.0;                              // 바깥은 투명.
	}

	ALBEDO = col;
	ALPHA = a * tint.a;
}
