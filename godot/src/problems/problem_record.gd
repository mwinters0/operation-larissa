class_name ProblemRecord
extends RefCounted
## One stored problem of the original game, decoded from its flat integer form.
##
## Teaches: wrapping a compact data format (a PackedInt64Array) in a small class with
## typed accessors, so the rest of the code can say `record.int_at(3)` or
## `record.number_at(7)` and never think about how the numbers are packed.
##
## A record is a list of numbered FIELDS in file order (DESIGN 5.4 explains what
## f0, f1 ... mean for each of the 34 types). `kinds` has one character per field:
##   c  u8       b  signed byte       w  u16          -> one int in the flat array
##   n  number                                        -> four ints (kind, a, b, c)
## For an `n` field: kind 0 = decimal (raw, decimals, 0), kind 1 = fraction (whole, num, den + 65536 * the byte after the
## denominator, which the original never reads and is 0 in nearly all records), kind 2 = unused leftover bytes of the
## original authoring tool (the 16-bit kind that is neither 0 nor 1, bytes 2-5 as one int, byte 6; reads as 0). The flat form
## keeps every byte of the original's table so that `ProblemType.encode_table()` can give it back.

var kinds: String
var flat: PackedInt64Array
## Index into `flat` where each field starts.
var _offsets: PackedInt32Array = PackedInt32Array()


func _init(field_kinds: String, flat_values: PackedInt64Array) -> void:
	kinds = field_kinds
	flat = flat_values
	var at := 0
	for k in kinds:
		_offsets.append(at)
		at += 4 if k == "n" else 1


## Field `i` as a whole number. A number field is rounded to the nearest whole number, a tie to the even one:
## `NumberToInt` (0x4283bc), which the original's text functions use (`GetAccessHintSubst` 0x417b40 for the sequence's
## step: 0.73 -> 1, 1.5 -> 2, 2.5 -> 2).
func int_at(i: int) -> int:
	if kinds[i] == "n":
		return number_at(i).to_int()
	return flat[_offsets[i]]


## Field `i` as a NumberValue. Plain integer fields become decimals without digits.
func number_at(i: int) -> NumberValue:
	var at := _offsets[i]
	if kinds[i] != "n":
		return NumberValue.decimal(flat[at])
	match flat[at]:
		0:
			return NumberValue.decimal(flat[at + 1], flat[at + 2])
		1:
			return NumberValue.fraction(flat[at + 1], flat[at + 2], flat[at + 3] & 0xFFFF)
		_:
			return NumberValue.decimal(0)


## Field `i` as a float.
func value_at(i: int) -> float:
	return number_at(i).to_double()


## The number kind of a number field (false for integers and unused fields).
func is_fraction_at(i: int) -> bool:
	return kinds[i] == "n" and flat[_offsets[i]] == 1
