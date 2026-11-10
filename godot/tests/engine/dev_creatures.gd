class_name DevCreatures
extends RefCounted
## The dev pack's creature test sectors (batch B of I7: `tools/dev_pack/test_sectors/batch_b.py`), as the engine tests of creatures, combat and the skins
## know them. A TEST helper: the numbers here are dev's own and say where each creature of those sectors is and what its script does; if
## the generator changes one, change it here.
##
## Teaches: one place that says what a test place holds, so a test says `DevCreatures.POST` and not "creature 0 of sector 120".

## --- sector 120, the arena (zone 0): a creature for every property the creature tests look at ---------------------------------
const ARENA := 120
## The post: a hostile clam (damage 1) on screen 0 that never moves; its ink script makes it a harmless cloud for `INK_TICKS` ticks.
const POST := 0
## The swimmer: hostile, on screen 0, swims ten steps right and ten left (4 px a tick); inked like the post.
const SWIMMER := 1
## The chomper: harmless, on screen 0; plays the sound `clam_chomp` once per round of `CHOMP_ROUND` ticks.
const CHOMPER := 2
## The bell and the hopper (screen 2): a jellyfish bell that changes picture every other tick, and its loose tentacle tip, which hops 28, 8, 32 and 12 px
## with a rest of two ticks between the hops.
const BELL := 3
const HOPPER := 4
## The sleeper: dormant and hidden, on screen 3; it creeps right as soon as it runs. The waker (screen 5) wakes it in its 31st tick on that screen.
const SLEEPER := 5
const WAKER := 10
const WAKER_SCREEN := 5
const WAKER_TICKS := 31
## The runner: like the swimmer, on screen 6 (a creature of a screen that is not shown).
const RUNNER := 6
## The mirror: stands still on screen 4, drawn mirrored (picture ray_swim_0). The glider (screen 4) swims 12 steps right, rests, and swims 12 left.
const MIRROR := 7
const GLIDER := 8
const MIRROR_SCREEN := 4
## Zoom: a friendly dolphin (damage -4) on screen 7; touched, it puts itself to sleep, plays `oxygen_refill` and hides.
const ZOOM := 9
const ZOOM_SCREEN := 7
const CREATURES := 11
## The pieces of the arena: 0 is the canister (screen 3); 1 and 2 lie on screen 8 (taking one leaves the other).
const PIECE_SCREEN := 8
const PIECES: Array[int] = [1, 2]
const INK_TICKS := 60
const CHOMP_ROUND := 20
## The screens the arena's creatures are on.
const POST_SCREEN := 0
const BELL_SCREEN := 2
const SLEEPER_SCREEN := 3
const RUNNER_SCREEN := 6

## --- sector 121, the closing (zone 0): the treasure (foe 0, screen 4) raises flag 15 when touched; the ending starts on screen 10 ---------
const CLOSING := 121
const TREASURE := 0
const GUARD := 1
const CLOSING_SCREEN := 10

## --- sector 122, the fish (zone 0): creatures of the kinds the "creatures" skin replaces ---------------------------------------------
const FISH := 122
const CLAM := 0
const PUFFERS: Array[int] = [1, 2, 3]            # on screens 0, 6 and 9
const RAINBOW_FISH: Array[int] = [4, 5]          # on screens 3 and 5

## The sector a creature test starts from when it needs "some sector with creatures on several screens".
const DEFAULT := ARENA


## The arena's creature `index` as a creature of a world (`world.original.foes[index]`).
static func foe(world: SectorWorld, index: int) -> Foe:
	return world.original.foes[index]
