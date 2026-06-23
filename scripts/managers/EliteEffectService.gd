extends Node

## Centralized elite-death payload dispatcher. Each elite type's
## `effect_type` (1=폭발, 2=보너스 슬래시, 3=불릿타임, 4=보호막) maps
## to a single `trigger(type, pos)` call. Extracted from Main.gd so
## Main + Testplay share the same logic instead of mirroring it.
##
## Wired by parent scene:
##   var es := EliteEffectService.new()
##   es.name = "EliteEffectService"
##   es.explosion_burst_scene = explosion_burst_scene
##   es.circular_slash_scene = circular_slash_scene
##   add_child(es)
##   es.setup(_player, _bullet_time_service)

@export var explosion_burst_scene: PackedScene
@export var circular_slash_scene: PackedScene

var _player: Node
var _bullet_time_service: Node
## True from a type-2 elite's death until the PC's next slash_finished
## fires the bonus CircularSlash. Guards against queuing a second
## bonus on top of an in-flight one.
var _pending_circular_slash: bool = false


func setup(player: Node, bullet_time_service: Node) -> void:
	_player = player
	_bullet_time_service = bullet_time_service


func trigger(effect_type: int, pos: Vector3) -> void:
	match effect_type:
		1:
			_spawn_explosion(pos)
		2:
			_queue_circular_slash_after_slash()
		3:
			if _bullet_time_service != null and _bullet_time_service.has_method("start"):
				_bullet_time_service.call("start")
		4:
			_give_player_shield()


func _spawn_explosion(pos: Vector3) -> void:
	if explosion_burst_scene == null:
		return
	var burst := explosion_burst_scene.instantiate() as Node3D
	var host := _effect_host()
	if host == null:
		burst.queue_free()
		return
	host.add_child(burst)
	burst.global_position = pos


## Public entry for non-elite callers (the Echo card) that just want a
## CircularSlash dropped at a position. Keeps `circular_slash_scene`
## owned by a single node instead of a copy living in Main.
func spawn_circular_slash(pos: Vector3, radius: float = -1.0, attack_power: int = 1, ring_color: Color = Color(0.8, 0.95, 1.0, 0.85)) -> void:
	_spawn_circular_slash(pos, radius, attack_power, ring_color)


func _spawn_circular_slash(pos: Vector3, radius: float = -1.0, attack_power: int = 1, ring_color: Color = Color(0.8, 0.95, 1.0, 0.85)) -> void:
	if circular_slash_scene == null:
		return
	var slash := circular_slash_scene.instantiate() as Node3D
	var host := _effect_host()
	if host == null:
		slash.queue_free()
		return
	host.add_child(slash)
	if slash.has_method("configure"):
		slash.call("configure", radius, attack_power, ring_color)
	slash.global_position = pos


## World node to parent spawned effects under. Active scene normally; falls
## back to our parent (Main/Testplay) / tree root during a scene reload.
func _effect_host() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	var p := get_parent()
	if p != null:
		return p
	return tree.root


## Type-2 elite died. If the PC is still mid-iaido dash, wait for
## slash_finished; otherwise fire immediately at PC's current position.
func _queue_circular_slash_after_slash() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _pending_circular_slash:
		return
	var is_dashing: bool = false
	if "_state" in _player:
		is_dashing = _player._state == 2  # Player.State.DASHING
	if is_dashing and _player.has_signal("slash_finished"):
		_pending_circular_slash = true
		_player.slash_finished.connect(_on_pending_slash_finished, CONNECT_ONE_SHOT)
		# Safety: if Player dies before slash_finished, CONNECT_ONE_SHOT
		# auto-disconnects but the flag would stay stuck.
		get_tree().create_timer(1.5).timeout.connect(_clear_pending_circular_slash)
	else:
		_spawn_circular_slash((_player as Node3D).global_position)


func _on_pending_slash_finished() -> void:
	_pending_circular_slash = false
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_circular_slash((_player as Node3D).global_position)


func _clear_pending_circular_slash() -> void:
	_pending_circular_slash = false


func _give_player_shield() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if "shield_charges" in _player:
		_player.shield_charges += 1


## Re-target after a chapter transition (Main._advance_chapter rebuilds
## bookkeeping). Player ref may be the same instance — passing it
## defensively keeps the contract explicit.
func rebind(player: Node, bullet_time_service: Node) -> void:
	_player = player
	_bullet_time_service = bullet_time_service
	_pending_circular_slash = false
