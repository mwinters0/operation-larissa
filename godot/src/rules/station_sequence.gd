class_name StationSequence
extends RefCounted
## One trip at a supply station, counted in game ticks by the rules: the sub drives out of the start station (LAUNCH), the sub
## drives into the end station (DOCK), or the balloon takes the pieces up to the surface ship (BALLOON). The view is told "you
## have `ticks` ticks" and shows each tick of it; it does not decide when the trip is over - `SimWorld.tick` does, and play goes on
## the tick after.
##
## Teaches: a presentation step that holds up play, written down as data and arithmetic. The sequence knows nothing of nodes, tweens
## or animations: it is a counter with a few questions you can ask it ("where is the sub after 7 ticks?", "which picture does the
## door show?"). A skin may draw the door and the balloon any way it likes, a test can run the whole trip with `advance()`, and a
## blank presenter that draws nothing takes exactly as long, because the length is in the data (`station.*` of
## `data/rules/durations.json`, read through `Durations`) and not in an animation or a constant. A pack that wants a longer dock
## changes a number there; the numbers below are the original's (the legacy pack).
##
## THE LAUNCH (`ExitSupplyStation` 0x4328b0), in game ticks of 6/73 s (DESIGN 3.7), after `elapsed` ticks:
##   0 the door shows picture 3      1 picture 4      2 the door is open (no picture)
##   3.. the sub drives 4 px per tick (96 px out of the left station, 100 px into the right one)
##   then the door closes: picture 4, picture 3 (with the door sound, one tick after it starts to close), picture 2 (closed)
##   and one more tick before play goes on. That is 3 + drive + 3 ticks: 30 for the launch, 31 for the dock.
## THE BALLOON rises 4 px per tick from its window until it has left the playfield: 44 ticks.
##
## Positions are integer window pixels of the original (the sub's `SubX`, the balloon's top y); the playfield starts at (16, 32).

enum Kind { LAUNCH, DOCK, BALLOON }

## The door's pictures (the 7 of the station bundle: 2 closed, 3 and 4 opening or closing).
const DOOR_CLOSED := 2
const DOOR_OPEN := -1              # (no picture: the doorway is empty)

## The sub's picture is this high (window y) while it drives (where the station's door is drawn, not a length).
const DRIVE_Y := 202

## Which trip this is.
var kind: Kind
## How many game ticks the whole trip lasts (the view is told this).
var ticks: int
## The door's ticks before the sub drives and after it has stopped (a drive: `station.launch` / `station.dock`).
var opening_ticks: int = 0
var closing_ticks: int = 0
## How far the sub's picture or the balloon moves in one tick (window pixels).
var pixels_per_tick: int = 4
## The sub's picture starts and ends here (window x; a drive).
var from_x: int = 0
var to_x: int = 0
## The balloon: its x, where its top starts (the window of the surface ship) and where it is gone (64 px above the playfield) (window y).
var balloon_x: int = 0
var balloon_from_y: int = 0
var balloon_to_y: int = 0
## How many have gone by. The view shows the state after this many.
var elapsed: int = 0
## The number of the game tick (`SimWorld.tick_number`) in which the first of the trip's ticks runs. Set by `SimWorld` when the trip
## starts; the trip's last tick is tick `started_tick + ticks - 1`. A skin that watches `ticked` can tell by it how long ago the trip began.
var started_tick: int = 0


static func launch() -> StationSequence:
	return StationSequence.new(Kind.LAUNCH)


static func dock() -> StationSequence:
	return StationSequence.new(Kind.DOCK)


static func balloon() -> StationSequence:
	return StationSequence.new(Kind.BALLOON)


## The trip as the data (`Durations`, `station.<launch|dock|balloon>`) lays it out; the numbers are copied, so a trip does not change
## when the data does.
func _init(trip: Kind) -> void:
	kind = trip
	var section: String = "station." + ["launch", "dock", "balloon"][trip] + "."
	pixels_per_tick = maxi(Durations.at(section + "pixels_per_tick"), 1)
	if is_drive():
		opening_ticks = maxi(Durations.at(section + "opening_ticks"), 0)
		closing_ticks = maxi(Durations.at(section + "closing_ticks"), 0)
		from_x = Durations.at(section + "from_x")
		to_x = Durations.at(section + "to_x")
		ticks = opening_ticks + drive_ticks() + closing_ticks
	else:
		balloon_x = Durations.at(section + "x")
		balloon_from_y = Durations.at(section + "from_y")
		balloon_to_y = Durations.at(section + "to_y")
		ticks = maxi(ceili(float(balloon_from_y - balloon_to_y) / pixels_per_tick), 0)


## A copy of this trip with every number of it as it is now (its own lengths and places, not the data's: the data may have changed
## since the trip began). `SimView.SequenceState` asks its questions of such a copy.
func copy() -> StationSequence:
	var twin := StationSequence.new(kind)
	for property in get_script().get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			twin.set(property["name"], get(property["name"]))
	return twin


## True for the launch and the dock: a door and a sub that drives.
func is_drive() -> bool:
	return kind != Kind.BALLOON


## How many ticks the sub drives (24 for the launch, 25 for the dock): 4 px per tick, the last step may be shorter.
func drive_ticks() -> int:
	return maxi(ceili(float(to_x - from_x) / pixels_per_tick), 0)


func drive_from_x() -> int:
	return from_x


func drive_to_x() -> int:
	return to_x


func is_done() -> bool:
	return elapsed >= ticks


## One game tick has gone by. Returns true when that was the last one.
func advance() -> bool:
	elapsed = mini(elapsed + 1, ticks)
	return is_done()


## The sub's picture x (window pixels) after `at` ticks: still for the opening, then 4 px per tick, still again at the end.
func sub_x(at: int = elapsed) -> int:
	var driven := clampi(at - opening_ticks, 0, drive_ticks())
	return mini(from_x + driven * pixels_per_tick, to_x)


## The door's picture after `at` ticks: DOOR_OPEN, DOOR_CLOSED or the 3 / 4 of its moving. Opening: picture 3, picture 4, then open;
## closing: picture 4, picture 3, then closed. Longer openings and closings (data) hold the last of those, shorter ones cut it off.
func door_picture(at: int = elapsed) -> int:
	var close_start := opening_ticks + drive_ticks()
	if at < opening_ticks:
		return [3, 4][at] if at < 2 else DOOR_OPEN
	if at < close_start:
		return DOOR_OPEN
	if at < close_start + closing_ticks:
		return [4, 3][at - close_start] if at - close_start < 2 else DOOR_CLOSED
	return DOOR_CLOSED


## The tick after which the door sound plays: one after the door starts to close, with its picture 3 (the last tick at the latest).
func door_sound_tick() -> int:
	return mini(opening_ticks + drive_ticks() + 1, ticks)


## The balloon's top y (window pixels) after `at` ticks.
func balloon_y(at: int = elapsed) -> int:
	return balloon_from_y - clampi(at, 0, ticks) * pixels_per_tick
