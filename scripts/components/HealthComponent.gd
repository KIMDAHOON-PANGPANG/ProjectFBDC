class_name HealthComponent
extends Node

signal damaged(amount: int)
signal died

@export var max_hp: int = 1

var hp: int

func _ready() -> void:
	hp = max_hp

func setup(new_max: int) -> void:
	max_hp = new_max
	hp = new_max

func take_damage(amount: int = 1) -> void:
	if hp <= 0:
		return
	hp -= amount
	damaged.emit(amount)
	if hp <= 0:
		died.emit()

func is_alive() -> bool:
	return hp > 0


## Restore `amount` HP up to `max_hp`. Pure no-op if currently dead — we
## don't resurrect via heal (Player.gd's Phoenix path resets hp directly).
## Emits `damaged(0)` so the HpBar3D / HUD refresh on heal (the bar
## listens for damaged to repaint; passing 0 reuses that path without
## adding a parallel `healed` signal).
func heal(amount: int) -> void:
	if hp <= 0:
		return
	if amount <= 0:
		return
	hp = min(hp + amount, max_hp)
	damaged.emit(0)
