class_name FoeOps
extends RefCounted
## The instruction set of the creature scripts (DESIGN 3.5): opcode numbers, how
## many operand bytes each one has, and a tiny disassembler for debug displays.
## The manual for people who write scripts is docs/create/FOE_SCRIPTING.md.
##
## Teaches: an `enum` as a table of names, parallel constant arrays indexed by the
## enum, and why a bytecode format is easy to inspect once you can print it.

## The original's 25 opcodes, then `MOD_INSTRUCTION`, the port's own: an instruction only for a campaign that declares a mod pack with creature instructions (`RuleHooks`,
## `FoeVM.Context.hooks`). Anywhere else a creature that reaches it faults as it does for any byte that is no opcode, so the original's sectors, which hold none, run as they do.
## It is in the tables below so that the assembler, the disassembler and the editor know it.
enum Op {
	YIELD, JMP, HANDLER, RET, LOOP0, LOOP1, LOOP2, SOUND, SLEEP_FOE, WAKE_FOE,
	FRAME_RANGE, SET_FRAME, MOVE_REL, SET_POS, SET_POS_SCREEN, HIDE, SHOW,
	IF_SUBX_GT, IF_SUBX_LT, IF_SUBY_GT, IF_SUBY_LT, IF_RAND_GT, SEM_SET, SEM_CLR, IF_SEM,
	MOD_INSTRUCTION,
}


## Number of operand bytes after each opcode (the original's table at DS 0x184A, and the port's own entry for `MOD_INSTRUCTION`).
const OPERAND_COUNT: Array[int] = [
	0, 2, 2, 0, 4, 4, 4, 1, 1, 1, 2, 1, 3, 3, 4, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2]


## The beginner-friendly spelling of each opcode, indexed by opcode number. These are
## the names a level designer types in a script (see FoeAsm) and the names every
## debug display prints. The enum keys above (YIELD, JMP ...) stay as the short
## names the original code used; the VM source keeps using them.
##
## The full manual, with every instruction explained, is docs/create/FOE_SCRIPTING.md; what
## each instruction does in one line is SUMMARY below, its operands are OPERANDS.
const MNEMONIC: Array[String] = [
	"Wait_Next_Tick", "Jump_To", "Call_Subroutine", "Return",
	"Loop_Counter0_Back_To", "Loop_Counter1_Back_To", "Loop_Counter2_Back_To",
	"Play_Sound", "Put_Foe_To_Sleep", "Wake_Foe",
	"Set_Frame_Range", "Set_Frame", "Move_Foe_Relative_XY", "Move_Foe_To_XY",
	"Move_Foe_To_Screen_XY", "Hide_Foe", "Show_Foe",
	"If_Sub_X_Greater", "If_Sub_X_Less", "If_Sub_Y_Greater", "If_Sub_Y_Less",
	"If_Random_Greater", "Set_Flag", "Clear_Flag", "If_Flag", "Mod_Instruction",
]

## What each instruction does, in one line, indexed like MNEMONIC (the editor shows it
## in its tooltips and completion list). "Ends the tick" means the creature does nothing
## more until the next game tick.
const SUMMARY: Array[String] = [
	"Ends the tick; the script resumes just after it next tick.",                        # YIELD
	"Continue at a label.",                                                              # JMP
	"Jump to a label and remember where to come back to (Return comes back).",          # HANDLER
	"End of a hit/ink script, or return from a subroutine.",                             # RET
	"Count down counter 0; jump back to a label until it runs out (the body runs count + 1 times).",   # LOOP0
	"The same with the independent counter 1.",                                          # LOOP1
	"The same with the independent counter 2.",                                          # LOOP2
	"Play a sound effect (only if the creature is on the shown screen).",               # SOUND
	"A sleeping creature runs no script; put the named creature (or self+N) to sleep.",  # SLEEP_FOE
	"Undo Put_Foe_To_Sleep for the named creature (or self+N).",                         # WAKE_FOE
	"The lowest and highest picture this creature may show.",                            # FRAME_RANGE
	"Show a picture (write mirrored after it to flip it left-right).",                   # SET_FRAME
	"Move by dx, dy (signed, 2-pixel steps) and step the picture; ends the tick.",       # MOVE_REL
	"Jump to x (4-pixel steps), y (2-pixel steps) with a picture; ends the tick.",       # SET_POS
	"As Move_Foe_To_XY, and also change to another screen; ends the tick.",              # SET_POS_SCREEN
	"Make the creature invisible and untouchable; ends the tick.",                       # HIDE
	"Make the creature visible again.",                                                  # SHOW
	"Run the next instruction only if the sub's X is greater than 4*x, else skip it.",   # IF_SUBX_GT
	"Run the next instruction only if the sub's X is less than 4*x, else skip it.",      # IF_SUBX_LT
	"Run the next instruction only if the sub's Y is greater than 2*y, else skip it.",   # IF_SUBY_GT
	"Run the next instruction only if the sub's Y is less than 2*y, else skip it.",      # IF_SUBY_LT
	"Run the next instruction only if a random 0-255 is greater than the value, else skip it.",   # IF_RAND_GT
	"Raise a global flag bit (shared by all creatures).",                                # SEM_SET
	"Lower a global flag bit.",                                                          # SEM_CLR
	"Run the next instruction only if the flag bit is raised, else skip it.",              # IF_SEM
	"An instruction a mod pack of the campaign defines (only a campaign that declares one runs it).",   # MOD_INSTRUCTION
]


# =============================================================================
# Operands: the single description of every instruction's parameters
# =============================================================================

## How an operand is written and stored. The assembler, the disassembler and the editor
## (FoeLineInfo, FoeHelp) all take what they need from this one table.
##   LABEL  a label name; two bytes, the signed distance to the label from the next instruction
##   U8     one byte, 0..255
##   I8     one byte, -128..127
##   U16    two bytes, 0..65535
##   FOE    one byte: a creature number 0..127, or self / self+N / self-N (bit 7 set, N in 7 bits), or a creature's name
##   COUNT  a number of bytes, 1..65535 (only the `count` of the Padding pseudo-instruction; no bytes of its own)
##   SOUND, FRAME, FLAG, SCREEN  one byte like U8 (0..255 as a plain number), but a NAME of the kind is accepted too:
##          a sound, a creature picture, a flag, a screen (NameRegistry; FoeNames says which names are valid where)
enum Kind { LABEL, U8, I8, U16, FOE, COUNT, SOUND, FRAME, FLAG, SCREEN }

## Written after an operand that has "mirror" (a picture, or the picture step of Move_Foe_Relative_XY) to set its bit 7:
## `Set_Frame eel_swim_1 mirrored`, `Set_Frame 35 mirrored` (= 163). A plain number with bit 7 set (`Set_Frame 163`) is
## still accepted. NameRegistry.RESERVED keeps the word out of the names.
const MIRROR_WORD := "mirrored"

## A jump can reach this far (the distance is a signed 16-bit number).
const JUMP_MIN := -32768
const JUMP_MAX := 32767
## The N of self+N / self-N.
const SELF_MIN := -64
const SELF_MAX := 63
const FOE_MAX := 127

## The most bytes one `Padding` line can write.
const PADDING_MAX := 65535

## The character CodeEdit.set_code_hint looks for around the argument to underline.
const HINT_MARK := "\uFFFF"

# Operands that several instructions share.
const _LABEL := {"name": "label", "kind": Kind.LABEL,
	"meaning": "the label to continue at (a name defined elsewhere as `name:`)"}
const _COUNT := {"name": "count", "kind": Kind.U16,
	"meaning": "how often to jump back; the loop body runs count + 1 times, and 0 never ends"}
const _FOE := {"name": "foe", "kind": Kind.FOE,
	"meaning": "which creature: its number in the sector's foe list, or self, self+N, self-N relative to the creature running the instruction"}
const _FLAG := {"name": "flag", "kind": Kind.FLAG, "meaning": "the flag number 0..15 or its name (bit 15 is the sector finale)"}
const _FRAME := {"name": "frame", "kind": Kind.FRAME, "mirror": true,
	"meaning": "the picture: its name or number (0..127); write mirrored after it to flip it left-right"}
const _FRAME_IN_RANGE := {"name": "frame", "kind": Kind.FRAME, "mirror": true,
	"meaning": "the picture: its name or number (0..127, kept inside the frame range); write mirrored after it to flip it"}
const _X := {"name": "x", "kind": Kind.U8, "pixels": 4, "meaning": "horizontal position in 4-pixel steps (window pixel = 4 * x)"}
const _Y := {"name": "y", "kind": Kind.U8, "pixels": 2, "meaning": "vertical position in 2-pixel steps (window pixel = 2 * y)"}

## The operands of each instruction, indexed by opcode like MNEMONIC. One Dictionary per
## operand, in the order they are written and stored:
##   "name"     what the editor calls it (the manual uses the same names)
##   "kind"     a Kind: how it is written, how many bytes it takes, which values are valid
##   "meaning"  what it means, with its unit
##   "pixels"   (only for positions) how many window pixels one unit is: 4 for x, 2 for y
##   "mirror"   (only when true) bit 7 mirrors the picture; written as MIRROR_WORD after the operand (or add 128)
const OPERANDS: Array = [
	[],                                                       # Wait_Next_Tick
	[_LABEL],                                                 # Jump_To
	[_LABEL],                                                 # Call_Subroutine
	[],                                                       # Return
	[_LABEL, _COUNT],                                         # Loop_Counter0_Back_To
	[_LABEL, _COUNT],                                         # Loop_Counter1_Back_To
	[_LABEL, _COUNT],                                         # Loop_Counter2_Back_To
	[{"name": "sound", "kind": Kind.SOUND, "meaning": "the sound effect: its name or its number"}],     # Play_Sound
	[_FOE],                                                   # Put_Foe_To_Sleep
	[_FOE],                                                   # Wake_Foe
	[{"name": "min", "kind": Kind.FRAME, "meaning": "the lowest picture the creature may show: its name or number"},
		{"name": "max", "kind": Kind.FRAME, "meaning": "the highest picture the creature may show: its name or number"}],   # Set_Frame_Range
	[_FRAME],                                                 # Set_Frame
	[{"name": "dx", "kind": Kind.I8, "pixels": 2, "meaning": "how far to move right (negative: left), in 2-pixel steps"},
		{"name": "dy", "kind": Kind.I8, "pixels": 2, "meaning": "how far to move down (negative: up), in 2-pixel steps"},
		{"name": "frame", "kind": Kind.U8, "mirror": true,
			"meaning": "the picture step (a number, not a picture): the low 7 bits are added to the picture (0 keeps it, it wraps inside the frame range); write mirrored after it to flip"}],   # Move_Foe_Relative_XY
	[_X, _Y, _FRAME_IN_RANGE],                                # Move_Foe_To_XY
	[_X, _Y, _FRAME_IN_RANGE,
		{"name": "screen", "kind": Kind.SCREEN, "meaning": "the screen to change to: its name or number (the real screens are 0..11)"}],   # Move_Foe_To_Screen_XY
	[],                                                       # Hide_Foe
	[],                                                       # Show_Foe
	[{"name": "x", "kind": Kind.U8, "pixels": 4, "meaning": "compared with the sub's X (window pixels) as 4 * x"}],    # If_Sub_X_Greater
	[{"name": "x", "kind": Kind.U8, "pixels": 4, "meaning": "compared with the sub's X (window pixels) as 4 * x"}],    # If_Sub_X_Less
	[{"name": "y", "kind": Kind.U8, "pixels": 2, "meaning": "compared with the sub's Y (window pixels) as 2 * y"}],    # If_Sub_Y_Greater
	[{"name": "y", "kind": Kind.U8, "pixels": 2, "meaning": "compared with the sub's Y (window pixels) as 2 * y"}],    # If_Sub_Y_Less
	[{"name": "value", "kind": Kind.U8, "meaning": "true if a random number 0..255 is greater than this (255 never, 0 almost always)"}],   # If_Random_Greater
	[_FLAG],                                                  # Set_Flag
	[_FLAG],                                                  # Clear_Flag
	[_FLAG],                                                  # If_Flag
	[{"name": "number", "kind": Kind.U8, "meaning": "which instruction of the campaign's mods this is (0 to 7); a number no mod defines does nothing"},
		{"name": "value", "kind": Kind.U8, "meaning": "the operand the mod is given (0 to 255)"}],   # Mod_Instruction
]


# =============================================================================
# Pseudo-instructions: directives for the assembler, not opcodes
# =============================================================================

## A PSEUDO-INSTRUCTION is written like an instruction but is not one: it tells the
## ASSEMBLER what to put in the bytes (like `db 0` or `.fill` in a real assembler), and
## no creature ever executes it as such. It has no opcode byte, so it is NOT in OPERAND_COUNT,
## MNEMONIC, SUMMARY or OPERANDS above (those are indexed by the opcodes the VM runs, and
## the VM and the bytes are untouched by it). Its numbers start at PSEUDO_FIRST (256, above
## every byte), so one number can name "the thing at the start of a line" for the editor:
## `op_from_mnemonic`, `op_name`, `operands`, `summary` and `signature` answer for these too.
## `is_valid` stays true only for real opcodes.
const PSEUDO_FIRST := 256
## `Padding count`: the assembler writes `count` zero bytes (1 when `count` is left out).
## Zero is the opcode of Wait_Next_Tick, so these bytes, if a creature ever reached them,
## would run as that many Wait_Next_Tick; the disassembler writes unreachable zero bytes
## as Padding to say that nobody does.
const PADDING := PSEUDO_FIRST

## One entry per pseudo-instruction, indexed by (number - PSEUDO_FIRST):
##   "name"      what is typed
##   "summary"   one line for the editor
##   "operands"  like one entry of OPERANDS, plus "optional": true for an operand that may be left out
const PSEUDO: Array[Dictionary] = [
	{
		"name": "Padding",
		"summary": "Not an instruction: the assembler writes count zero bytes here (filler that no creature reaches).",
		"operands": [{"name": "count", "kind": Kind.COUNT, "optional": true,
				"meaning": "how many zero bytes to write (1 when left out); each would run as a Wait_Next_Tick if a creature ever reached it"}],
	},
]


static func is_pseudo(opcode: int) -> bool:
	return opcode >= PSEUDO_FIRST and opcode < PSEUDO_FIRST + PSEUDO.size()


## Every number the editor can show help for: the opcodes in order, then the pseudo-instructions.
static func listed() -> Array[int]:
	var result: Array[int] = []
	for opcode in MNEMONIC.size():
		result.append(opcode)
	for k in PSEUDO.size():
		result.append(PSEUDO_FIRST + k)
	return result


## The one-line summary of an opcode or pseudo-instruction ("" for a number that is neither).
static func summary(opcode: int) -> String:
	if is_pseudo(opcode):
		return PSEUDO[opcode - PSEUDO_FIRST]["summary"]
	return SUMMARY[opcode] if is_valid(opcode) else ""


static func is_valid(opcode: int) -> bool:
	return opcode >= 0 and opcode < OPERAND_COUNT.size()


## "Move_Foe_Relative_XY" for Op.MOVE_REL; "??37" for a byte that is not an opcode.
static func op_name(opcode: int) -> String:
	if is_pseudo(opcode):
		return PSEUDO[opcode - PSEUDO_FIRST]["name"]
	if not is_valid(opcode):
		return "??%d" % opcode
	return MNEMONIC[opcode]


## The opcode for a friendly name, ignoring upper/lower case; -1 if there is no such
## instruction. A pseudo-instruction gives its number (PADDING), which is no opcode: the
## assembler must check `is_pseudo` before it indexes OPERAND_COUNT. (The short names of
## the enum, like "JMP", are not accepted.)
static func op_from_mnemonic(name: String) -> int:
	var wanted := name.to_lower()
	for opcode in MNEMONIC.size():
		if MNEMONIC[opcode].to_lower() == wanted:
			return opcode
	for k in PSEUDO.size():
		if PSEUDO[k]["name"].to_lower() == wanted:
			return PSEUDO_FIRST + k
	return -1


## One instruction as text, e.g. "0867: Move_Foe_Relative_XY 0 0 1". `base` is the buffer offset
## of `script[0]` (SectorData.foe_script_base); `pc` is a buffer offset too.
static func disassemble_one(script: PackedByteArray, base: int, pc: int) -> String:
	var index := pc - base
	if index < 0 or index >= script.size():
		return "%04d: <outside the script>" % pc
	var opcode := script[index]
	var text := "%04d: %s" % [pc, op_name(opcode)]
	if is_valid(opcode):
		for i in OPERAND_COUNT[opcode]:
			if index + 1 + i < script.size():
				text += " %d" % script[index + 1 + i]
	return text


## The operands of `opcode` (see OPERANDS) or of a pseudo-instruction (PSEUDO); an empty
## array for a byte that is no opcode.
static func operands(opcode: int) -> Array:
	if is_pseudo(opcode):
		return PSEUDO[opcode - PSEUDO_FIRST]["operands"]
	return OPERANDS[opcode] if is_valid(opcode) else []


## How many bytes an operand of this kind takes (a COUNT takes none: it says how many bytes
## the pseudo-instruction itself writes).
static func kind_width(kind: int) -> int:
	if kind == Kind.COUNT:
		return 0
	return 2 if kind == Kind.LABEL or kind == Kind.U16 else 1


## The smallest and largest value of a kind (for a LABEL: the jump distance). A FOE is a
## creature number here; its self+N form is described by SELF_MIN and SELF_MAX.
static func kind_range(kind: int) -> Vector2i:
	match kind:
		Kind.LABEL:
			return Vector2i(JUMP_MIN, JUMP_MAX)
		Kind.I8:
			return Vector2i(-128, 127)
		Kind.U16:
			return Vector2i(0, 65535)
		Kind.COUNT:
			return Vector2i(1, PADDING_MAX)
		Kind.FOE:
			return Vector2i(0, FOE_MAX)
	return Vector2i(0, 255)


## Names of the kinds for people: "unsigned byte".
static func kind_name(kind: int) -> String:
	match kind:
		Kind.LABEL:
			return "label"
		Kind.I8:
			return "signed byte"
		Kind.U16:
			return "16-bit number"
		Kind.FOE:
			return "creature"
		Kind.COUNT:
			return "number of bytes"
		Kind.SOUND:
			return "sound effect"
		Kind.FRAME:
			return "picture"
		Kind.FLAG:
			return "flag"
		Kind.SCREEN:
			return "screen"
	return "unsigned byte"


## The NameRegistry kind whose names an operand of this kind may be written with, or &"" for a kind that has none.
static func name_kind(kind: int) -> StringName:
	match kind:
		Kind.SOUND:
			return &"sound"
		Kind.FRAME:
			return &"frame"
		Kind.FOE:
			return &"foe"
		Kind.FLAG:
			return &"flag"
		Kind.SCREEN:
			return &"screen"
	return &""


## The valid values of a kind as text: "0..255", "-128..127", "a label". This is also what
## the assembler prints in its "must be ..." messages.
static func range_text(kind: int) -> String:
	var limits := kind_range(kind)
	match kind:
		Kind.LABEL:
			return "a label"
		Kind.FOE:
			return "%d..%d or self, self+N, self-N with N from %d to %d" % [limits.x, limits.y, SELF_MIN, SELF_MAX]
	return "%d..%d" % [limits.x, limits.y]


## The bytes of all operands of `opcode`: must equal OPERAND_COUNT (a test checks it).
static func operand_bytes(opcode: int) -> int:
	var total := 0
	for operand in operands(opcode):
		total += kind_width(operand["kind"])
	return total


## `opcode`'s name and operand names: "Move_Foe_To_XY x y frame" (an operand that may be left
## out is in brackets: "Padding [count]"). With `marked` >= 0 the
## operand of that index is put between two U+FFFF characters, which is how a CodeEdit's
## code hint is told which argument to underline.
static func signature(opcode: int, marked := -1) -> String:
	var parts: Array[String] = [op_name(opcode)]
	var list := operands(opcode)
	for i in list.size():
		var shown: String = "[%s]" % list[i]["name"] if list[i].get("optional", false) else list[i]["name"]
		parts.append(HINT_MARK + shown + HINT_MARK if i == marked else shown)
	return " ".join(parts)


## A creature operand as the byte the VM stores: 3 -> 3, "self" -> 0x80, "self+2" -> 0x82,
## "self-1" -> 0xFF. Returns -1 when the word is none of these. (The inverse of what
## FoeAsm prints; `self` may be written in any case.)
static func parse_foe(word: String) -> int:
	var lower := word.to_lower()
	if word.is_valid_int() and word.to_int() >= 0 and word.to_int() <= FOE_MAX:
		return word.to_int()
	if lower == "self":
		return 0x80
	if lower.begins_with("self+") or lower.begins_with("self-"):
		var digits := lower.substr(5)
		if digits.is_valid_int() and digits.unicode_at(0) >= 48 and digits.unicode_at(0) <= 57:
			var offset := digits.to_int() * (1 if lower[4] == "+" else -1)
			if offset >= SELF_MIN and offset <= SELF_MAX:
				return 0x80 | (offset & 0x7F)
	return -1
