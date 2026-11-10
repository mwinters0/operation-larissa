class_name PracticeSet
extends RefCounted
## Which math problems one Math Practice set contains, in which order. Pure logic, no nodes.
##
## Teaches: a rule learned from decompiled code and written as a small testable function. The original
## (`do_math_practice`, PRACTICE.C) builds a set from three choices of the player:
##
##   * "5 Math Problems"      five problem TYPES picked at random: `rand() % 33 + 1`, kept when the type has
##                            stored problems at the chosen level, repeats allowed (there is no check)
##   * "10 Mental Math"       five combination locks (type 0); a lock holds two sums, so ten problems and no
##                            calculator
##   * "All Math Problems"    every type 1-33 that exists at the level, in order (the lock is not part of it), and then the types a pack of the chain adds (`Catalog.problem_type_ids`)
##
## The problem itself (which stored record of the type) is then chosen exactly as in the game proper
## (`ProblemFactory.make`). The ids are the problem TYPES 0-33; "mental" is just the lock. The original has one more
## switch, `PracticeRecordTweaks`, that would replace some records at some levels; it is read from the string
## "FALSE" in the game's own resources, so it is never on, and the port leaves it out.

enum Kind { FIVE, MENTAL, ALL }

const FIVE_PROBLEMS := 5
const LOCKS := 5
const LOCK_TYPE := 0
const FIRST_TYPE := 1
const LAST_TYPE := 33


## Does problem type `type_id` have stored problems at `level` (0-3)? That is the original's test, a table of
## record counts read from the data at start-up.
static func is_available(type_id: int, level: int) -> bool:
	var type := Catalog.problem_type(type_id)
	return type != null and type.record_count(level) > 0


## The types 1-33 that appear at `level`, in order, and then those the chain's packs add.
static func available_types(level: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for type_id in Catalog.problem_type_ids():
		if type_id >= FIRST_TYPE and is_available(type_id, level):
			result.append(type_id)
	return result


## The problem types of a set, in the order they are played. `rng` is optional (tests pass a seeded one).
static func build(kind: Kind, level: int, rng: RandomNumberGenerator = null) -> PackedInt32Array:
	var order := PackedInt32Array()
	match kind:
		Kind.FIVE:
			var random := rng if rng != null else RandomNumberGenerator.new()
			while order.size() < FIVE_PROBLEMS:
				var type_id := random.randi() % LAST_TYPE + FIRST_TYPE
				if is_available(type_id, level):
					order.append(type_id)
		Kind.MENTAL:
			for i in LOCKS:
				order.append(LOCK_TYPE)
		Kind.ALL:
			order = available_types(level)
	return order


## How many problems the player will answer: a lock counts as two (its two combination numbers).
static func problem_count(order: PackedInt32Array) -> int:
	var count := 0
	for type_id in order:
		count += 2 if type_id == LOCK_TYPE else 1
	return count
