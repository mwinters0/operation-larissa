class_name HookState
extends RefCounted
## What a rule hook of a mod is TOLD: PLAIN DATA the rules build from their own objects (`RuleHooks` asks, then the mod side freezes it and hands it over). One builder per hook point, each a function of the
## rules' state alone: numbers, strings, `Vector2i` and Arrays of them, never an object, a node, a clock or a dice. A hook is told what it may look at and nothing else (no oxygen, no run, no pack, no other creature),
## so what it answers is a function of this snapshot and of the memory the game hands back (`RuleHooks`), and the same snapshot is the same answer on every machine and in every test.
##
## Teaches: the same lesson as `SkinState` and `ProblemState` for a script that decides something: a copy of the state made by one builder from its owner, as plain values.

## The fields of the problem's record in order: a whole number for a byte or a word, `{"text", "value", "fraction"}` for a number (the text the way the game prints it).
static func fields(problem: ProblemInstance) -> Array:
	var found: Array = []
	for i in problem.type.field_kinds.length():
		if problem.record.kinds[i] != "n":
			found.append(problem.record.int_at(i))
		else:
			var number := problem.record.number_at(i)
			found.append({"text": number.to_text(), "value": number.to_double(), "fraction": problem.record.is_fraction_at(i)})
	return found


## The answer check of `problem`: the type, the level, the record's fields and what was typed. (No memory: an answer is judged from this alone.)
static func answer(problem: ProblemInstance, typed: NumberValue) -> Dictionary:
	return {
		"type": problem.type.id,
		"level": problem.level,
		"fields": fields(problem),
		"typed": {"text": typed.to_text(), "value": typed.to_double(), "fraction": typed.is_fraction()},
	}


## The creature instruction `number` with operand `value`, run by the creature `vm` in tick `tick` of this load (`RuleHooks.tick`).
static func creature(number: int, value: int, vm: FoeVM, ctx: FoeVM.Context, tick: int) -> Dictionary:
	return {
		"number": number,
		"value": value,
		"tick": tick,
		"creature": vm.index,
		"position": Vector2i(vm.x, vm.y),
		"frame": vm.frame,
		"mirrored": vm.flip,
		"screen": vm.screen,
		"shown_screen": ctx.current_screen,
		"sub": Vector2i(ctx.sub_x, ctx.sub_y),
		"flags": ctx.semaphore,
	}


## The sub's turn in tick `tick` of this load, after the sub moved: where it is (the original's SubX / SubY), how fast (1/8 pixel per tick), the hands of the player, and the bounds the answer is held to.
static func sub(model: SubModel, input: InputSnapshot, sector: int, screen: int, tick: int) -> Dictionary:
	return {
		"tick": tick,
		"sector": sector,
		"screen": screen,
		"position": model.original_position(),
		"velocity": model.velocity_units,
		"cell": model.cell,
		"invulnerability": model.invulnerability,
		"steer": input.steer if input != null else Vector2i.ZERO,
		"fire": input.fire_presses if input != null else 0,
		"max_velocity": Vector2i(model.tuning.max_speed_x_units, model.tuning.max_speed_y_units),
		"max_invulnerability": model.tuning.invulnerability_ticks,
	}
