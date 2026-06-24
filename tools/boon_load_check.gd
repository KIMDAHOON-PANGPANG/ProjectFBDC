extends SceneTree

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 2)" % all.size())
	assert(all.size() == 2, "all_boons 크기 불일치")

	var mark = _B.by_id("gumiho_mark")
	print("by_id(gumiho_mark) name: %s" % str(mark.get("name", "?")))

	var gumiho_list := _B.by_yokai("GUMIHO")
	print("by_yokai(GUMIHO) size: %d (기대: 2)" % gumiho_list.size())
	assert(gumiho_list.size() == 2, "by_yokai 크기 불일치")

	var rarities := _B.rarities_for("gumiho_mark")
	print("rarities_for(gumiho_mark): %s" % str(rarities))
	assert(rarities == ["chosim", "rare", "uniq", "legend", "master"], "rarities 순서 불일치")

	var master_params := _B.params_for("gumiho_mark", "master")
	print("params_for(gumiho_mark, master): %s" % str(master_params))
	assert(int(master_params.get("per_hits", -1)) == 1, "per_hits 불일치")
	assert(int(master_params.get("mark_add", -1)) == 1, "mark_add 불일치")
	assert(int(master_params.get("cap", -1)) == 8, "cap 불일치")

	var uniq_params := _B.params_for("gumiho_lifesteal", "uniq")
	print("params_for(gumiho_lifesteal, uniq): %s" % str(uniq_params))
	assert(float(uniq_params.get("heal_per_mark", -1.0)) == 0.9, "heal_per_mark 불일치")
	assert(int(uniq_params.get("transfer", -1)) == 1, "transfer 불일치")

	print("boon_load_check: 전체 통과")
	quit()
