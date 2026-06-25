extends SceneTree

## M9-S10: 납도류(18) + 연격류(10) = 28장 로드 검증.
## boons.json 28카드가 로드되고, style_req 필터가 두 발도술 풀을 안 섞는지 확인.

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 28)" % all.size())
	assert(all.size() == 28, "all_boons 크기 불일치 (M9-S10 28장 기대)")

	# 납도류 18개 id 전부 존재 + style_req='iaido'.
	var iaido_ids := [
		"iaido_draw", "iaido_perfect", "deep_mark", "sheathe_refund",
		"wide_blade", "no_sheathe", "chain_sheathe", "reverse_grip",
		"slash_extend", "iaido_finisher",
		"iai_domino", "reaping_cull", "epicenter_overcharge", "mark_contagion",
		"slow_field", "scatter_ring", "gauge_burst", "spirit_stack",
	]
	for id in iaido_ids:
		var card = _B.by_id(id)
		print("by_id(%s): %s" % [id, "OK" if card != null else "null"])
		assert(card != null, "by_id(%s) null — 카드 누락" % id)
		assert(String(card.get("skill_type", "")) != "", "skill_type 비어 있음 — %s" % id)
		assert(String(card.get("style_req", "")) == "iaido", "style_req 불일치(iaido) — %s" % id)

	# 연격류 10개 id 전부 존재 + style_req='nuki'.
	var nuki_ids := [
		"nuki_draw", "triple_draw", "beat_accel", "rhythm_beat",
		"draw_mark", "flurry_trace", "nuki_settle", "draw_refund",
		"chain_cadence", "dash_draw",
	]
	for id in nuki_ids:
		var card = _B.by_id(id)
		print("by_id(%s): %s" % [id, "OK" if card != null else "null"])
		assert(card != null, "by_id(%s) null — 연격 카드 누락" % id)
		assert(String(card.get("skill_type", "")) != "", "skill_type 비어 있음 — %s" % id)
		assert(String(card.get("style_req", "")) == "nuki", "style_req 불일치(nuki) — %s" % id)

	# 연격류 신규 효과 키 검증.
	var effect_for := {
		"nuki_draw": "STYLE_NUKI",
		"triple_draw": "NUKI_COMBO_EXT",
		"beat_accel": "NUKI_ACCEL",
		"rhythm_beat": "NUKI_RHYTHM",
		"nuki_settle": "NUKI_SETTLE",
		"chain_cadence": "NUKI_CADENCE",
	}
	for id in effect_for.keys():
		var card = _B.by_id(id)
		var comps = card.get("components", [])
		assert(comps is Array and not comps.is_empty(), "components 비어 있음 — %s" % id)
		var eff := String(comps[0].get("effect", ""))
		print("%s effect: %s (기대: %s)" % [id, eff, effect_for[id]])
		assert(eff == effect_for[id], "%s 효과 키 불일치" % id)

	# 철거된 옛 id 는 없어야 함.
	var gone = _B.by_id("gumiho_mark")
	assert(gone == null, "철거된 id 가 살아 있음")

	# draw_boons — 미보유 시 카드 반환(style 카드 노출 포함).
	var cards := _B.draw_boons(3, 5, [])
	print("draw_boons(3, 5, []): size=%d" % cards.size())
	assert(not cards.is_empty(), "draw_boons 빈 배열 (28장인데 비어 있음)")
	assert(cards.size() <= 3, "draw_boons count 초과")

	# ── style_req 필터: 납도(iaido) 보유 시 → 연격(nuki) 카드 안 섞임. ──
	var owned_iaido := ["iaido_draw"]
	var iaido_run := _B.draw_boons(3, 5, owned_iaido)
	for c in iaido_run:
		assert(String(c.get("id", "")) != "iaido_draw", "보유 카드 재노출")
		assert(String(c.get("kind", "")) != "style", "style exclusive 위반")
		var rc = _B.by_id(String(c.get("id", "")))
		var sr := String(rc.get("style_req", "")) if rc is Dictionary else ""
		assert(sr == "" or sr == "iaido", "iaido 런에 nuki 카드 섞임 — %s(%s)" % [c.get("id", ""), sr])

	# ── style_req 필터: 속발(nuki) 보유 시 → 납도(iaido) 카드 안 섞임. ──
	var owned_nuki := ["nuki_draw"]
	var nuki_run := _B.draw_boons(3, 5, owned_nuki)
	for c in nuki_run:
		assert(String(c.get("id", "")) != "nuki_draw", "보유 카드 재노출")
		assert(String(c.get("kind", "")) != "style", "style exclusive 위반")
		var rc = _B.by_id(String(c.get("id", "")))
		var sr := String(rc.get("style_req", "")) if rc is Dictionary else ""
		assert(sr == "" or sr == "nuki", "nuki 런에 iaido 카드 섞임 — %s(%s)" % [c.get("id", ""), sr])

	print("boon_load_check: 전체 통과 (M9-S10 28장 + style_req 필터)")
	quit()
