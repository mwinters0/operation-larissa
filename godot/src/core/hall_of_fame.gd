class_name HallOfFame
extends RefCounted
## The Hall of Fame: the last nine players who finished a game (DESIGN 6, `HALLFAME.DAT`).
##
## Teaches: a fixed-size list with a "shift out" rule instead of sorting or scoring. A new entry
## goes into the first empty row; when all nine rows are taken the oldest entry drops out at the
## top and the newcomer takes the last row. Pure logic, so `tests/engine/test_hall_of_fame.gd` needs no scene.

const ROWS := 9

var entries: Array[HallEntry] = []


## Adds `entry` following the shift-out rule.
func add(entry: HallEntry) -> void:
	if entries.size() >= ROWS:
		entries.pop_front()
	entries.append(entry)


func to_array() -> Array:
	var rows: Array = []
	for entry in entries:
		rows.append(entry.to_dict())
	return rows


## Replaces the entries with those of `rows` (an Array of Dictionaries; bad rows are skipped, extra ones ignored).
func from_array(rows: Array) -> void:
	entries.clear()
	for row in rows:
		if row is Dictionary and entries.size() < ROWS:
			var entry := HallEntry.from_dict(row)
			if entry != null:
				entries.append(entry)
