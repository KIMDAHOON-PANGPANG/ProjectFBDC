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
