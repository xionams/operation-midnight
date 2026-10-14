extends Object
class_name DamageTypes

## What a weapon fires, and how well each kind of ordnance performs
## against each armor class.
##
## The whole counter system is this one table. It lives here as data
## rather than as checks inside unit scripts, so rebalancing counters is
## editing numbers in one place and every weapon - unit or turret,
## player or AI - obeys it automatically.
##
##   SMALL_ARMS   rifles and machine guns: excellent vs infantry,
##                useless against real armour, slow but real work
##                against structures (a rifle squad CAN raze a building -
##                it just takes a while)
##   ANTI_ARMOR   shaped charges and missiles: poor vs infantry,
##                devastating vs heavy armour
##   CANNON       tank guns: strong across vehicles, inefficient against
##                dispersed infantry
##   EXPLOSIVE    artillery: strong vs infantry groups and structures,
##                less effective against heavy plate

##   TORPEDO      submarine torpedoes: nothing on land, heavy against
##                hulls and anything built on the water
##   FLAK         anti-air guns: nearly useless against the ground, which
##                is what makes an air force worth answering deliberately
##                rather than with whatever is nearby

enum Type { SMALL_ARMS, ANTI_ARMOR, CANNON, EXPLOSIVE, TORPEDO, FLAK }

## [INFANTRY, LIGHT, MEDIUM, HEAVY, STRUCTURE, AIR]
##
## Every row carries an AIR column even though most of them read near
## zero, because `multiplier()` returns 1.0 for an armor index past the
## end of its row - so a short row would have quietly let every weapon in
## the game do FULL damage to aircraft.
const TABLE: Dictionary = {
	Type.SMALL_ARMS: [1.00, 0.55, 0.20, 0.10, 0.30, 0.25],
	Type.ANTI_ARMOR: [0.35, 0.90, 1.10, 1.30, 0.70, 0.15],
	Type.CANNON:     [0.40, 1.00, 1.00, 0.90, 0.85, 0.20],
	Type.EXPLOSIVE:  [1.20, 0.85, 0.75, 0.55, 1.30, 0.10],
	Type.TORPEDO:    [0.00, 1.10, 1.25, 1.30, 1.10, 0.00],
	Type.FLAK:       [0.25, 0.30, 0.15, 0.10, 0.15, 1.35],
}

static func type_name(damage: Type) -> String:
	return Type.keys()[damage]

static func multiplier(damage: Type, armor: int) -> float:
	var row: Array = TABLE.get(damage, [])
	if armor < 0 or armor >= row.size():
		return 1.0
	return row[armor]
