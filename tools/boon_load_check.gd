extends SceneTree

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 15)" % all.size())
	assert(all.size() == 15, "all_boons 크기 불일치")

	var mark = _B.by_id("gumiho_mark")
	print("by_id(gumiho_mark) name: %s" % str(mark.get("name", "?")))

	var gumiho_list := _B.by_yokai("GUMIHO")
	print("by_yokai(GUMIHO) size: %d (기대: 8)" % gumiho_list.size())
	assert(gumiho_list.size() == 8, "by_yokai(GUMIHO) 크기 불일치")

	var dokebi_list := _B.by_yokai("DOKEBI")
	print("by_yokai(DOKEBI) size: %d (기대: 7)" % dokebi_list.size())
	assert(dokebi_list.size() == 7, "by_yokai(DOKEBI) 크기 불일치")

	var rarities := _B.rarities_for("gumiho_mark")
	print("rarities_for(gumiho_mark): %s" % str(rarities))
	assert(rarities == ["chosim", "rare", "uniq", "legend", "master"], "rarities 순서 불일치")

	# 기존 3 카드 params 보존 검증.
	var master_params := _B.params_for("gumiho_mark", "master")
	print("params_for(gumiho_mark, master): %s" % str(master_params))
	assert(int(master_params.get("per_hits", -1)) == 1, "per_hits 불일치")
	assert(int(master_params.get("mark_add", -1)) == 1, "mark_add 불일치")
	assert(int(master_params.get("cap", -1)) == 8, "cap 불일치")

	var uniq_params := _B.params_for("gumiho_lifesteal", "uniq")
	print("params_for(gumiho_lifesteal, uniq): %s" % str(uniq_params))
	assert(float(uniq_params.get("heal_per_mark", -1.0)) == 0.9, "heal_per_mark 불일치")
	assert(int(uniq_params.get("transfer", -1)) == 1, "transfer 불일치")

	# 신규 5 카드 스폿체크.
	var charm = _B.by_id("gumiho_charm")
	assert(charm != null, "gumiho_charm 없음")
	var charm_uniq := _B.params_for("gumiho_charm", "uniq")
	print("params_for(gumiho_charm, uniq): %s" % str(charm_uniq))
	assert(float(charm_uniq.get("radius", 0.0)) > 0.0, "charm radius 불량")
	assert(float(charm_uniq.get("burst_knockback", 0.0)) > 0.0, "charm burst_knockback 불량")

	var summon_uniq := _B.params_for("gumiho_summon", "uniq")
	print("params_for(gumiho_summon, uniq): %s" % str(summon_uniq))
	assert(int(summon_uniq.get("count", 0)) >= 1, "summon count 불량")
	assert(float(summon_uniq.get("lifetime", 0.0)) > 0.0, "summon lifetime 불량")

	var fox_uniq := _B.params_for("gumiho_foxfire", "uniq")
	print("params_for(gumiho_foxfire, uniq): %s" % str(fox_uniq))
	assert(int(fox_uniq.get("count", 0)) >= 1, "foxfire count 불량")
	assert(float(fox_uniq.get("speed", 0.0)) > 0.0, "foxfire speed 불량")

	var fan_uniq := _B.params_for("gumiho_slashfan", "uniq")
	print("params_for(gumiho_slashfan, uniq): %s" % str(fan_uniq))
	assert(float(fan_uniq.get("width_mult", 0.0)) > 1.0, "slashfan width_mult 불량")

	var radial_uniq := _B.params_for("gumiho_radial", "uniq")
	print("params_for(gumiho_radial, uniq): %s" % str(radial_uniq))
	assert(int(radial_uniq.get("count", 0)) >= 1, "radial count 불량")

	# 트리거/effect 매핑 스폿체크.
	var charm_comps = charm.get("components", [])
	assert(charm_comps.size() > 0, "charm components 없음")
	assert(String(charm_comps[0].get("trigger", "")) == "On_Slash_Hit", "charm trigger 불일치")
	assert(String(charm_comps[0].get("effect", "")) == "CHARM_ZONE", "charm effect 불일치")

	var fox = _B.by_id("gumiho_foxfire")
	var fox_comps = fox.get("components", [])
	assert(String(fox_comps[0].get("trigger", "")) == "On_Mark_Full", "foxfire trigger 불일치")
	assert(String(fox_comps[0].get("effect", "")) == "HOMING_PROJECTILE", "foxfire effect 불일치")

	# ── 도깨비 7카드 스폿체크 ──
	var dokebi_ids := ["dokebi_foxfire", "dokebi_chain", "dokebi_smash",
		"dokebi_extrafan", "dokebi_clone", "dokebi_gold", "dokebi_ignite"]
	for did in dokebi_ids:
		var b = _B.by_id(did)
		assert(b != null, "%s 없음" % did)
		assert(String(b.get("yokai", "")) == "DOKEBI", "%s yokai 불일치" % did)
		var comps = b.get("components", [])
		assert(comps.size() > 0, "%s components 없음" % did)
		# 등급 5단 보존.
		var rar := _B.rarities_for(did)
		assert(rar == ["chosim", "rare", "uniq", "legend", "master"], "%s rarities 불일치" % did)

	# 효과 매핑 스폿체크.
	var dfox = _B.by_id("dokebi_foxfire").get("components", [])[0]
	assert(String(dfox.get("trigger", "")) == "On_Slash_Hit", "dokebi_foxfire trigger 불일치")
	assert(String(dfox.get("effect", "")) == "HOMING_PROJECTILE", "dokebi_foxfire effect 불일치")
	var dchain = _B.by_id("dokebi_chain").get("components", [])[0]
	assert(String(dchain.get("effect", "")) == "CHAIN_BURST", "dokebi_chain effect 불일치")
	var dsmash = _B.by_id("dokebi_smash").get("components", [])[0]
	assert(String(dsmash.get("trigger", "")) == "On_Slash_End", "dokebi_smash trigger 불일치")
	assert(String(dsmash.get("effect", "")) == "SMASH", "dokebi_smash effect 불일치")
	var dfan = _B.by_id("dokebi_extrafan").get("components", [])[0]
	assert(String(dfan.get("effect", "")) == "EXTRA_FAN", "dokebi_extrafan effect 불일치")
	var dclone = _B.by_id("dokebi_clone").get("components", [])[0]
	assert(String(dclone.get("effect", "")) == "SUMMON_CLONE", "dokebi_clone effect 불일치")
	var dgold = _B.by_id("dokebi_gold").get("components", [])[0]
	assert(String(dgold.get("effect", "")) == "GOLD_REFUND", "dokebi_gold effect 불일치")
	var dignite = _B.by_id("dokebi_ignite").get("components", [])[0]
	assert(String(dignite.get("trigger", "")) == "On_Just_Dodge", "dokebi_ignite trigger 불일치")
	assert(String(dignite.get("effect", "")) == "IGNITE_ZONE", "dokebi_ignite effect 불일치")

	# 도깨비 params 스폿체크.
	var smash_uniq := _B.params_for("dokebi_smash", "uniq")
	assert(float(smash_uniq.get("radius", 0.0)) > 0.0, "dokebi_smash radius 불량")
	assert(float(smash_uniq.get("knockback", 0.0)) > 0.0, "dokebi_smash knockback 불량")
	var gold_master := _B.params_for("dokebi_gold", "master")
	assert(float(gold_master.get("heat_refund", 0.0)) > 0.0, "dokebi_gold heat_refund 불량")

	print("boon_load_check: 전체 통과 (15장 = 구미호8 + 도깨비7)")
	quit()
