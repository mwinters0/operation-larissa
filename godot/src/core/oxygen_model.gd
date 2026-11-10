class_name OxygenModel
extends RefCounted
## The player's air supply: tanks and oxygen, with the rules of the original's
## `UpdateOxygen(d)` (DESIGN 3.4).
##
## Teaches: keeping game rules in a plain `RefCounted` object with no nodes and no
## signals, so they can be unit tested row by row. `GameState` (an autoload) owns
## one of these and turns its results into signals for the HUD.
##
## `oxygen` is the air in the tank you are breathing from (up to `max_oxygen`, 4 in the original); `tanks` counts the
## SPARE tanks (up to `max_tanks`, 6). A new player has `refill_tanks` (2) spare tanks and a full tank of oxygen. The three numbers are
## the run's `Tuning` (`air` section), given to the model when the run makes it.

## What `update` returns when the air runs out. The original's numbers; the caller
## only needs to know "lost a tank" (-1, -3) versus "game over" (-2).
const OK := 0
const OUT_WITH_SPARE_TANKS := -1    # oxygen gone, more than one spare tank
const GAME_OVER := -2               # oxygen gone and no spare tank
const OUT_WITH_LAST_TANK := -3      # oxygen gone, exactly one spare tank

## The most air in the tank in use and the most spare tanks.
var max_oxygen: int
var max_tanks: int
## The spare tanks a refill gives at least (+2, +3), and a new player's.
var refill_tanks: int
var tanks: int
var oxygen: int


func _init(air: Tuning) -> void:
	max_oxygen = air.max_oxygen
	max_tanks = air.max_tanks
	refill_tanks = air.refill_tanks
	tanks = refill_tanks
	oxygen = max_oxygen


## Applies `d` and returns OK or one of the "air ran out" codes.
##   d < 0   breathing / damage: oxygen drops by |d|; at 0 the result says what happens next
##   d = +1  Zoom's tank: a full tank of oxygen, and if already full, one more spare tank (up to `max_tanks`)
##   d = +2  at least `refill_tanks` spare tanks
##   d = +3  supply station / new sector / game restart: `refill_tanks` spare tanks (at least), full oxygen
##   d = +4  respawn after losing a tank: full oxygen, one spare tank less
func update(d: int) -> int:
	if d < 0:
		oxygen += d
		if oxygen <= 0:
			oxygen = 0
			if tanks > 1:
				return OUT_WITH_SPARE_TANKS
			if tanks == 1:
				return OUT_WITH_LAST_TANK
			return GAME_OVER
		return OK
	match d:
		1:
			if oxygen >= max_oxygen:
				tanks = mini(tanks + 1, max_tanks)
			else:
				oxygen = max_oxygen
		2:
			tanks = maxi(tanks, refill_tanks)
		3:
			tanks = maxi(tanks, refill_tanks)
			oxygen = max_oxygen
		4:
			oxygen = max_oxygen
			tanks = maxi(tanks - 1, 0)
	return OK


## True for the two "lost a tank, play on" codes.
static func is_tank_lost(code: int) -> bool:
	return code == OUT_WITH_SPARE_TANKS or code == OUT_WITH_LAST_TANK
