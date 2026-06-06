extends Node

## ⏱ Zen meter (M4 후속 → 이번 패스에서 도입). Counts consecutive
## "perfect" inputs: perfect parries, perfect-charged slashes (>=0.65s
## charge), perfect dodges. When the meter fills, the PC's next slash
## becomes a 풀폭 slash (wide hitbox, max range, deals 5 dmg to bosses).
## Damage gets consumed.
##
## Wired by Main / Testplay:
##   var zs := ZenSystem.new()
##   zs.name = "ZenSystem"
##   add_child(zs)
##   zs.bind(_player)
## Then Player.on_parry_success / Player._fire_slash report into the
## system; HUD label reads `.zen` / `.max_zen` for display.

signal zen_changed(current: int, maximum: int)
signal zen_full
signal burst_consumed

@export var max_zen: int = 5

var zen: int = 0
var burst_armed: bool = false  # True from full → next slash, drives Player.has_zen_burst
var _player: Node


func bind(player: Node) -> void:
	_player = player
	# Refresh the burst flag on the live PC in case the system reattaches
	# (chapter transition).
	_push_burst_state()


func add(amount: int = 1) -> void:
	if amount <= 0:
		return
	if burst_armed:
		# Already full + waiting for the slash. Extra perfects don't
		# stack past max — they just hold the bar at full.
		zen_changed.emit(zen, max_zen)
		return
	zen = min(zen + amount, max_zen)
	zen_changed.emit(zen, max_zen)
	if zen >= max_zen:
		burst_armed = true
		_push_burst_state()
		zen_full.emit()


## Called by Player.gd right BEFORE the burst slash fires. Drops the
## meter to 0, disarms the burst flag, and notifies any listeners
## (e.g. SuperSlash spawner — currently inline).
func consume_burst() -> bool:
	if not burst_armed:
		return false
	burst_armed = false
	zen = 0
	_push_burst_state()
	zen_changed.emit(zen, max_zen)
	burst_consumed.emit()
	return true


## On hit, drain the meter to keep the "reward for sustained perfect
## play" pressure. Halve current, don't disarm an already-armed burst.
func drain_on_hit() -> void:
	if burst_armed:
		return
	zen = int(zen / 2)
	zen_changed.emit(zen, max_zen)


func _push_burst_state() -> void:
	if _player != null and is_instance_valid(_player) and "has_zen_burst" in _player:
		_player.has_zen_burst = burst_armed
