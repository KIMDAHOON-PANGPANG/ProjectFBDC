extends RefCounted

## 스무스 넉백 헬퍼 — 적이 1개씩 소유한다(`var _kb = preload(...).new()`).
## push() 로 밀침 속도를 넣으면 integrate() 가 매 프레임 위치를 밀고 속도를 선형
## 감쇠시켜 부드럽게 멈춘다. 기존의 "즉시 global_position += push"(순간이동) 방식이
## 연출이 가벼워 보여서, 짧게 미끄러지는 감쇠 슬라이드로 교체했다.
##
## class_name 없이 preload + .new() 로 쓴다(헤드리스 class_name 캐시 회피).

## 초당 속도 감쇠량(유닛/초). 클수록 더 짧고 빠르게 멈춘다.
## 예) 속도 12 → 약 12/35 ≈ 0.34초, 이동거리 ≈ 12²/(2·35) ≈ 2.06 유닛.
const DECAY := 35.0

var vel: Vector3 = Vector3.ZERO


## 밀침 시작 — dir 방향으로 speed(유닛/초)의 넉백 속도를 준다(기존 값 덮어씀).
func push(dir: Vector3, speed: float) -> void:
	var d := dir
	d.y = 0.0
	if d.length() < 0.001 or speed <= 0.0:
		return
	vel = d.normalized() * speed


## 매 프레임 호출 — 넉백 속도만큼 위치를 밀고 감쇠. 충돌은 무시(짧은 푸시라 OK,
## 대시/리프와 동일하게 직접 위치 이동). 활성 중이 아니면 즉시 반환.
func integrate(node: Node3D, delta: float) -> void:
	if vel.length_squared() <= 0.0025:
		vel = Vector3.ZERO
		return
	node.global_position += vel * delta
	vel = vel.move_toward(Vector3.ZERO, DECAY * delta)
