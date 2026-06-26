extends SceneTree

## M9-T7: 납도류(18) + 연격류(10) + 충전류(10) + 보조(11) + baseline 5 = 54장 로드 검증.
## pool 분기(pillar/style_kit/support) + L2 발도술 3종 결정적 노출 + L3+ style_kit/support 합성 확인.

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 54)" % all.size())
	assert(all.size() == 54, "all_boons 크기 불일치 (M9-T7 54장 기대)")

	# ── pool 분류 카운트: pillar 3 / style_kit 35 / support 16. ──
	var pool_count := {"pillar": 0, "style_kit": 0, "support": 0, "": 0}
	for b in all:
		var p := String(b.get("pool", ""))
		pool_count[p] = int(pool_count.get(p, 0)) + 1
	print("pools — pillar:%d style_kit:%d support:%d (빈값:%d)" % [pool_count["pillar"], pool_count["style_kit"], pool_count["support"], pool_count[""]])
	assert(pool_count["pillar"] == 3, "pillar 3장 아님")
	assert(pool_count["style_kit"] == 35, "style_kit 35장 아님")
	assert(pool_count["support"] == 16, "support 16장 아님")
	assert(pool_count[""] == 0, "pool 키 없는 카드 존재")

	# pillar 3종 = 발도술(kind=='style').
	for id in ["iaido_draw", "nuki_draw", "charge_draw"]:
		var card = _B.by_id(id)
		assert(card != null, "pillar 카드 누락 — %s" % id)
		assert(String(card.get("pool", "")) == "pillar", "pillar pool 아님 — %s" % id)
		assert(String(card.get("kind", "")) == "style", "pillar kind!=style — %s" % id)

	# ── 보조(support) 11장 id + 효과 키 + style_req 검증. ──
	var support_effect := {
		"gather_echo": ["SUPPORT_GATHER_FIELD", ""],
		"dash_afterimage": ["SUPPORT_DASH_FIELD", ""],
		"gale_spirit": ["SUPPORT_DASH_HASTE", ""],
		"vent_dash": ["SUPPORT_DASH_VENT", ""],
		"calm_breath": ["SUPPORT_SLASH_VENT", ""],
		"residual_heat": ["SUPPORT_KILL_VENT", ""],
		"soul_magnet": ["SUPPORT_KILL_MAGNET", ""],
		"harvest_pull": ["SUPPORT_SHEATHE_MAGNET", "iaido"],
		"mark_accel": ["SUPPORT_MARK_ACCEL", ""],
		"dash_mark": ["SUPPORT_DASH_MARK", "charge"],
		"draw_afterglow": ["SUPPORT_KILL_AFTERGLOW", "charge"],
		"bl_heal": ["BL_HEAL", ""],
		"bl_gem": ["BL_GEM", ""],
		"bl_spread": ["BL_SPREAD", "nuki"],
		"bl_heat": ["BL_HEAT", "charge"],
		"bl_echo": ["BL_ECHO", "iaido"],
	}
	for id in support_effect.keys():
		var card = _B.by_id(id)
		print("by_id(%s): %s" % [id, "OK" if card != null else "null"])
		assert(card != null, "보조 카드 누락 — %s" % id)
		assert(String(card.get("pool", "")) == "support", "support pool 아님 — %s" % id)
		assert(String(card.get("kind", "")) == "support", "support kind 아님 — %s" % id)
		assert(String(card.get("skill_type", "")) != "", "skill_type 비어 있음 — %s" % id)
		assert(String(card.get("style_req", "")) == support_effect[id][1], "style_req 불일치 — %s" % id)
		var comps = card.get("components", [])
		assert(comps is Array and not comps.is_empty(), "components 비어 있음 — %s" % id)
		var eff := String(comps[0].get("effect", ""))
		assert(eff == support_effect[id][0], "%s 효과 키 불일치(%s)" % [id, eff])
		# 5등급 params 전부 존재.
		var rs := _B.rarities_for(id)
		assert(rs.size() == 5, "%s 등급 5개 아님 (%d)" % [id, rs.size()])

	# 납도류 18 + 연격류 10 + 충전류 10 = 38 (기존) style_req 풀 검증(축약).
	for id in ["iaido_perfect", "deep_mark", "chain_sheathe", "slow_field"]:
		assert(String(_B.by_id(id).get("style_req", "")) == "iaido", "iaido 풀 누락 — %s" % id)
	for id in ["triple_draw", "nuki_settle"]:
		assert(String(_B.by_id(id).get("style_req", "")) == "nuki", "nuki 풀 누락 — %s" % id)
	for id in ["pierce_reap", "pierce_thunder"]:
		assert(String(_B.by_id(id).get("style_req", "")) == "charge", "charge 풀 누락 — %s" % id)

	# 철거된 옛 id 는 없어야 함.
	assert(_B.by_id("gumiho_mark") == null, "철거된 id 가 살아 있음")

	# ── L2(첫 레벨업·style 미보유) — pillar(발도술 3종)만 결정적 노출. ──
	var l2 := _B.draw_boons(3, 2, [])
	print("L2 draw(3, 2, []): size=%d" % l2.size())
	assert(l2.size() == 3, "L2 발도술 3종 노출 아님 (%d)" % l2.size())
	var l2_ids := {}
	for c in l2:
		assert(String(c.get("kind", "")) == "style", "L2 카드 style 아님 — %s" % c.get("id", ""))
		assert(String(c.get("pool", "")) == "pillar", "L2 카드 pool!=pillar — %s" % c.get("id", ""))
		l2_ids[String(c.get("id", ""))] = true
	assert(l2_ids.size() == 3, "L2 발도술 3종 결정적 노출 실패 (중복/누락)")
	assert(l2_ids.has("iaido_draw") and l2_ids.has("nuki_draw") and l2_ids.has("charge_draw"),
		"L2 발도술 3종(iaido/nuki/charge) 누락")

	# 결정적 노출 — 여러 번 뽑아도 항상 같은 3종 집합(순서만 다를 수 있음).
	for _n in range(8):
		var r := _B.draw_boons(3, 2, [])
		var s := {}
		for c in r:
			s[String(c.get("id", ""))] = true
		assert(s.size() == 3 and s.has("iaido_draw") and s.has("nuki_draw") and s.has("charge_draw"),
			"L2 결정적 노출 위반 — 매번 같은 발도술 3종이어야 함")

	# ── L3+(iaido 보유) — pillar 제외 + style exclusive + style_req(iaido/universal) + support 합류 확인. ──
	var owned_iaido := ["iaido_draw"]
	var l3 := _B.draw_boons(3, 5, owned_iaido)
	print("L3 draw(3, 5, [iaido]): size=%d" % l3.size())
	assert(l3.size() == 3, "L3 카드 3장 아님 (%d)" % l3.size())
	for c in l3:
		assert(String(c.get("id", "")) != "iaido_draw", "보유 카드 재노출")
		assert(String(c.get("pool", "")) != "pillar", "L3 에 pillar 재노출 — %s" % c.get("id", ""))
		assert(String(c.get("kind", "")) != "style", "style exclusive 위반")
		var rc = _B.by_id(String(c.get("id", "")))
		var sr := String(rc.get("style_req", "")) if rc is Dictionary else ""
		assert(sr == "" or sr == "iaido", "iaido 런에 다른 발도술 카드 섞임 — %s(%s)" % [c.get("id", ""), sr])
		# pool 키가 결과 dict 에 실려 있어야 함(Main/Testplay _selected_cards 미러용).
		assert(String(c.get("pool", "")) in ["style_kit", "support"], "L3 결과 pool 키 누락/오류 — %s" % c.get("id", ""))

	# ── support_slots 비율 — L6+ 여러 번 뽑아 support 가 끼는지(도배 안 됨, 1~2장) 통계 확인. ──
	var support_seen_max := 0
	for _n in range(30):
		var r := _B.draw_boons(3, 6, owned_iaido)
		var sc := 0
		for c in r:
			if String(c.get("pool", "")) == "support":
				sc += 1
		support_seen_max = max(support_seen_max, sc)
		assert(sc <= 2, "L6 support 슬롯 2 초과 — 도배 방지 위반 (%d)" % sc)
	print("L6 max support slots seen over 30 draws: %d" % support_seen_max)
	assert(support_seen_max >= 1, "L6 에서 support 가 한 번도 안 끼임 — 합류 실패")

	# ── L3~5 support_slots == 1 상한 — 여러 번 뽑아 2 이상 안 나오는지. ──
	for _n in range(20):
		var r := _B.draw_boons(3, 4, owned_iaido)
		var sc := 0
		for c in r:
			if String(c.get("pool", "")) == "support":
				sc += 1
		assert(sc <= 1, "L4 support 슬롯 1 초과 (%d)" % sc)

	# ── charge 런 — support 의 charge 전용(dash_mark/draw_afterglow)만 합류, iaido 전용(harvest_pull) 제외. ──
	var owned_charge := ["charge_draw"]
	for _n in range(20):
		var r := _B.draw_boons(3, 6, owned_charge)
		for c in r:
			var id := String(c.get("id", ""))
			assert(id != "harvest_pull", "charge 런에 iaido 전용 support(harvest_pull) 섞임")
			assert(String(c.get("kind", "")) != "style", "charge 런 style exclusive 위반")

	print("boon_load_check: 전체 통과 (M9-T7 54장 + pool 분기 + L2/L3+ 합성)")
	quit()
