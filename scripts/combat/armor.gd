extends Object
class_name Armor

## Armor classes. What a thing counts as when something shoots at it.
##
## INFANTRY   soft targets on foot - shredded by small arms, crushable
## LIGHT      unarmoured vehicles - scouts, harvesters
## MEDIUM     armoured but not a main tank - assault vehicles, artillery
## HEAVY      main battle tanks
## STRUCTURE  buildings, walls and defences
## AIR        aircraft - untouchable by anything without a flak gun, and
##            fragile once something can reach them

enum Type { INFANTRY, LIGHT, MEDIUM, HEAVY, STRUCTURE, AIR }

static func type_name(armor: Type) -> String:
	return Type.keys()[armor]
