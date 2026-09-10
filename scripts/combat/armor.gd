extends Object
class_name Armor

## Armor classes and the damage multipliers weapons apply against them.
## This is the backbone of unit counters: a weapon is not simply "strong"
## or "weak", it is strong against some armor and poor against others, so
## every unit has something it beats and something that beats it.
##
## INFANTRY  soft targets on foot — shredded by machine guns, crushable
## LIGHT     wheeled/light vehicles — scouts, harvesters
## HEAVY     armoured vehicles — assault vehicles
## BUILDING  structures — resistant to small arms, vulnerable to shells

enum Type { INFANTRY, LIGHT, HEAVY, BUILDING }

static func type_name(armor: Type) -> String:
	return Type.keys()[armor]
