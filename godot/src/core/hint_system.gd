class_name HintSystem
extends RefCounted
## The "new player hints": seven short tips, each shown to a player once.
##
## Teaches: a bit mask as a tiny set. The original keeps one bit per hint in the player's
## record: a SET bit means "not shown yet" (`ShowFirstTimeHint` (0x427e20): if the bit is set, clear it and show
## the hint), so a new player starts with all bits set. Options > New Player Hints switches the
## whole feature on or off. The class is pure logic (no nodes), so it is unit tested directly.
##
## Hint ids (DESIGN 5.9 / texts `hint_<id>`): 0 controls, 1 low oxygen, 2 data canister,
## 3 type your answer, 4 calculator, 5 blinking light, 6 fractions.

const COUNT := 7
const CONTROLS := 0
const LOW_OXYGEN := 1
const DATA_CANISTER := 2
const TYPE_ANSWER := 3
const CALCULATOR := 4
const BLINKING_LIGHT := 5
const FRACTIONS := 6

## The data has no text for the calculator hint (id 10171 is empty); this stands in for it.
const CALCULATOR_FALLBACK := "Use the calculator to work out the answer.\n\nClick its keys with the mouse or type\non the keyboard. When the answer you\nwant is showing, press Enter."

## Bit i set = hint i has not been shown yet.
var unseen_mask: int = (1 << COUNT) - 1
## Options > New Player Hints.
var enabled: bool = true


## Asks to show hint `id`. True exactly once per hint (while hints are enabled); it is then marked seen.
func take(id: int) -> bool:
	if not enabled or id < 0 or id >= COUNT:
		return false
	var bit := 1 << id
	if unseen_mask & bit == 0:
		return false
	unseen_mask &= ~bit
	return true


func has_been_shown(id: int) -> bool:
	return unseen_mask & (1 << id) == 0


## A new player: every hint is unseen again.
func reset() -> void:
	unseen_mask = (1 << COUNT) - 1


## Takes over the player's saved mask. The original keeps 16 bits (starting at 0xFFFF) but only
## the first seven mean anything.
func load_mask(saved: int) -> void:
	unseen_mask = saved & ((1 << COUNT) - 1)


## The mask as it is saved in the player's record: the unused upper bits stay set, like the original's 0xFFFF.
func mask_for_save() -> int:
	return unseen_mask | (0xFFFF & ~((1 << COUNT) - 1))


## The text of hint `id`, with the original's keyboard glyphs (control characters in the data)
## turned into words and arrows that any font can show. Empty when the data has no text
## (hint 4, the calculator, has none in the data).
static func text_for(id: int) -> String:
	var text_name := StringName("hint_%d" % id)                 # (`hint_0` .. `hint_6`; the data has no text for hint 4)
	var raw := Catalog.text(text_name) if Catalog.has_text(text_name) else ""
	if raw.is_empty() and id == CALCULATOR:
		return CALCULATOR_FALLBACK
	return printable(raw)


## The original's font has special pictures for keys at character codes 1-31 (the 20 px key caps of font resource 998).
## This maps them to text: arrows for the steering keys (0x19 left, 0x1a right, 0x1b down, 0x1c up), "Space" for the fire
## key, "Enter", the calculator's keys "F" (0x16, fraction), "C" (0x10, clear), "N" (0x13), "S" (0x15) and "R" (0x0f), and
## "/" for the fraction bar (0x0e: "Then press [/] and type in the denominator", the key `GetNumber` (0x41fb34) switches on).
## The map is keyed by the raw codes of the texts: `ConvertTextMarkup` (0x415ebf) turns the tab (9) of text 12016 into
## glyph 0x13, the negate key N ("Press [N], then type in the number"), and 0x0b into 0x10, and passes 0x10 (text 10162),
## 0x15 (store, S), 0x0f (recall, R), 0x0e and 0x16 through.
static func printable(raw: String) -> String:
	var map := {
		0x0e: "/", 0x16: "F", 0x0b: "C", 0x10: "C", 0x09: "N", 0x15: "S", 0x0f: "R",
		0x11: "Space", 0x12: "",          # the fire key is two glyphs wide in the original
		0x17: "Enter", 0x18: "",          # so is Enter
		0x19: "←", 0x1a: "→", 0x1b: "↓", 0x1c: "↑",
	}
	var out := ""
	for c in raw:
		var code := c.unicode_at(0)
		if code < 32 and code != 10 and code != 13:
			out += map.get(code, "")
		else:
			out += c
	return out.replace("\r", "\n")
