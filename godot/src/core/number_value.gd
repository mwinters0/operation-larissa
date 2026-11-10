class_name NumberValue
extends RefCounted
## A number as the original game stores and types it: either a DECIMAL ("2.50") or a
## mixed FRACTION ("1 3/4"). The original called it a CompactNumber.
##
## Teaches: a small value class instead of a bare `float`. The decimal remembers how
## many digits it shows (2.50 prints with two), a fraction remembers its numerator and
## denominator (2/4 is NOT reduced when it is printed), and yet two numbers are
## *equal* when their values agree to 1e-10, so 1/2 == .5 == 0.50 == 2/4.
## The kind (decimal or fraction) is still kept, because a few problems demand
## "type it as a fraction" (see AnswerChecker).
##
## Limits of what a player can type (DESIGN 5.2 item 7): a decimal has at most 9
## digits; a fraction has a whole part of up to 9 digits, a numerator of up to 2
## digits and a denominator of up to 3 digits. No units, no rounding.

enum Kind { DECIMAL, FRACTION }

## Two numbers are equal when they differ by less than this (NumberCmp of the original).
const EQUAL_EPSILON := 1e-10
const MAX_DIGITS := 9
const MAX_NUMERATOR_DIGITS := 2
const MAX_DENOMINATOR_DIGITS := 3

var kind: Kind = Kind.DECIMAL
## Decimal: value = raw / 10^decimals, `decimals` is how many digits follow the point.
var raw: int = 0
var decimals: int = 0
## Fraction: value = whole + numerator / denominator. For a negative mixed number
## the whole part AND the numerator are negative (-6 2/3 is whole -6, numerator -2).
## A negative fraction without a whole part has whole 0 and a negative numerator.
var whole: int = 0
var numerator: int = 0
var denominator: int = 1


static func decimal(raw_value: int, exponent: int = 0) -> NumberValue:
	var n := NumberValue.new()
	n.kind = Kind.DECIMAL
	n.raw = raw_value
	n.decimals = exponent
	return n


static func fraction(whole_part: int, numerator_part: int, denominator_part: int) -> NumberValue:
	var n := NumberValue.new()
	n.kind = Kind.FRACTION
	n.whole = whole_part
	n.numerator = numerator_part
	n.denominator = denominator_part
	return n


## `RoundHalfEven` (0x427f20): `x` rounded to a whole number, an exact tie (x.5) going to the EVEN neighbour:
## 0.5 -> 0, 1.5 -> 2, 2.5 -> 2, -0.5 -> 0, -1.5 -> -2, -2.5 -> -2. Everything else rounds to the nearest whole number.
## The original builds it from the C runtime's `fmod`, `ceil` and `floor` (x87 doubles) and so does this, with the same
## branches: for x >= 0 the remainder `fmod(x, 2)` below 1 says the whole number under x is even, so `ceil(x - 0.5)` (a tie
## goes down); at 1 or more it is odd and `floor(x + 0.5)` (a tie goes up). For x < 0 the same with the limit -1.
## GDScript's own `round` / `roundf` send every tie away from zero and so differ at x.5 exactly.
static func round_half_even(x: float) -> float:
	var parity := fmod(x, 2.0)
	if x < 0.0:                                       # (the original tests `0.0 > x` first)
		if parity < -1.0:
			return ceilf(x - 0.5)
		return floorf(x + 0.5)
	if parity < 1.0:
		return ceilf(x - 0.5)
	return floorf(x + 0.5)


## The low and high end of a decimal mantissa after `NormalizeDecimal` (0x427fe8): the doubles at 0x428118 / 0x428120.
## The sign takes a digit, so a negative number keeps one digit less than a positive one.
const MANTISSA_MIN := -99999999.0
const MANTISSA_MAX := 999999999.0


## `NormalizeDecimal` (0x427fe8), step by step as the original runs it on a decimal "mantissa `value` with `exponent` digits
## after the point" (value = mantissa / 10^exponent); every operation of the original's `Add` / `Subtract` / `Multiply` /
## `Divide` on two decimals ends here. The five loops, all on doubles:
## 1. while exponent <= 9 and the mantissa has a fractional part: exponent + 1, mantissa * 10;
## 2. while exponent < 0: exponent + 1, mantissa * 10;
## 3. while exponent >= 0 and the mantissa is outside MANTISSA_MIN .. MANTISSA_MAX: exponent - 1, mantissa * 0.1
##    (this is the only place a number gets shorter, and why a negative one keeps 8 digits: -1234567.89 = -123456789 at
##    exponent 2 becomes -12345678.9 at exponent 1, then -1234567.9);
## 4. while exponent > 9: exponent - 1, mantissa * 0.1; then the mantissa is rounded with `RoundHalfEven` (0x427f20);
## 5. while exponent > 0 and the mantissa ends in 0: exponent - 1, mantissa * 0.1; then `RoundHalfEven` again.
## It returns 1 ("too large") when the exponent has dropped below 0; the number is then left as it is (exponent -1, the
## mantissa one digit short). Here the result is that number: the error is `decimals < 0`. (The original multiplies by the
## extended-precision constant 0.1 at 0x42810c; dividing by 10 gives the same double except in far-off tie cases.)
static func normalize_decimal(exponent: int, value: float) -> NumberValue:
	var e := exponent
	var m := value
	while e <= 9 and fmod(m, 1.0) != 0.0:
		e += 1
		m *= 10.0
	while e < 0:
		e += 1
		m *= 10.0
	while e >= 0 and (m < MANTISSA_MIN or m > MANTISSA_MAX):
		e -= 1
		m /= 10.0
	while e > 9:
		e -= 1
		m /= 10.0
	m = round_half_even(m)
	while e > 0 and fmod(absf(m), 10.0) < 0.5:
		e -= 1
		m /= 10.0
	m = round_half_even(m)
	return decimal(int(m), e)


## True when `normalize_decimal` reported "too large" for this number (the original's return value 1): exponent below 0.
func is_overflow() -> bool:
	return kind == Kind.DECIMAL and decimals < 0


## A decimal for `value` (a plain number, as if exponent 0): `normalize_decimal` (0x427fe8) with at most 9 digits for a
## positive number and 8 for a negative one (the mantissa range is -99999999 .. 999999999), no trailing zeros, a tie at
## the last digit going to the even digit (12345678.25 -> 12345678.2, 123456788.5 -> 123456788, -1234567.89 ->
## -1234567.9). Used for results that did not come from two decimals and for building test values.
static func from_double(value: float) -> NumberValue:
	return normalize_decimal(0, value)


## Reads a typed answer: "3", "-2.5", ".5", "3/4", "1 3/4", "-1 3/4".
## Returns null for anything else (empty, letters, too many digits, denominator 0).
static func parse(text: String) -> NumberValue:
	var s := text.strip_edges()
	if s.is_empty():
		return null
	var negative := false
	if s.begins_with("-"):
		negative = true
		s = s.substr(1).strip_edges()
	if s.is_empty():
		return null

	if "/" in s:                                         # fraction: "3/4" or "1 3/4"
		var halves := s.split("/")
		if halves.size() != 2:
			return null
		var left := halves[0].strip_edges()
		var den_text := halves[1].strip_edges()
		var whole_text := "0"
		var num_text := left
		if " " in left:
			var parts := left.split(" ", false)
			if parts.size() != 2:
				return null
			whole_text = parts[0]
			num_text = parts[1]
		if not (_is_digits(whole_text, MAX_DIGITS) and _is_digits(num_text, MAX_NUMERATOR_DIGITS)
				and _is_digits(den_text, MAX_DENOMINATOR_DIGITS)):
			return null
		var den := den_text.to_int()
		if den == 0:
			return null
		var whole_value := whole_text.to_int()
		var num_value := num_text.to_int()
		if negative:                                     # both parts carry the sign
			whole_value = -whole_value
			num_value = -num_value
		return fraction(whole_value, num_value, den)

	# decimal: digits with at most one point, at most 9 digits in total
	var point := s.find(".")
	var digits := s.replace(".", "")
	if s.count(".") > 1 or not _is_digits(digits, MAX_DIGITS):
		return null
	var exponent := 0 if point < 0 else s.length() - point - 1
	var value := digits.to_int()
	return decimal(-value if negative else value, exponent)


## The value as a float: whole + numerator / denominator, or raw * 10^-decimals.
func to_double() -> float:
	if kind == Kind.FRACTION:
		return float(whole) + float(numerator) / float(denominator)
	if decimals < 0:                                  # only after a `Negate` overflow (0x428845): mantissa * 10^-decimals
		return float(raw) * pow(10.0, -decimals)
	return float(raw) / pow(10.0, decimals)


## `NumberToInt` (0x4283bc): the value rounded to a whole number with `round_half_even` (2.5 -> 2, 3.5 -> 4, 0.73 -> 1).
func to_int() -> int:
	return int(round_half_even(to_double()))


## Same value (within 1e-10)? The kind is NOT compared here.
func equals(other: NumberValue) -> bool:
	return absf(to_double() - other.to_double()) < EQUAL_EPSILON


func is_fraction() -> bool:
	return kind == Kind.FRACTION


## The text as the original prints it (`NumberToString` 0x4289cc, `CompactNumberToString` 0x428c10): decimals keep their
## digits ("2.50", "0.05"), fractions are "w  n/d" with TWO spaces (0x428b85, 0x428b89), "n/d" (no whole part) or "w" (no
## numerator); a negative mixed number prints as "-6  2/3". Fractions are not reduced. A number being typed on the calculator
## has one space (`FormatEntryText` 0x4208d9, see `CalculatorModel.display_text`); `parse` reads either.
func to_text() -> String:
	if kind == Kind.FRACTION:
		var num_abs := absi(numerator)
		if whole == 0:
			if numerator == 0:
				return "0"
			return "%s%d/%d" % ["-" if numerator < 0 else "", num_abs, denominator]
		if numerator == 0:
			return str(whole)
		return "%d  %d/%d" % [whole, num_abs, denominator]
	if decimals <= 0:
		return str(raw)
	var digits := str(absi(raw)).pad_zeros(decimals + 1)
	var text := digits.substr(0, digits.length() - decimals) + "." + digits.substr(digits.length() - decimals)
	return "-" + text if raw < 0 else text


static func _is_digits(text: String, max_length: int) -> bool:
	if text.is_empty() or text.length() > max_length:
		return false
	for c in text:
		if c < "0" or c > "9":
			return false
	return true
