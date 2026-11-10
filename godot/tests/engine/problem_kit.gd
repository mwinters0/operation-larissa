class_name ProblemKit
extends RefCounted
## A TEST helper (batch C): problem types and records made by the test itself, for the tests that are about a RULE (how a typed answer is compared,
## which text a record picks, how a diagram counts its copies) and not about the pack's content. The values are the test's own and stated in the test;
## nothing here reads a pack. Tests that need the pack's own problems ask `ProblemFactory` / `Catalog.problem_type` (dev's records are in
## `tools/dev_pack/dev_problems.py`).
##
## Teaches: building the data an engine rule works on instead of borrowing it from a game, so the test keeps its meaning when the pack changes.


## A decimal number field: `decimal(4.5)` is the flat form (0, 45, 1, 0), exact to `places` digits.
static func decimal(value: float, places: int = 1) -> Array[int]:
	return [0, roundi(value * pow(10.0, places)), places, 0]


## A fraction number field: `fraction(0, 1, 4)` is 1/4 and `fraction(-6, -2, 3)` is -6 2/3 below zero (whole part, numerator, denominator: the numerator carries the sign too).
static func fraction(whole: int, numerator: int, denominator: int) -> Array[int]:
	return [1, whole, numerator, denominator]


## One flat record of the kinds `kinds` ('c' 'b' 'w' take an int, 'n' takes a `decimal` or `fraction`, flattened in order).
static func flat(parts: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for part: Variant in parts:
		if part is Array:
			out.append_array(PackedInt64Array(part))
		else:
			out.append(int(part))
	return out


## A problem type of the test's own: every level compared by `mode` ("exact", "near", "close", "range", "sum") with the same `tolerance`, the answer in
## field `answer_field`, and `records` (flat arrays from `flat`), all of level 0 unless `levels` says otherwise.
static func type_of(mode: String, kinds: String, answer_field: int, records: Array, tolerance: float = 0.0, kind_checked: bool = false,
		levels: Array = []) -> ProblemType:
	var type := ProblemType.new()
	type.id = 0
	type.title = "Kit type"
	type.compare_mode = mode
	type.field_kinds = kinds
	type.answer_fields = PackedInt32Array([answer_field, answer_field, answer_field, answer_field])
	type.tolerances = PackedFloat64Array([tolerance, tolerance, tolerance, tolerance])
	type.kind_checked_levels = PackedInt32Array([0, 1, 2, 3]) if kind_checked else PackedInt32Array()
	type.levels_available = PackedInt32Array([1, 1, 1, 1])
	for i in records.size():
		var record: PackedInt64Array = records[i]
		type.records.append(record)
		type.record_levels.append(levels[i] if i < levels.size() else 0)
	return type


## The first record of `type` at `level`, as a problem screen sees it.
static func record_of(type: ProblemType, level: int = 0, index: int = 0) -> ProblemRecord:
	return type.record(level, index)


## Does the typed text count as right for the first record of `level`?
static func accepts(type: ProblemType, typed: String, level: int = 0, index: int = 0) -> bool:
	return AnswerChecker.check(type, level, type.record(level, index), NumberValue.parse(typed))


## A copy of the chain's type `type_id` whose records are `records` (flat arrays, all at `level`): the pack's texts, field kinds and rules, the
## test's numbers. The pack's own type is not touched.
static func with_records(type_id: int, records: Array, level: int = 0) -> ProblemType:
	var type := Catalog.problem_type(type_id).duplicate() as ProblemType
	type.records = []
	type.record_levels = PackedInt32Array()
	for record: PackedInt64Array in records:
		type.records.append(record)
		type.record_levels.append(level)
	return type


## A diagram built from a spec the test writes (the vocabulary at the top of `DiagramBase`): the pack's type 6 (three number fields, so its wording
## has what it reads) with `spec` as its diagram, the twelve pictures of the pack's type 3 to draw from, and `numbers` as the record's three decimals.
## The caller frees it (`auto_free`) and, to play an animation, adds it to the tree.
static func diagram_of(spec: Dictionary, numbers: Array = [0, 0, 0], level: int = 0, places: int = 0) -> DiagramBase:
	var type := Catalog.problem_type(6).duplicate() as ProblemType
	type.diagram = spec
	type.art_dir = Catalog.problem_type(3).art_dir
	type.art_files = Catalog.problem_type(3).art_files
	var record := PackedInt64Array()
	for number: float in numbers:
		record.append_array(PackedInt64Array(decimal(number, places)))
	type.records = [record]
	type.record_levels = PackedInt32Array([level])
	return DiagramFactory.create(ProblemInstance.build(type, level, 0))
