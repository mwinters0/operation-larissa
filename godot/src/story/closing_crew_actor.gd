class_name ClosingCrewActor
extends RefCounted
## One sailor of the Expert closing's deck shot: a tiny interpreter for the sailor's program.
## Original: `ExpertClosingCrewStep` (0x41ceb7, CLOSING.C), called once per 18-tick step for each of the six sailors,
## with the program taken from `ExpertCraneTable` (0x4415a4) and the picture drawn by `ExpertClosingDrawCrewPicture`
## (0x41ce8f). The table's name is misleading: it is not a crane script, it holds six walk / wave programs.
##
## Teaches: a data-driven animation. The behaviour of six characters is a few hundred numbers (`data/closing_crew.tres`)
## and one `step()` that reads them: the same idea as the creatures' scripts (`FoeVM`), only much smaller.
##
## A program is a list of records `[op, item, mirror, delay]`. `step()` runs one animation step:
##   * while the current record's `delay` has run out, the program moves on to the next record;
##   * the record's op then acts: WAIT draws nothing, DRAW draws, LEFT / RIGHT / UP / DOWN move the sailor and draw,
##     END draws the previous record's picture once more and restarts the program (the position is NOT reset);
##   * a record lasts `delay` steps, and a move op moves once in every one of them.
## The original erases every sailor before each step, so a step that draws nothing leaves the sailor invisible.

enum Op { WAIT = -8, DOWN = -7, UP = -6, LEFT = -5, RIGHT = -4, END = -3, DRAW = -2 }

const RECORD_SIZE := 4
const STEP_X := 4                      # a LEFT / RIGHT record moves this many pixels per step
const STEP_Y := 10                     # an UP / DOWN record moves this many pixels per step

## Position in window pixels (the top-left corner of the 28 x 26 picture).
var x: int
var y: int
## What the last `step()` drew: `visible` is false for a step in which nothing was drawn.
var visible: bool = false
var picture: int = 0
var mirrored: bool = false

var _program: PackedInt32Array
var _first_picture: int
var _record: int = -1                  # the original's ExpertClosingCrewScriptPos / 4 (-1 = not started)
var _delay: int = 0                    # the original's ExpertClosingCrewDelay


## Sailor number `index` (0-5) of `crew`.
func _init(crew: ClosingCrewScripts, index: int) -> void:
	_program = crew.scripts[index]
	_first_picture = crew.first_picture
	x = crew.start_x[index]
	y = crew.start_y[index]


## Number of records of the program (the end op included).
func record_count() -> int:
	return _program.size() / RECORD_SIZE


## One animation step (one call of `ExpertClosingCrewStep`).
func step() -> void:
	var previous := maxi(_record, 0)
	if _delay < 1:
		_record += 1
	var base := _record * RECORD_SIZE
	visible = false
	match _program[base]:
		Op.WAIT:
			if _delay == 0:
				_delay = _program[base + 3]
		Op.LEFT, Op.RIGHT, Op.UP, Op.DOWN, Op.DRAW:
			match _program[base]:
				Op.LEFT:
					x -= STEP_X
				Op.RIGHT:
					x += STEP_X
				Op.UP:
					y -= STEP_Y
				Op.DOWN:
					y += STEP_Y
			_draw(base)
			if _delay == 0:
				_delay = _program[base + 3]
		Op.END:
			_draw(previous * RECORD_SIZE)
			_record = -1
			_delay = 0
	if _delay > 0:
		_delay -= 1


func _draw(base: int) -> void:
	visible = true
	picture = _first_picture + _program[base + 1]
	mirrored = _program[base + 2] != 0
