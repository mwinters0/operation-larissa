@tool
class_name FoeData
extends Resource
## One creature record (the 34-byte struct of the original game).
##
## Teaches: describing a *script-driven* entity with plain data. The behaviour
## itself lives in SectorData.foe_script (a `.foe` text file, see
## docs/create/FOE_SCRIPTING.md) and is run by FoeVM. The record names its three entry points by LABEL: the stored
## data says "start at foe3_start", not "start at byte 1170", so a designer can edit
## the script without breaking the record. `pc`, `script_hit` and `script_ink` are the
## same entry points as numbers (offsets into the ORIGINAL foe buffer); SectorData
## fills them in when it compiles the script, so nothing stores them twice.
##
## Like `ScreenData` and the sector header, the record can be rebuilt byte for byte: `encode()` gives the original's
## 34 bytes (tests/legacy/test_foe_record_fidelity.gd compares their hashes with tests/fixtures/foe_records.json). THE RECORD
## (DESIGN 3.5), offsets in bytes:
##   0x00 u8 dormant   0x01 u8 hidden   0x02 u8 screen   0x03 u16 x / 2   0x05 u16 y / 2
##   0x07 u8 frame     0x08 u8 flip     0x09 u8 frame min   0x0A u8 frame max
##   0x0B u16 hit script   0x0D u16 ink script   0x0F i8 damage   0x10 u16 start pc
##   0x12..0x21 the run-time state the game keeps while a creature is interrupted (see `runtime_state`)
## Three of the fields are stored in a more convenient form than the file's: positions are in pixels (the file
## halves them), flags are booleans, and the three entry points are labels. `encode()` undoes each of those exactly,
## and `problems()` refuses the values that have no such form (an odd position, a frame of 300, ...).
##
## The pictures are shown BY NAME in the Inspector (`_validate_property`): `frame`, `frame_min` and `frame_max` are still the
## original's numbers in the file and in `encode()`, but the Inspector offers a drop-down of the zone's picture names
## (`eel_swim_0`, `puffer_swell`) with each number behind it, so nobody has to know that slot 40 is the eel.
## Teaches: `_validate_property`, which changes how a property is SHOWN (here: an enum hint on an `int`) without changing
## what is stored.

## Size of the record in the original's foe buffer and where its run-time state starts.
const RECORD_SIZE := 34
const RUNTIME_STATE_AT := 0x12
const RUNTIME_STATE_SIZE := RECORD_SIZE - RUNTIME_STATE_AT
## The properties that hold a picture number, and the bit that mirrors a picture in the numbers a script uses.
const PICTURE_PROPERTIES: Array[String] = ["frame", "frame_min", "frame_max"]
const MIRRORED := 0x80

@export var dormant: bool = false
@export var hidden: bool = false
## Screen the creature starts on (0-11).
@export var screen: int = 0
## Start position in window pixels (the playfield starts at (16, 32)).
@export var pos: Vector2i = Vector2i.ZERO
## Index into the zone's foe SpriteFrames ("foes_zone{z}.tres"); the Inspector shows its `frame` name.
@export var frame: int = 0
@export var flip: bool = false
@export var frame_min: int = 0
@export var frame_max: int = 0
## Oxygen lost on contact. Negative = friendly (Zoom the dolphin).
@export var damage: int = 0
## The three entry points, as labels of SectorData.foe_script: where the
## creature starts, what runs when the sub touches it, what runs when an ink pellet
## hits it. Several creatures may use the same label. An unknown label is a
## compile error (SectorData.compile names the creature and the field).
@export var start_label: String = ""
@export var hit_label: String = ""
@export var ink_label: String = ""
## Bytes 0x12..0x21 of the record: the saved pc, the loop counters and the saved x / y / frame / flip that the game
## fills in while a creature is interrupted (DESIGN 3.5). The data starts out with all of them zero, in every one
## of the 640 original creatures, so this is EMPTY (meaning 16 zero bytes) and the 640 resources store nothing;
## FoeVM does not read it either. It exists so that a record that does carry bytes there can be kept and rebuilt
## exactly. Empty or exactly RUNTIME_STATE_SIZE bytes. Not something to edit.
@export var runtime_state: PackedByteArray = PackedByteArray()

# --- the Inspector: pictures by name -------------------------------------------------------------------------------

## `frame`, `frame_min` and `frame_max` get a drop-down of the creature pictures of the sector's zone, each entry a `frame`
## name with its slot number as the value, so the stored value stays the original's number. The numbers a creature may
## hold that the list does not offer (an unnamed slot, or a mirrored picture: bit 7, number + 128, written `mirrored` in a
## script) are added to it as the current choice, so opening a record never changes it.
func _validate_property(property: Dictionary) -> void:
	if property.name in PICTURE_PROPERTIES:
		property.type = TYPE_INT
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = picture_choices(_zone(), int(get(property.name)))


## The drop-down text ("name:number,name:number") of the pictures of `zone` (`NameRegistry.NO_SCOPE`: only the common
## ones), with `current` added when it is none of them.
static func picture_choices(zone: int, current: int) -> String:
	var registry := NameRegistry.original()
	var choices := registry.entries(&"frame", zone)
	var parts: Array[String] = []
	for picture_name: String in choices:
		parts.append("%s:%d" % [picture_name, choices[picture_name]])
	if not choices.values().has(current):
		var label := registry.name_of(&"frame", current & 0x7F, zone)
		if label.is_empty():
			label = str(current)
		elif current >= MIRRORED:
			label += " " + FoeOps.MIRROR_WORD
		parts.append("%s:%d" % [label, current])
	return ",".join(parts)


## The zone of the creature set this record's pictures belong to: the zone of the sector file that holds the record
## (a record inside `res://packs/legacy/data/sectors/sector_03/sector_03.tres` has the path `...sector_03.tres::Foe_5`), or no zone.
func _zone() -> int:
	var sector_path := resource_path.get_slice("::", 0)
	if resource_path.contains("::") and ResourceLoader.has_cached(sector_path):
		var sector := load(sector_path) as SectorData
		if sector != null:
			return sector.zone
	return NameRegistry.NO_SCOPE


# --- filled in by SectorData.compile(), NOT stored in the resource ------------------
## Initial program counter (buffer offset of `start_label`).
var pc: int = 0
## Script entry points (buffer offsets of `hit_label` / `ink_label`) run on sub
## contact / ink hit.
var script_hit: int = 0
var script_ink: int = 0


# --- the original's record bytes ---------------------------------------------------------------------------------

## Everything that stops the record from being stored as the original's, in plain words; empty when it fits.
## `encode()` returns nothing while this is not empty. The three entry points are the numbers `SectorData.compile()`
## filled in, so a creature of a sector that was not compiled (or whose script has errors) reports them as 0, which
## fits; use `SectorData.foe_problems()` / `encode_foe_records()` to have the script compiled first.
func problems() -> Array[String]:
	var found: Array[String] = []
	for pair: Array in [["screen", screen], ["frame", frame], ["frame_min", frame_min], ["frame_max", frame_max]]:
		if pair[1] < 0 or pair[1] > 0xFF:
			found.append("%s %d does not fit: the original keeps it in one byte, so 0 to 255" % pair)
	if damage < -128 or damage > 127:
		found.append("damage %d does not fit: the original keeps it in one signed byte, so -128 to 127" % damage)
	for pair: Array in [["x", pos.x], ["y", pos.y]]:
		var value: int = pair[1]
		if value < 0 or value > 2 * 0xFFFF:
			found.append("%s %d does not fit: the original keeps %s / 2 in two bytes, so 0 to %d" % [pair[0], value, pair[0], 2 * 0xFFFF])
		elif value % 2 != 0:
			found.append("%s %d is not on the grid: the original keeps %s / 2, so it must be even" % [pair[0], value, pair[0]])
	for pair: Array in [["pc", pc], ["script_hit", script_hit], ["script_ink", script_ink]]:
		if pair[1] < 0 or pair[1] > 0xFFFF:
			found.append("%s %d does not fit in two bytes" % pair)
	if not runtime_state.is_empty() and runtime_state.size() != RUNTIME_STATE_SIZE:
		found.append("runtime_state: %d bytes, but it is empty or %d" % [runtime_state.size(), RUNTIME_STATE_SIZE])
	return found


## The original record: exactly RECORD_SIZE bytes, or an empty array while `problems()` finds problems.
func encode() -> PackedByteArray:
	if not problems().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(RECORD_SIZE)
	out[0x00] = 1 if dormant else 0
	out[0x01] = 1 if hidden else 0
	out[0x02] = screen
	out.encode_u16(0x03, pos.x / 2)
	out.encode_u16(0x05, pos.y / 2)
	out[0x07] = frame
	out[0x08] = 1 if flip else 0
	out[0x09] = frame_min
	out[0x0A] = frame_max
	out.encode_u16(0x0B, script_hit)
	out.encode_u16(0x0D, script_ink)
	out.encode_s8(0x0F, damage)
	out.encode_u16(0x10, pc)
	for i in runtime_state.size():
		out[RUNTIME_STATE_AT + i] = runtime_state[i]
	return out


## The name of the record field that byte `offset` belongs to, e.g. "x" or "run-time state byte 0x14".
static func field_at(offset: int) -> String:
	const NAMES := {0x00: "dormant", 0x01: "hidden", 0x02: "screen", 0x07: "frame", 0x08: "flip", 0x09: "frame min",
		0x0A: "frame max", 0x0F: "damage"}
	if NAMES.has(offset):
		return NAMES[offset]
	if offset < 0x05:
		return "x"
	if offset < 0x07:
		return "y"
	if offset < 0x0D:
		return "hit script"
	if offset < 0x0F:
		return "ink script"
	if offset < RUNTIME_STATE_AT:
		return "start pc"
	return "run-time state byte 0x%02x" % offset


## "" when the two records are the same, else "first difference at byte 0x05 (y): expected 0x2a, got 0x2b".
## Names the field of the `expected` record.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the record has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference at byte 0x%02x (%s): expected 0x%02x, got 0x%02x" % [i, field_at(i), expected[i], actual[i]]
	return ""
