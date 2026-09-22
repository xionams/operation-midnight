extends ProducerBuilding
class_name Refinery

## Converts harvested cargo into credits and acts as the harvester
## drop-off point. It also trains Harvesters, so a player who loses their
## whole harvest fleet can rebuild it from the refinery itself rather
## than being economically dead.

const FREE_HARVESTER: UnitStats = preload("res://config/units/harvester.tres")

func _ready() -> void:
	super._ready()
	var first: bool = not GameState.has_refinery(is_player_faction)
	GameState.register_refinery(self, is_player_faction)
	## The first refinery arrives with a harvester. Paying 2000 for a
	## building that then does nothing until a further 1200 is spent
	## stalls the opening badly; every later refinery is bought bare.
	## Not when rebuilding a saved match: that harvester already exists in
	## the save, and handing out another one duplicates it on every load.
	if first and not GameState.restoring:
		_spawn_free_harvester.call_deferred()

func _spawn_free_harvester() -> void:
	if FREE_HARVESTER.unit_scene == null:
		return
	var harvester = FREE_HARVESTER.unit_scene.instantiate()
	harvester.stats = FREE_HARVESTER
	harvester.is_player_faction = is_player_faction
	get_parent().add_child(harvester)
	harvester.global_position = global_position + queue.spawn_offset
	EventBus.unit_spawned.emit(harvester)

func _on_died() -> void:
	GameState.unregister_refinery(self, is_player_faction)
	super._on_died()

func _on_faction_changing() -> void:
	## Leaves whichever side's list it is currently on, before the flip.
	GameState.unregister_refinery(self, is_player_faction)

func _on_faction_changed() -> void:
	GameState.register_refinery(self, is_player_faction)

func receive_resources(amount: float) -> void:
	if amount <= 0.0:
		return
	var payout: int = int(round(amount))
	GameState.add_credits_for(is_player_faction, payout)
	if is_player_faction:
		MatchStats.record_harvest(payout)
