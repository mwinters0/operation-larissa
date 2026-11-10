class_name CreatureSpecies
extends RefCounted
## Which creatures this skin draws itself, and how it tells them apart: by their PICTURES. The skin API says a creature's `picture` is a
## slot in the zone's list of creature pictures, and the registry has a name for every slot (`rainbow_fish_swim_0` is slot 35
## in zone 0), so "this is a rainbow fish" means "its picture is one of the rainbow fish's". (A creature is not a species in the rules:
## `FoeVM` has a script, a picture and a place, and nothing else.)
##
## Teaches: names instead of numbers in a skin (the slot of a picture is different in every zone, its name is not), and the registry
## scoping at work: the same slot number is another creature in another zone, so a name that has no slot in this zone answers -1 and the
## creature is left to the original.

const RAINBOW_FISH := &"rainbow_fish"
const PUFFER := &"puffer"

## Species -> the names of the pictures that make a creature of that species (what it shows while it is itself).
const PICTURES := {
	RAINBOW_FISH: ["rainbow_fish_swim_0", "rainbow_fish_swim_1", "rainbow_fish_spit_0", "rainbow_fish_spit_1"],
	PUFFER: ["puffer_swim_0", "puffer_swim_1", "puffer_swell", "puffer_puffed_0", "puffer_puffed_1"],
}
## The pictures of the ink cloud every creature turns into when a pellet hits it.
const INK_PICTURES := ["ink_burst_0", "ink_burst_1", "ink_burst_2", "ink_burst_3", "ink_burst_4", "ink_burst_5", "ink_burst_6"]


## The species of a creature that shows picture `slot` in `zone`, or &"" when this skin leaves it to the original.
static func of_picture(zone: int, slot: int) -> StringName:
	for species: StringName in PICTURES:
		if slot_list(zone, PICTURES[species]).has(slot):
			return species
	return &""


## The slots of the pictures called `names` in `zone` (a name with no slot in this zone is left out).
static func slot_list(zone: int, names: Array) -> Array[int]:
	var slots: Array[int] = []
	for picture_name: String in names:
		var slot := NameRegistry.original().index_of(&"frame", picture_name, zone)
		if slot >= 0:
			slots.append(slot)
	return slots


## The slot of the picture `picture_name` in `zone`, or -1.
static func slot_of(zone: int, picture_name: String) -> int:
	return NameRegistry.original().index_of(&"frame", picture_name, zone)
