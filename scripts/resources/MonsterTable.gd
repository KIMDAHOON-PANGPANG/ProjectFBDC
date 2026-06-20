class_name MonsterTable
extends Resource

## 모든 몬스터(MonsterStats)의 묶음 — enemy.csv 를 대체하는 인하우스 테이블 리소스.
## CombatData 가 런타임에 load 해서 id 로 찾아 적용한다. 밸런스 툴이 편집.

@export var monsters: Array[MonsterStats] = []

## id 로 몬스터 데이터 찾기(없으면 null).
func by_id(want_id: int) -> MonsterStats:
	for m in monsters:
		if m != null and m.id == want_id:
			return m
	return null
