extends SceneTree

## M9-S11: 납도류(18) + 연격류(10) + 충전류(10) = 38장 로드 검증.
## boons.json 38카드가 로드되고, style_req 필터가 세 발도술 풀을 안 섞는지 확인.

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 38)" % all.size())
	assert(all.size() == 38, "all_boons 크기 불일치 (M9-S11 38장 기대)")

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

	# 충전류 10개 id 전부 존재 + style_req='charge'.
	var charge_ids := [
		"charge_draw", "deep_breath", "draw_master", "pierce_reap", "deep_charge",
		"pierce_line", "dual_align", "charge_whirl", "afterglow_draw", "pierce_thunder",
	]
	for id in charge_ids:
		var card = _B.by_id(id)
		print("by_id(%s): %s" % [id, "OK" if card != null else "null"])
		assert(card != null, "by_id(%s) null — 충전 카드 누락" % id)
		assert(String(card.get("skill_type", "")) != "", "skill_type 비어 있음 — %s" % id)
		assert(String(card.get("style_req", "")) == "charge", "style_req 불일치(charge) — %s" % id)

	# 연격류 + 충전류 신규 효과 키 검증.
	var effect_for := {
		"nuki_draw": "STYLE_NUKI",
		"triple_draw": "NUKI_COMBO_EXT",
		"beat_accel": "NUKI_ACCEL",
		"rhythm_beat": "NUKI_RHYTHM",
		"nuki_settle": "NUKI_SETTLE",
		"chain_cadence": "NUKI_CADENCE",
		"charge_draw": "STYLE_CHARGE",
		"deep_breath": "CHARGE_HASTE",
		"draw_master": "CHARGE_PERFECT",
		"pierce_reap": "PIERCE_REAP",
		"deep_charge": "DEEP_CHARGE_MARK",
		"dual_align": "CHARGE_ALIGN",
		"charge_whirl": "CHARGE_DASH_CANCEL",
		"afterglow_draw": "CHARGE_AFTERGLOW",
		"pierce_thunder": "PIERCE_THUNDER",
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

	# ── M9-S12 첫 발도술 강제 1픽 — 미보유 첫 draw 는 '전부 style 카드(발도술)'여야 한다. ──
	# build-up/universal 카드가 섞이면 첫 픽에서 스타일이 안 정해질 수 있어 cap/템포 축이 무너진다.
	for c in cards:
		assert(String(c.get("kind", "")) == "style", "미보유 첫 draw 가 style 카드 아님 — %s(kind=%s)" % [c.get("id", ""), c.get("kind", "")])
	# 발도술 3종이 같은 slot('발도술')임에도 강제 픽에서는 셋 다 노출돼야 한다(slot 중복 가드 우회 확인).
	# count=3 으로 뽑았으므로 발도/속발/일도양단 3종이 모두 노출될 것을 기대(풀이 정확히 style 3장).
	var style_ids := {}
	for c in cards:
		style_ids[String(c.get("id", ""))] = true
	print("미보유 첫 draw style ids: %s (size=%d)" % [style_ids.keys(), style_ids.size()])
	assert(style_ids.size() == 3, "강제 첫 픽에서 발도술 3종이 모두 노출되지 않음(slot 중복 가드 우회 실패)")
	assert(style_ids.has("iaido_draw") and style_ids.has("nuki_draw") and style_ids.has("charge_draw"),
		"강제 첫 픽 style 3종(iaido/nuki/charge) 누락")

	# ── M9-S12 스타일별 mark_cap params — 발도술 3종 params 에 cap(iaido5/nuki3/charge7) 노출 확인. ──
	var iaido_p := _B.params_for("iaido_draw", "chosim", 0)
	var nuki_p := _B.params_for("nuki_draw", "chosim", 0)
	var charge_p := _B.params_for("charge_draw", "chosim", 0)
	print("mark_cap — iaido:%s nuki:%s charge:%s" % [iaido_p.get("mark_cap", "?"), nuki_p.get("mark_cap", "?"), charge_p.get("mark_cap", "?")])
	assert(int(iaido_p.get("mark_cap", -1)) == 5, "iaido mark_cap 5(미들) 아님")
	assert(int(nuki_p.get("mark_cap", -1)) == 3, "nuki mark_cap 3(숏) 아님")
	assert(int(charge_p.get("mark_cap", -1)) == 7, "charge mark_cap 7(롱) 아님")

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

	# ── style_req 필터: 충전(charge) 보유 시 → 납도/연격 카드 안 섞임 + style 재노출 안 됨(3풀 분리). ──
	var owned_charge := ["charge_draw"]
	var charge_run := _B.draw_boons(3, 5, owned_charge)
	for c in charge_run:
		assert(String(c.get("id", "")) != "charge_draw", "보유 카드 재노출")
		assert(String(c.get("kind", "")) != "style", "style exclusive 위반 — charge 런에 style 카드 노출")
		var rc = _B.by_id(String(c.get("id", "")))
		var sr := String(rc.get("style_req", "")) if rc is Dictionary else ""
		assert(sr == "" or sr == "charge", "charge 런에 iaido/nuki 카드 섞임 — %s(%s)" % [c.get("id", ""), sr])

	print("boon_load_check: 전체 통과 (M9-S11 38장 + style_req 3풀 필터)")
	quit()
