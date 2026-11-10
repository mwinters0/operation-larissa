class_name Ground
extends RefCounted
## The test sectors of batch A ("ground": tiles, walls, currents, screens, sector data and its editors and checks), as the tests of that batch name them.
## They are in the dev pack (`tools/dev_pack/test_sectors/batch_a.py` writes them; its docstring tells what each one holds), so they are there with or without
## the legacy pack. Every number below is dev's own and arbitrary.
##
## Teaches: one place for the numbers a family of tests shares with the generator that made the data, so that a change to the data is a change in two files
## that sit side by side, not in forty literals.

## The sector the editors and the checkers work on: twelve screens in a row, eleven pieces (piece 0 is the canister), six creatures (creature 5 starts dormant and hidden, 2 hidden, 4 mirrored), math triggers, ledges, every current on screen 7, and on screen 6 (the midpoint) one of everything the screen editor shows: two middle decorations, a front one, an animated one, a current, rock, a piece (5) and a trigger.
const MAIN := 100
## Rock at chosen heights on screen 1 (see `ledge_sector` in batch_a.py): the sub's wall box and a piece behind a rock.
const LEDGE := 101
## Twelve screens in four columns and three rows, every link two-way.
const MAP := 102
## A sector whose finale starts on screen 2; creature 0 is the treasure and no piece is asked for.
const FINALE := 103
## The row of twelve with tables that do not lead back and a ring (`tangle_sector`): for the models of the maps, not a sector to play.
const TANGLE := 104
## What the sector editors add to and take from: seven pieces, five creatures, a script that names creatures 3 and 1 (`edit_sector`).
const EDIT := 105

## What `MAIN` holds: pieces as (screen, window x, window y), piece 0 the canister.
const MAIN_PIECES: Array[Vector3i] = [Vector3i(9, 480, 232), Vector3i(0, 480, 200), Vector3i(2, 300, 100), Vector3i(3, 320, 180), Vector3i(4, 256, 240),
		Vector3i(6, 448, 160), Vector3i(9, 400, 150), Vector3i(7, 100, 240), Vector3i(8, 160, 230), Vector3i(10, 300, 200), Vector3i(1, 350, 120)]
## The screens the six creatures of `MAIN` start on (creature 5 sleeps, hidden, on screen 1 beside the awake creature 3).
const MAIN_CREATURE_SCREENS: Array[int] = [4, 7, 10, 1, 2, 1]
const MAIN_DORMANT := 5
## Creature 2 starts hidden but awake, creature 4 starts mirrored.
const MAIN_HIDDEN := 2
const MAIN_MIRRORED := 4
## The screen with the animated decoration, its list of deco slots (one tick each), and where it starts in the list.
const ANIM_SCREEN := 6
const ANIM_FRAMES: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1]
const ANIM_START := 2
## The screen with the eight currents of both strengths: tile column 3 is strength 0, column 4 strength 7, row 2 + 2 * direction.
const CURRENT_SCREEN := 7


## `MAIN` as dev's files hold it.
static func main() -> SectorData:
	return DevPack.sector(MAIN)


## A copy that a test may change: the loaded resources are shared and cached, and `duplicate_deep` copies what the .tres holds inside itself (pieces,
## creatures, the animated decorations of a screen), not the screen files or the creature script, which a test replaces when it changes them.
static func copy_of(index: int = MAIN) -> SectorData:
	return DevPack.sector(index).duplicate_deep() as SectorData


## The sectors of the dev pack that make a game of their own or that are test sectors of this batch and fine as they are: what an "every sector of the
## chain" loop may expect to pass the playability checks. (The sectors that other batches add are not in the list.)
static func clean_sectors() -> Array[int]:
	var found: Array[int] = []
	for index in DevPack.TOUR_SECTORS:
		found.append(index)
	found.append(DevPack.TOUR_FINALE)
	found.append_array([MAIN, LEDGE, MAP, FINALE, EDIT])
	return found
