extends SceneTree

## M9-S1: M8 요괴 콘텐츠 전면 철거 후 — boons.json 빈 배열(0장) 로드 graceful 검증.
## S3+ 에서 M9 카드를 채우면 이 어서션을 다시 갱신한다.

func _initialize() -> void:
	const _B := preload("res://scripts/managers/BoonSystem.gd")

	var all := _B.all_boons()
	print("all_boons size: %d (기대: 0)" % all.size())
	assert(all.size() == 0, "all_boons 크기 불일치 (빈 풀 기대)")

	var missing = _B.by_id("gumiho_mark")
	print("by_id(gumiho_mark): %s (기대: null)" % str(missing))
	assert(missing == null, "by_id 빈 풀에서 null 아님")

	var cards := _B.draw_boons(3, 5, [])
	print("draw_boons(3, 5, []): %s (기대: 빈 배열)" % str(cards))
	assert(cards.is_empty(), "draw_boons 빈 풀에서 빈 배열 아님")

	print("boon_load_check: 전체 통과 (0장 — M9-S1 철거 상태)")
	quit()
