class_name FoeVM
extends RefCounted
## The virtual machine that runs one creature's script (DESIGN 3.5).
##
## Teaches: a small bytecode interpreter written readably (fetch an opcode, `match`
## on it, advance the program counter); a state machine that can be interrupted
## and resumed; and logic with no nodes at all, so every opcode can be unit tested
## with a hand-assembled byte array. `Foe` (a node) is only the thin adapter that
## shows this object's state on screen.
##
## HOW A SCRIPT RUNS. Once per game tick `tick()` executes instructions until one of
## them YIELDs (ends the creature's turn) or moves it (MOVE_REL, SET_POS ... also
## end the turn). The program counter `pc` is a byte offset into the creature
## buffer of the original game; `script[pc - base]` is the byte it points at.
##
## INTERRUPTS. When the sub touches a creature, the creature is "interrupted": its
## pc, position and picture are saved and it runs its `script_hit` (contact) entry;
## an ink pellet does the same with `script_ink`. A `RET` in such a script restores
## the saved state, so the creature carries on where it was. Without an interrupt,
## `RET` returns from a subroutine that HANDLER set up (see below).
##
## THE 25 OPCODES (operand bytes in brackets), and a 26th that only a campaign with a mod runs (`MOD_INSTRUCTION`, below):
##   YIELD         end this tick
##   JMP [i16]     pc = (address after the operands) + offset
##   HANDLER [i16] a CALL: remember the address after the operands as the return
##                 point, then jump forward (or back) by the offset to the subroutine
##   RET           end of an interrupt script, or return from a HANDLER subroutine
##   LOOP0/1/2 [i16 offset, u16 count]  jump back to (address after) + offset `count`
##                 times, so the body runs count + 1 times in total (the original's
##                 first visit only loads the counter); three independent counters
##   SOUND [u8]    ask for a sound effect (only when the creature is on the current screen)
##   SLEEP_FOE/WAKE_FOE [u8]  set/clear the `dormant` flag of creature number n; SLEEP_FOE
##                 also ends the running creature's own interrupt (nothing restored)
##   FRAME_RANGE [min, max]   the picture numbers MOVE_REL cycles through and SET_POS clamps into
##   SET_FRAME [u8]           picture = low 7 bits, mirrored if bit 7 is set
##   MOVE_REL [dx i8, dy i8, f]  move by (2*dx, 2*dy) pixels; f: bit 7 = mirrored,
##                 low 7 bits = picture increment (below min wraps to max, above max to min); ends the turn
##   SET_POS [x, y, f]        jump to (4*x, 2*y) with picture f & 0x7F clamped into FRAME_RANGE
##                 (bit 7 = mirrored); ends the turn
##   SET_POS_SCREEN [x, y, f, screen]  the same, on another screen
##   HIDE / SHOW   hidden = true (ends the turn) / false
##   IF_SUBX_GT/LT [v]  run the NEXT instruction only if SubX > / < 4*v, else skip it
##   IF_SUBY_GT/LT [v]  the same with SubY and 2*v
##   IF_RAND_GT [v]     only if a random number 0-255 is > v
##   SEM_SET/SEM_CLR [bit], IF_SEM [bit]  the global flags shared by all creatures
##   MOD_INSTRUCTION [number, value]  the port's own: ask the campaign's mod (`RuleHooks.creature_instruction`) what this instruction does and apply the plain answer the game
##                 validated (skip the next instruction, raise or lower flags, show a picture, move, end the turn). Without a mod that defines instructions it is no opcode at all
##                 ("unknown opcode"), as for every byte the original does not know; a number no mod defines does nothing.

# --- what the creature looks like (the Foe node shows these) -------------------
var index: int = 0                 ## position in the sector's creature list
var x: int = 0                     ## top-left corner of the picture, WINDOW pixels like the original (the Foe node subtracts the playfield's (16, 32))
var y: int = 0
var frame: int = 0                 ## picture number (slot in the zone's foe SpriteFrames)
var flip: bool = false             ## mirrored horizontally
var hidden: bool = false           ## not drawn, cannot be touched
var dormant: bool = false          ## scripts do not run while dormant
var screen: int = 0                ## the screen it lives on
## True if the last tick put the creature somewhere instead of stepping it there (SET_POS, SET_POS_SCREEN, the
## end of an interrupt): the Foe node must draw the new place at once, not glide to it.
var jumped: bool = false
var damage: int = 1                ## oxygen lost on contact; negative = friendly (Zoom)

# --- script state ----------------------------------------------------------------
var frame_min: int = 0
var frame_max: int = 0
var script_hit: int = 0            ## entry points (buffer offsets) for interrupts
var script_ink: int = 0
var pc: int = 0
## True while a hit or ink script runs; the state to come back to is in `_saved_*`.
var interrupted: bool = false
## Non-empty if the script did something impossible; the creature then freezes.
var fault: String = ""
## The sector the creature belongs to (its number, for the words of a warning); -1 for a VM made outside `from_data`.
var sector_index: int = -1

var _fault_told := false
var _script: PackedByteArray
var _base: int = 0                 ## buffer offset of _script[0]
var _return_pc: int = 0            ## where RET goes when not interrupted (set by HANDLER)
var _counters: Array[int] = [0, 0, 0]
var _saved_pc: int = 0
var _saved_x: int = 0
var _saved_y: int = 0
var _saved_frame: int = 0
var _saved_flip: bool = false


## Everything a script can look at or change outside its own creature.
## One Context is shared by all creatures of a sector.
##
## LIFETIMES. The context is derived state: its owner (`SimWorld`, which keeps one for its whole life) fills every field from its own
## state, one lifetime at a time, and a tool or a test that runs scripts by themselves makes its own. Each field is in one of the
## `*_FIELDS` lists below, and each list has the one method that fills it (docs/engine/ARCHITECTURE.md, "Lifetimes of state";
## tests/engine/test_state_lifetimes.gd checks both).
class Context extends RefCounted:
	## Filled by `begin_load`: what a load of the creatures gives the scripts (a sector start, a respawn, the reload after the lock).
	const LOAD_FIELDS: Array[StringName] = [&"semaphore", &"foes", &"rng"]
	## Filled by `show_screen`: the screen that is shown.
	const SCREEN_FIELDS: Array[StringName] = [&"current_screen"]
	## Filled by `begin_tick`, at the start of the creatures' step of every tick: where the sub is, and no sound asked for yet.
	const TICK_FIELDS: Array[StringName] = [&"sub_x", &"sub_y", &"sounds"]
	## Member variables that no lifetime fills, and why.
	const KEPT_FIELDS: Dictionary[StringName, String] = {
		&"max_instructions": "configuration: the run's limit (`Tuning.max_instructions_per_tick`), handed over by the owner (`SimWorld.load_sector`)",
		&"hooks": "configuration: the run's rule hooks (`RuleHooks`, null for none), handed over by the owner (`SimWorld.load_sector`); what they keep has lifetimes of its own",
		&"trouble": "the warnings given for this context's creatures (a creature that faults, a `Mod_Instruction` no mod defines), each once for the life of the context, so a respawn does not say it again",
	}

	## The sub's SubX / SubY: window pixels of its picture's top-left corner.
	var sub_x: int = 0
	var sub_y: int = 0
	var current_screen: int = 0
	## The 16 global flags ("FoeSemaphore"); the finale uses bit 15.
	var semaphore: int = 0
	## All creatures of the sector, indexed like the creature list (SLEEP/WAKE use it).
	var foes: Array[FoeVM] = []
	## The dice of `IF_RAND_GT`. A `SimWorld` hands over its own (`SimWorld.foe_rng`), which outlives every load.
	var rng := RandomNumberGenerator.new()
	## Sound effects requested during ticks; whoever plays sounds drains this list.
	var sounds: Array[int] = []
	## Longest run without a YIELD before a script is judged stuck in an endless loop.
	var max_instructions: int = 0
	## The run's rule hooks (`RuleHooks`): the creature instructions the campaign's mods define. Null (a tool, a test of the VM alone) or empty: `MOD_INSTRUCTION` is no opcode.
	var hooks: RuleHooks = null
	## The warnings about a pack's scripts given so far (`TroubleLog`).
	var trouble := TroubleLog.new()

	## Does a mod give `MOD_INSTRUCTION` a meaning in this run?
	func runs_mod_instructions() -> bool:
		return hooks != null and hooks.runs_instructions()

	## `tuning` is the rule values the scripts run under (the run's, or a tool's `Tuning.resolve()`: every path of the game and the tools gives one); a bare context, for a test of the VM alone, has the original's.
	func _init(tuning: Tuning = null) -> void:
		max_instructions = (tuning if tuning != null else Tuning.original()).max_instructions_per_tick

	## The creatures of a sector were (re)made: every field starts from what the owner holds now. `creatures` are the new VMs,
	## `dice` the owner's generator, `screen` the screen that is shown and `sub_at` the sub's SubX / SubY.
	## Deliberate deviation from the original (G40): `FoeSemaphore` (0x448cac) is never cleared there, so the creature flags survive
	## sectors, respawns and later games of the same session. The port starts every load of the creatures (respawns included) with all
	## flags 0. The only visible effects of the original's leftovers are short and cosmetic (sectors 16, 19, 24, bit 0; see
	## docs/create/FOE_SCRIPTING.md "Global flags").
	func begin_load(creatures: Array[FoeVM], dice: RandomNumberGenerator, screen: int, sub_at: Vector2i) -> void:
		semaphore = 0
		foes = creatures
		rng = dice
		show_screen(screen)
		begin_tick(sub_at)

	## Screen `screen` is shown: the creatures on it are the ones that are drawn and touched.
	func show_screen(screen: int) -> void:
		current_screen = screen

	## The creatures' step of a tick begins with the sub at `sub_at` (SubX / SubY): the scripts compare with it, and the sounds they
	## ask for in this step are collected from nothing.
	func begin_tick(sub_at: Vector2i) -> void:
		sub_x = sub_at.x
		sub_y = sub_at.y
		sounds = []


## Builds a VM from a creature record of `sector` (index = position in sector.foes).
## The sector's script text is compiled first (once); if it has errors the creature
## starts with a fault, so it stands still instead of running garbage.
static func from_data(data: FoeData, foe_index: int, sector: SectorData) -> FoeVM:
	sector.ensure_compiled()
	var vm := FoeVM.new()
	vm.index = foe_index
	vm.sector_index = sector.index
	vm.setup(data, sector.foe_bytecode, sector.foe_script_base)
	if not sector.compile_errors.is_empty():
		vm.fault = "the script of %s did not compile (%d problems), first: %s" % [
				sector.describe(), sector.compile_errors.size(), sector.compile_errors[0]]
	return vm


func setup(data: FoeData, script: PackedByteArray, base: int) -> void:
	_script = script
	_base = base
	dormant = data.dormant
	hidden = data.hidden
	screen = data.screen
	x = data.pos.x
	y = data.pos.y
	frame = data.frame
	flip = data.flip
	frame_min = data.frame_min
	frame_max = data.frame_max
	script_hit = data.script_hit
	script_ink = data.script_ink
	damage = data.damage
	pc = data.pc
	_return_pc = data.pc
	interrupted = false
	fault = ""
	_fault_told = false


## May this creature execute a script now? Dormant ones never do; others only while
## their screen is shown, except that an interrupted one finishes its interrupt.
func can_run(current_screen: int) -> bool:
	return fault.is_empty() and not dormant and (screen == current_screen or interrupted)


## Is something pressing on the hit / ink entries right now?
## (A creature that is already busy with an interrupt ignores new ones.)
## Deliberate deviation from the original (G41): `update_animals` (0x41ed0c) does not test the dormant byte at
## contact, so the sub's touch also gives a dormant, shown creature a pending hit script (run once it is woken).
## The port refuses the interrupt for a dormant creature (the damage still applies, `SimWorld.sub_touches`).
## No original sector has a dormant creature that is visible, so the difference cannot be seen with the data.
func can_be_interrupted() -> bool:
	return fault.is_empty() and not interrupted and not dormant and not hidden


## Starts an interrupt: save the state, continue at `entry` (a buffer offset).
func interrupt(entry: int) -> void:
	_saved_pc = pc
	_saved_x = x
	_saved_y = y
	_saved_frame = frame
	_saved_flip = flip
	interrupted = true
	pc = entry


## Runs this creature's script for one game tick.
func tick(ctx: Context) -> void:
	jumped = false
	if not can_run(ctx.current_screen):
		_tell_fault(ctx)
		return
	for _step in ctx.max_instructions:
		if not _execute_one(ctx):
			_tell_fault(ctx)
			return
	_fail("more than %d instructions without a YIELD (endless loop?)" % ctx.max_instructions)
	_tell_fault(ctx)


## A creature that has faulted stands still for good, which a player sees as a creature that does not do what the sector's script says: the fault is warned about once (a creature that was made with a fault, a script that did not compile, says so
## in its first tick, on whatever screen it is, and the one line says it for every creature of the sector). Once per context as well: the respawn that makes the creature again says nothing new.
func _tell_fault(ctx: Context) -> void:
	if fault.is_empty() or _fault_told:
		return
	_fault_told = true
	ctx.trouble.tell("[creatures] %s%s; the creature stays where it is and does nothing more (until the sector is loaded again)" % [_where(), fault])


## Executes the instruction at `pc`. Returns true to keep going, false when the
## creature's turn is over (a YIELD, a move, or a fault).
func _execute_one(ctx: Context) -> bool:
	var at := pc
	var opcode := _byte(at)
	if not FoeOps.is_valid(opcode) or (opcode == FoeOps.Op.MOD_INSTRUCTION and not ctx.runs_mod_instructions()):
		_fail("unknown opcode %d at %d%s" % [opcode, at, _no_mod_instruction(opcode, at)])
		return false
	# `next` is the address right after this instruction's operand bytes. Jumps are
	# measured from here, and so is the "skip the next instruction" of the IF_ ops.
	var next := at + 1 + FoeOps.OPERAND_COUNT[opcode]
	pc = next
	if not fault.is_empty():
		return false

	match opcode:
		FoeOps.Op.YIELD:
			return false
		FoeOps.Op.JMP:
			pc = next + _i16(at + 1)
		FoeOps.Op.HANDLER:
			_return_pc = next
			pc = next + _i16(at + 1)
		FoeOps.Op.RET:
			_return_from_script()
		FoeOps.Op.LOOP0, FoeOps.Op.LOOP1, FoeOps.Op.LOOP2:
			_loop(opcode - FoeOps.Op.LOOP0, next, _i16(at + 1), _u16(at + 3))
		FoeOps.Op.SOUND:
			if screen == ctx.current_screen:
				ctx.sounds.append(_byte(at + 1))
		FoeOps.Op.SLEEP_FOE:
			_set_dormant(ctx, _byte(at + 1), true)
		FoeOps.Op.WAKE_FOE:
			_set_dormant(ctx, _byte(at + 1), false)
		FoeOps.Op.FRAME_RANGE:
			frame_min = _byte(at + 1)
			frame_max = _byte(at + 2)
		FoeOps.Op.SET_FRAME:
			_set_picture(_byte(at + 1))
		FoeOps.Op.MOVE_REL:
			x += _i8(at + 1) * 2          # the original keeps positions in 2-pixel units
			y += _i8(at + 2) * 2
			_advance_picture(_byte(at + 3))
			return false
		FoeOps.Op.SET_POS:
			x = _byte(at + 1) * 4         # x operand: 4-pixel units, y operand: 2-pixel units
			y = _byte(at + 2) * 2
			_set_picture_clamped(_byte(at + 3))
			jumped = true
			return false
		FoeOps.Op.SET_POS_SCREEN:
			x = _byte(at + 1) * 4         # x operand: 4-pixel units, y operand: 2-pixel units
			y = _byte(at + 2) * 2
			_set_picture_clamped(_byte(at + 3))
			screen = _byte(at + 4)
			jumped = true
			return false
		FoeOps.Op.HIDE:
			hidden = true
			return false
		FoeOps.Op.SHOW:
			hidden = false
		FoeOps.Op.IF_SUBX_GT:
			_if(ctx, next, ctx.sub_x > 4 * _byte(at + 1))
		FoeOps.Op.IF_SUBX_LT:
			_if(ctx, next, ctx.sub_x < 4 * _byte(at + 1))
		FoeOps.Op.IF_SUBY_GT:
			_if(ctx, next, ctx.sub_y > 2 * _byte(at + 1))
		FoeOps.Op.IF_SUBY_LT:
			_if(ctx, next, ctx.sub_y < 2 * _byte(at + 1))
		FoeOps.Op.IF_RAND_GT:
			_if(ctx, next, ctx.rng.randi_range(0, 255) > _byte(at + 1))
		FoeOps.Op.SEM_SET:
			ctx.semaphore |= 1 << _byte(at + 1)
		FoeOps.Op.SEM_CLR:
			ctx.semaphore &= ~(1 << _byte(at + 1))
		FoeOps.Op.IF_SEM:
			_if(ctx, next, ((ctx.semaphore >> _byte(at + 1)) & 1) == 1)
		FoeOps.Op.MOD_INSTRUCTION:
			if not _mod_instruction(ctx, next, _byte(at + 1), _byte(at + 2)):
				return false
	return fault.is_empty()


# --- helpers for the opcodes ---------------------------------------------------

## RET: finish an interrupt (restore everything) or return from a HANDLER subroutine.
func _return_from_script() -> void:
	if interrupted:
		interrupted = false
		pc = _saved_pc
		x = _saved_x
		y = _saved_y
		frame = _saved_frame
		flip = _saved_flip
		jumped = true
	else:
		pc = _return_pc


## LOOPn (update_animals 0x41ed0c, asm 0x41f080-0x41f0cf): every visit computes
## counter - 1. Result 0: the loop is over, the counter is stored as 0 and the script
## falls through. Otherwise the new value is stored, but a NEGATIVE one is replaced by
## `count`, and the script jumps back. The stored counter starts at 0, so the first visit
## computes -1, loads `count` and jumps back without counting: the body runs count + 1
## times (count 0 never ends, but no stored script uses it). The counter is 16 bits wide.
func _loop(counter: int, next: int, offset: int, count: int) -> void:
	var value: int = _counters[counter] - 1
	if value == 0:
		_counters[counter] = 0
		return
	_counters[counter] = _to_i16(value) if value >= 0 else _to_i16(count)
	pc = next + offset


static func _to_i16(value: int) -> int:
	value &= 0xFFFF
	return value - 65536 if value >= 32768 else value


## IF_...: if the condition is false, skip the instruction that follows.
func _if(ctx: Context, next: int, condition: bool) -> void:
	if condition:
		return
	var following := _byte(next)
	if not FoeOps.is_valid(following) or (following == FoeOps.Op.MOD_INSTRUCTION and not ctx.runs_mod_instructions()):
		_fail("unknown opcode %d after a condition at %d%s" % [following, next, _no_mod_instruction(following, next)])
		return
	pc = next + 1 + FoeOps.OPERAND_COUNT[following]


## "sector 7: " for a creature made from a sector's data, "" for one made by hand (a tool, a test).
func _where() -> String:
	return "sector %d: " % sector_index if sector_index >= 0 else ""


## What a fault at `at` says more when the opcode is `Mod_Instruction` with no mod to give it a meaning: which number, and why it is unknown.
func _no_mod_instruction(opcode: int, at: int) -> String:
	if opcode != FoeOps.Op.MOD_INSTRUCTION:
		return ""
	return " (Mod_Instruction %d: no mod of this run defines creature instructions, so it is no instruction)" % _byte(at + 1)


## MOD_INSTRUCTION: the campaign's mod says what instruction `number` does with `value` (`RuleHooks.creature_instruction`: the effect is plain data the game has
## validated, `{}` when no mod defines the number or the call faulted: then nothing happens and the script goes on). The effects, each optional: `condition` (false: skip the
## next instruction, as an `If_`), `set_flags` and `clear_flags` (bit masks of the 16 global flags), `frame` (the picture, kept inside the frame range as `Move_Foe_To_XY` does, bit 7 mirrors), `dx` and `dy` (a move in 2-pixel
## steps like `Move_Foe_Relative_XY`, which ends the turn), `end_turn` (ends the turn). Returns false when the creature's turn is over.
func _mod_instruction(ctx: Context, next: int, number: int, value: int) -> bool:
	if not ctx.hooks.has_instruction(number):
		ctx.trouble.tell("[rules] %sfoe %d runs Mod_Instruction %d, which no mod of this run defines (campaign '%s'); the instruction does nothing and the script goes on" % [
				_where(), index, number, ctx.hooks.campaign_id])
		return true
	var effect := ctx.hooks.creature_instruction(number, value, self, ctx)
	if effect.has("condition"):
		_if(ctx, next, effect["condition"])
	if effect.has("set_flags") or effect.has("clear_flags"):
		ctx.semaphore = (ctx.semaphore | int(effect.get("set_flags", 0))) & ~int(effect.get("clear_flags", 0))
	if effect.has("frame"):
		_set_picture_clamped(effect["frame"])
	var dx: int = effect.get("dx", 0)
	var dy: int = effect.get("dy", 0)
	if dx != 0 or dy != 0:
		x += dx * 2
		y += dy * 2
		return false
	return not effect.get("end_turn", false) and fault.is_empty()


## SLEEP_FOE / WAKE_FOE. Bit 7 of the operand means "relative to this creature".
## SLEEP_FOE also ends the interrupt of the creature RUNNING it, whichever creature it
## names (the original zeroes the running creature's saved pc first): nothing is
## restored, the creature just carries on from where the interrupt script has got to.
## WAKE_FOE leaves the interrupt alone. The interrupt is cleared before the target is
## looked up, as in the original; a missing target faults the creature anyway.
func _set_dormant(ctx: Context, operand: int, sleep: bool) -> void:
	if sleep:
		interrupted = false
	var target := operand
	if operand & 0x80:
		var offset := operand & 0x7F
		target = index + (offset - 128 if offset >= 64 else offset)    # 7-bit signed
	if target < 0 or target >= ctx.foes.size():
		_fail("creature %d does not exist (SLEEP/WAKE)" % target)
		return
	ctx.foes[target].dormant = sleep


## SET_FRAME / SET_POS: low 7 bits are the picture, bit 7 mirrors it.
func _set_picture(value: int) -> void:
	frame = value & 0x7F
	flip = (value & 0x80) != 0


## SET_POS / SET_POS_SCREEN: the picture (low 7 bits) is clamped into FRAME_RANGE:
## below min -> min, above max -> max. Bit 7 mirrors it.
func _set_picture_clamped(value: int) -> void:
	flip = (value & 0x80) != 0
	var picture := value & 0x7F
	if picture < frame_min:
		frame = frame_min
	elif frame_max < picture:
		frame = frame_max
	else:
		frame = picture


## MOVE_REL: bit 7 sets the mirror flag, the low 7 bits are added to the picture
## number; a result below FRAME_RANGE's min wraps to its max, one above max wraps to min.
## An increment of 0 leaves the picture alone.
func _advance_picture(value: int) -> void:
	flip = (value & 0x80) != 0
	var increment := value & 0x7F
	if increment == 0:
		return
	var picture := frame + increment
	if picture < frame_min:
		frame = frame_max
	elif frame_max < picture:
		frame = frame_min
	else:
		frame = picture


# --- reading the script --------------------------------------------------------

func _byte(address: int) -> int:
	var i := address - _base
	if i < 0 or i >= _script.size():
		_fail("script read outside the buffer at %d" % address)
		return 0
	return _script[i]


func _i8(address: int) -> int:
	var v := _byte(address)
	return v - 256 if v >= 128 else v


func _u16(address: int) -> int:
	return _byte(address) | (_byte(address + 1) << 8)


func _i16(address: int) -> int:
	var v := _u16(address)
	return v - 65536 if v >= 32768 else v


func _fail(message: String) -> void:
	if fault.is_empty():
		fault = "foe %d: %s" % [index, message]
