class_name StoryLayout
extends Resource
## Where the opening cartoon puts its pictures: the original's table of 68 points (NEP.DLL resource 10012,
## decoded in `OpeningSequence`, OPENING.C). Filled by the importer (`step_console.py`), so no position is typed
## into a script.
##
## Teaches: "data, not code" once more, and a named index into a table. The numbers are window pixels of the
## 640 x 400 screen; a few (the ship) start left of the screen on purpose and are moved by the animation.

# --- the news cartoon: a radar map of the Pacific, a control room, a falling capsule ---
const MAP := 0                       # the radar map picture (1000)
const CONSOLE_LEFT := 1              # the control-room console (1001) and its mirror image
const CONSOLE_RIGHT := 2
const ALARM_LIGHTS: Array[int] = [3, 4, 5]
const STATUS_LIGHTS: Array[int] = [6, 7, 8, 9, 10, 11]            # 16 x 24 pictures (1010-1012)
const PANEL_LIGHTS: Array[int] = [12, 13, 14, 15, 16, 17, 18, 19]  # 24 x 16 pictures (1013-1015)
const TELETYPE := 20                 # the box the bulletins are typed into (350 x 120)
const CRASH_SITE := 21               # where the radar ring pulses
const CREW: Array[int] = [22, 23, 24, 25, 26]
const CAPSULE_TRAIL_FIRST := 27      # 21 points: the capsule's way down, one dot (1002) at a time
const CAPSULE_TRAIL_LAST := 47

# --- the title scene: the surface ship launches the mini-sub, then the title is revealed ---
const SHIP := 48                     # the ship starts at x = -400 and sails to the right
const SHIP_RADAR := 49
const SHIP_HOOK := 50
const SHIP_SUB := 51                 # the mini-sub hanging from the crane
const SHIP_BOW_SPRAY := 52
const WAVES_FRONT := 53              # the strip of waves drawn over the ship's hull
const SPLASH := 54
const SKY := 55
const SEA := 56
const CLOUD_LEFT := 57
const CLOUD_RIGHT := 58
const PRESENTS := 59                 # "The Learning Company Presents"
const OPERATION := 60
const NEPTUNE := 61
const COPYRIGHT := 62

@export var points: PackedVector2Array = PackedVector2Array()


## The point with this index (one of the constants above).
func at(index: int) -> Vector2:
	return points[index]
