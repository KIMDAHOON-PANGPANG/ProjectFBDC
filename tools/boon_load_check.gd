extends SceneTree

## M9-S4: 납도류 풀세트(스타일 1 + 9 = 10장) 로드 검증.
## boons.json 10카드가 로드되고 draw_boons 가 유효 카드를 반환하는지 확인.

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 10)" % all.size())
	assert(all.size() == 10, "all_boons 크기 불일치 (M9-S4 10장 기대)")

	# 10개 id 전부 존재 확인.
	var ids := [
		"iaido_draw", "iaido_perfect", "deep_mark", "sheathe_refund",
		"wide_blade", "no_sheathe", "chain_sheathe", "reverse_grip",
		"slash_extend", "iaido_finisher",
	]
	for id in ids:
		var card = _B.by_id(id)
		print("by_id(%s): %s" % [id, "OK" if card != null else "null"])
		assert(card != null, "by_id(%s) null — 카드 누락" % id)
		assert(String(card.get("skill_type", "")) != "", "skill_type 비어 있음 — %s" % id)
		assert(String(card.get("style_req", "")) == "iaido", "style_req 누락 — %s" % id)

	# 철거된 옛 id 는 없어야 함.
	var gone = _B.by_id("gumiho_mark")
	print("by_id(gumiho_mark): %s (기대: null)" % str(gone))
	assert(gone == null, "철거된 id 가 살아 있음")

	# 6개 신규 효과 키가 components 에 존재하는지 확인.
	var effect_for := {
		"wide_blade": "MARK_SPREAD",
		"no_sheathe": "IAIDO_CHAIN",
		"chain_sheathe": "SHEATHE_DOMINO",
		"reverse_grip": "IAIDO_HASTE",
		"slash_extend": "SLASH_EXTEND",
		"iaido_finisher": "IAIDO_FINISHER",
	}
	for id in effect_for.keys():
		var card = _B.by_id(id)
		var comps = card.get("components", [])
		assert(comps is Array and not comps.is_empty(), "components 비어 있음 — %s" % id)
		var eff := String(comps[0].get("effect", ""))
		print("%s effect: %s (기대: %s)" % [id, eff, effect_for[id]])
		assert(eff == effect_for[id], "%s 효과 키 불일치" % id)

	# draw_boons 가 카드를 반환 + 카드 형태 유효.
	var cards := _B.draw_boons(3, 5, [])
	print("draw_boons(3, 5, []): size=%d" % cards.size())
	assert(not cards.is_empty(), "draw_boons 빈 배열 (10장인데 비어 있음)")
	assert(cards.size() <= 3, "draw_boons count 초과")
	for c in cards:
		assert(String(c.get("skill_type", "")) != "", "draw 카드 skill_type 무효")
		assert(String(c.get("id", "")) != "", "draw 카드 id 무효")

	# 스타일 exclusive — 발도 보유 시 발도(style) 미노출.
	var owned := ["iaido_draw"]
	var cards2 := _B.draw_boons(3, 5, owned)
	for c in cards2:
		assert(String(c.get("id", "")) != "iaido_draw", "보유 카드 재노출")
		assert(String(c.get("kind", "")) != "style", "style exclusive 위반 — style 카드 재노출")

	print("boon_load_check: 전체 통과 (M9-S4 10장)")
	quit()
