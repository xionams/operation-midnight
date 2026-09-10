extends Object
class_name CommandTypes

## The vocabulary of orders a unit can be given.
##
## Everything the player does resolves to one of these before it reaches
## a unit, so adding a new unit role never means inventing a new input
## path: it means handling one more entry here. Not all are implemented
## yet - GARRISON is reserved - but the architecture carries them so the
## contextual command resolver has somewhere to point.

enum Type {
	MOVE,        ## Go there.
	ATTACK,      ## Kill that specific thing.
	ATTACK_MOVE, ## Advance, engaging whatever is met on the way.
	STOP,        ## Cancel everything; hold position.
	GUARD,       ## Hold here, engage what comes close.
	HARVEST,     ## Work that resource field.
	RETURN,      ## Take cargo to a refinery.
	CAPTURE,     ## Engineer/Spy: enter that structure.
	GARRISON,    ## Reserved: occupy a building.
}

static func type_name(t: Type) -> String:
	return Type.keys()[t]

## Orders that mean "I chose this destination", as opposed to reactions a
## unit takes on its own. Used to decide whether a unit is idle enough to
## acquire targets by itself.
static func is_player_directed(t: Type) -> bool:
	return t != Type.GUARD and t != Type.STOP
