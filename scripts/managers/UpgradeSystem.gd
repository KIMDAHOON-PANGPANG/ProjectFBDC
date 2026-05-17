class_name UpgradeSystem
extends RefCounted

## Card pool + apply logic for Vampire-Survivors-style level-up upgrades.
##
## Cards are identified by string IDs. `draw(n)` returns a shuffled subset of
## card descriptors (id/name/desc) for the UI to render. `apply(id, ...)`
## actually mutates the player or exp system.
##
## Cards stack — picking the same card again applies its effect a second time.

const CARDS := [
	{"id": "razor_edge",  "name": "Razor's Edge", "desc": "Slash width +30%"},
	{"id": "quickstep",   "name": "Quickstep",    "desc": "Move speed +20%"},
	{"id": "iron_will",   "name": "Iron Will",    "desc": "Max HP +1"},
	{"id": "wind_walker", "name": "Wind Walker",  "desc": "Dash cooldown -25%"},
	{"id": "greed",       "name": "Greed",        "desc": "EXP gain +25%"},
	{"id": "reach",       "name": "Reach",        "desc": "Slash max range +20%"},
	{"id": "vigilance",   "name": "Vigilance",    "desc": "Slash cooldown -30%"},
]

## Draw `n` distinct cards from the pool. Returns an Array of card dicts.
static func draw(n: int) -> Array:
	var pool := CARDS.duplicate()
	pool.shuffle()
	return pool.slice(0, min(n, pool.size()))

## Apply a card's effect to the live PC + EXP system. Pure dispatch — no UI.
static func apply(card_id: String, player: Node, exp_system: Node) -> void:
	match card_id:
		"razor_edge":
			if player and player.data:
				player.data.slash_width *= 1.3
		"quickstep":
			if player and player.data:
				player.data.move_speed *= 1.2
		"iron_will":
			var hp: Node = player.get_node_or_null("HealthComponent")
			if hp != null:
				hp.max_hp += 1
				hp.hp += 1
		"wind_walker":
			if player and player.data:
				player.data.evade_cooldown *= 0.75
		"greed":
			if exp_system != null:
				exp_system.gain_multiplier *= 1.25
		"reach":
			if player and player.data:
				player.data.max_slash_range *= 1.2
		"vigilance":
			if player and player.data:
				player.data.slash_cooldown *= 0.7
		_:
			push_warning("UpgradeSystem: unknown card id '%s'" % card_id)
