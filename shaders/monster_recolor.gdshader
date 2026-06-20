shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// 어두운 몸 스프라이트(예: Sword)도 색상 베리에이션이 보이도록 루미넌스→tint 매핑.
// Sprite3D.material_override 로 적용 — 빌보드/프레임 UV/플립은 Sprite3D 가 그대로 처리,
// COLOR(=Sprite3D.modulate)로 플래시/블링크/페이드도 유지.

uniform sampler2D albedo : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.72;

void vertex() {
	// 빌보드(스케일 유지) — Sprite3D 의 BILLBOARD_ENABLED 대체(override 시 자동 안 됨).
	mat4 mw = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]);
	mw = mw * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
}

void fragment() {
	vec4 c = texture(albedo, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 루미넌스를 tint 밝기에 매핑 → 어두운 몸도 tint 색으로 보인다(베리에이션).
	vec3 recolored = tint.rgb * clamp(lum * 1.7 + 0.18, 0.0, 1.0);
	vec3 base = mix(c.rgb, recolored, tint_strength);
	ALBEDO = base * COLOR.rgb;     // COLOR = Sprite3D.modulate (플래시/블링크)
	ALPHA = c.a * COLOR.a;         // 텍스처 알파 × 모듈레이트 알파(페이드/블링크)
}
