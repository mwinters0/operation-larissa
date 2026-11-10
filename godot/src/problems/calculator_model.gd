class_name CalculatorModel
extends RefCounted
## The brain of the on-screen calculator: key presses in, display text and number out.
##
## Teaches: separating a widget's LOGIC from its looks. `Calculator` (the scene) only turns
## button clicks and keyboard events into `press("7")` calls and shows `display_text()`;
## everything that needs to be right is here and is unit tested without any UI.
##
## Keys (DESIGN 5.2): digits, `.`, `+ - * /`, `=`, `F` fraction entry, `N` negate,
## `S` store, `R` recall, `C` clear (once: the entry; twice: everything).
##
## Fraction entry (`GetNumber` (0x41fb34)): digits typed BEFORE the first `F` are the whole part (none = 0; the
## original accepts `F` only after at most two characters of it, sign included, and not after a decimal point), the
## next digits (at most 2) are the numerator, `/` switches to the denominator (at most 3 digits; a second `F` does
## nothing). So `3 F 1 / 4` is 3 1/4 and `F 3 / 4` is 3/4.
##
## Limits of the original: 9 digits, and three messages (`Notice`) instead of an error on the display: division by zero,
## a result that is too big, or an operator / Enter pressed in the middle of a fraction. `press` returns the notice
## for the caller to show as a dialog (`ShowCalcNoticeDialog` (0x420d8f)); the model has no UI.

## The range of a result: `NormalizeDecimal` (0x427fe8) accepts -99999999 .. 999999999 (the sign takes a digit) and
## reports anything else as "too large" (`NumberValue.normalize_decimal`, `NumberValue.MANTISSA_MIN` / `MANTISSA_MAX`).
## `F` is only accepted while the whole part, sign included, has at most this many characters (0x41ff9f).
const MAX_WHOLE_BEFORE_FRACTION := 2
## How long a pressed key stays lit and the calculator takes no input: `set_alarm(0, 12)` in `GetNumber` (0x41fb34) / `BlinkButton`
## (0x41b411) = 12 ticks of 1/73 s (`calculator.key_flash_ticks` of `data/rules/durations.json`, `Durations`). The widget (`Calculator`) is
## told this number and turns it into seconds for its timer.
static func key_flash_ticks() -> int:
	return maxi(Durations.at("calculator.key_flash_ticks"), 0)


## What `press` can ask the screen to tell the player. The numbers are the original's `kind` argument of
## `ShowCalcNoticeDialog` (0x420d8f): -1 = the "Fraction Mode" help, 0-2 = "Calculator Error" with message 0-2 of
## bundle 0xf5 (texts 10174-10176). NONE is ours.
enum Notice {
	NONE = -2,
	FRACTION_HELP = -1,
	DIVIDE_BY_ZERO = 0,
	TOO_LARGE = 1,
	FRACTION_OPERATOR = 2,
}

## Text of the number being typed (decimal mode) or its whole part (fraction mode).
var _whole: String = ""
var _numerator: String = ""
var _denominator: String = ""
## 0 = typing a plain number, 1 = typing the numerator, 2 = typing the denominator.
var _fraction_stage: int = 0
var _negative: bool = false
var _typing: bool = false            # is there an entry being typed?

## The running result and the operator waiting for its second number ("" = none).
var _accumulator: NumberValue = NumberValue.decimal(0)
var _pending_operator: String = ""
var _memory: NumberValue = NumberValue.decimal(0)
var _memory_stored: bool = false
## C pressed twice in a row clears everything.
var _last_key_was_clear: bool = false
## `GetAnswer`'s `bVar2`: the display holds a RESULT (after Enter, =, N, S, R or the first C), not an entry being typed.
## The next entry key then starts a fresh entry, and an operator works on the displayed number; while it is false an
## operator, = or Enter needs a digit of the entry first (`GetNumber` state 0 ignores them otherwise).
var _result_shown: bool = false
var _was_result_shown: bool = false        # the same flag as it was when the current key arrived
var _digits_typed: bool = false            # `EntryWholeStart` < 9: at least one digit in the entry
## After `press("Enter")`: the number is to be submitted (Enter was not ignored and caused no notice).
var submit_ready: bool = false


## One key press. `key` is a single character of "0123456789.+-*/=FNSRC". Returns the `Notice` the key caused
## (`Notice.NONE` almost always).
func press(key: String) -> Notice:
	var was_clear := _last_key_was_clear
	_last_key_was_clear = false
	_was_result_shown = _result_shown
	_result_shown = false
	submit_ready = false
	if key.length() == 1 and key >= "0" and key <= "9":
		_digit(key)
		return Notice.NONE
	match key:
		".":
			_point()
		"+", "-", "*", "/":
			return _operator(key)
		"=":
			return _equals()
		"Enter":
			return _enter()
		"F":
			_fraction_key()
		"N":
			_negate()
		"S":
			if value() != null:
				_memory = value()
				_memory_stored = not _memory.to_double() == 0.0
				_result_shown = true
		"R":
			_recall()
		"C":
			_clear(was_clear)
			_last_key_was_clear = not was_clear
			_result_shown = not was_clear                    # the second C clears everything and leaves the display fresh
	return Notice.NONE


## Whether the display holds a result (`bVar2`): the calculator then lets a key take effect after its flash (`Calculator`).
func result_shown() -> bool:
	return _result_shown


## Keys that start or continue an entry (`IsCalcEntryKey` (0x420d46)); every other key is a command.
static func is_entry_key(key: String) -> bool:
	return key == "." or key == "F" or (key.length() == 1 and key >= "0" and key <= "9")


## The number the calculator holds right now (what the Enter key submits), or null while
## a fraction is unfinished.
func value() -> NumberValue:
	if _typing:
		return _entry_value()
	return _accumulator


## What the display shows.
func display_text() -> String:
	if _typing:
		var sign_text := "-" if _negative else ""
		if _fraction_stage == 0:
			return sign_text + (_whole if not _whole.is_empty() else "0")
		# `FormatEntryText` (0x4208d9): the fraction right to left, then a space and the whole part, unless it is a
		# single 0; an empty numerator reads "0" when there is no whole part either (the buffer starts as " 0")
		var text := _numerator
		if _fraction_stage == 2:
			text = "%s/%s" % [_numerator, _denominator]
		elif _numerator.is_empty() and _whole.is_empty():
			text = "0"
		if not _whole.is_empty():
			text = "%s %s" % ["" if _whole == "0" else _whole, text]
		return sign_text + text
	return _accumulator.to_text()


## The operator waiting for its second number ("+", "-", "*", "/" or ""), shown on the display.
func pending_operator() -> String:
	return _pending_operator


## True once `S` stored a number (the display shows the memory marker).
func has_memory() -> bool:
	return _memory_stored


## True while the player is in the middle of typing a fraction.
func in_fraction_mode() -> bool:
	return _typing and _fraction_stage > 0


# --- key handlers ---------------------------------------------------------------

func _digit(key: String) -> void:
	if not _typing or _was_result_shown:
		_start_entry()
	_digits_typed = true
	match _fraction_stage:
		0:
			if _whole.replace(".", "").length() < NumberValue.MAX_DIGITS:
				_whole += key
		1:
			if _numerator.length() < NumberValue.MAX_NUMERATOR_DIGITS:
				_numerator += key
		_:
			if _denominator.length() < NumberValue.MAX_DENOMINATOR_DIGITS:
				_denominator += key


func _point() -> void:
	if not _typing or _was_result_shown:
		_start_entry()
	if _fraction_stage == 0 and not "." in _whole:
		_whole += "." if not _whole.is_empty() else "0."


## `F`: starts a fraction. `GetNumber` (0x41fb34) takes it only while no decimal point was typed and the whole part
## (sign included) is at most two characters; typed again inside a fraction it does nothing.
func _fraction_key() -> void:
	if not _typing or _was_result_shown:
		_start_entry()
	if _fraction_stage == 0 and not "." in _whole and _whole.length() + (1 if _negative else 0) <= MAX_WHOLE_BEFORE_FRACTION:
		_fraction_stage = 1


## `/` inside a fraction: from the numerator on to the denominator (needs a numerator digit; otherwise nothing).
func _fraction_bar() -> void:
	if _fraction_stage == 1 and not _numerator.is_empty():
		_fraction_stage = 2


## + - * / while a number is typed or shown. Inside a fraction `GetNumber` refuses: in the numerator everything but `/`,
## in the denominator everything until it holds a usable one (a first digit that is not 0).
func _operator(key: String) -> Notice:
	if _fraction_stage == 1 and key == "/":
		_fraction_bar()
		return Notice.NONE
	if in_fraction_mode() and _entry_value() == null:
		return Notice.FRACTION_OPERATOR
	if _ignored_without_digits():
		return Notice.NONE
	if _typing:
		var notice := _apply_pending(_entry_value())
		if notice != Notice.NONE:
			return notice
		_typing = false
	_pending_operator = key
	return Notice.NONE


## `GetNumber` state 0 does nothing for + - * / = and Enter until a digit was typed, unless a result is on the display.
func _ignored_without_digits() -> bool:
	return not _was_result_shown and not in_fraction_mode() and not (_typing and _digits_typed)


func _equals() -> Notice:
	if in_fraction_mode() and _entry_value() == null:
		return Notice.FRACTION_OPERATOR
	if _ignored_without_digits():
		return Notice.NONE
	if _typing:
		var notice := _apply_pending(_entry_value())
		if notice != Notice.NONE:
			return notice
		_typing = false
	_pending_operator = ""
	_result_shown = true
	return Notice.NONE


## Enter is `=` first (`GetAnswer` case 1 falls into case 6), then the number is submitted: unless Enter was ignored
## (nothing typed yet) or refused with a notice.
func _enter() -> Notice:
	var ignored := _ignored_without_digits()
	var notice := _equals()
	submit_ready = notice == Notice.NONE and not ignored
	return notice


func _negate() -> void:
	if _typing:                                  # an entry being typed, or a recalled number
		_negative = not _negative
		_result_shown = _was_result_shown
	else:
		_accumulator = negated(_accumulator)
		_typing = false
		_result_shown = true


func _recall() -> void:
	# The stored number becomes the entry, as if it had just been typed.
	_start_entry()
	_digits_typed = true
	_result_shown = true
	_negative = _memory.to_double() < 0.0
	if _memory.is_fraction():
		_whole = str(absi(_memory.whole)) if _memory.whole != 0 else ""
		_numerator = str(absi(_memory.numerator))
		_denominator = str(_memory.denominator)
		_fraction_stage = 2
	else:
		_whole = NumberValue.decimal(absi(_memory.raw), _memory.decimals).to_text()


func _clear(second_time: bool) -> void:
	if _typing:
		_typing = false
		_reset_entry()
	if second_time:
		_accumulator = NumberValue.decimal(0)
		_pending_operator = ""


# --- helpers ------------------------------------------------------------------------

func _start_entry() -> void:
	_reset_entry()
	_typing = true


func _reset_entry() -> void:
	_whole = ""
	_numerator = ""
	_denominator = ""
	_fraction_stage = 0
	_negative = false
	_digits_typed = false


## The typed entry as a NumberValue; null for an unfinished fraction.
func _entry_value() -> NumberValue:
	if _fraction_stage == 0:
		var typed := NumberValue.parse(_whole if not _whole.is_empty() else "0")
		if typed == null:
			return null
		return NumberValue.decimal(-typed.raw if _negative else typed.raw, typed.decimals)
	if _numerator.is_empty() or _denominator.is_empty() or _denominator.begins_with("0"):
		return null                            # the original checks the first digit of the denominator, so "05" is refused too
	var whole_part := _whole.to_int() if not _whole.is_empty() else 0
	var numerator_part := _numerator.to_int()
	if _negative:
		whole_part = -whole_part
		numerator_part = -numerator_part
	return NumberValue.fraction(whole_part, numerator_part, _denominator.to_int())


## Combines the running result with a new number using the waiting operator. A division by zero or a result that is
## too big clears the calculator like the original (`GetAnswer` (0x41ade0): `Zero`, operators dropped; only the memory
## stays) and returns the notice to show.
func _apply_pending(next: NumberValue) -> Notice:
	if _pending_operator.is_empty():
		_accumulator = next               # no operation: the typed number (and its kind) is kept
		return Notice.NONE
	if _pending_operator == "/" and is_zero_approx(next.to_double()):
		_reset_after_notice()
		return Notice.DIVIDE_BY_ZERO
	var result := calculate(_accumulator, next, _pending_operator)
	if result == null:
		_reset_after_notice()
		return Notice.TOO_LARGE
	_accumulator = result
	return Notice.NONE


## One arithmetic step the way NUMBERS.C does it: `Add` (0x4284f3), `Subtract` (0x4285fd), `Multiply` (0x4286e0),
## `Divide` (0x4287cb). `UnifyNumberKinds` (0x428264) first: two decimals stay decimals; two fractions stay a fraction
## (`AddFractions` (0x4284bf) ... with `NormalizeFraction` (0x4281b3)); a fraction with a decimal becomes a fraction
## when the decimal is a whole number from -9 to 99, otherwise both are decimals. Returns null when the result does
## not fit ("too large"): a decimal outside `MIN_VALUE` .. `MAX_VALUE`, a fraction whose whole part is outside -9 .. 99,
## whose numerator is above 99 or whose denominator is above 999.
static func calculate(left: NumberValue, right: NumberValue, operator: String) -> NumberValue:
	if left.is_fraction() != right.is_fraction():
		var decimal_side := right if left.is_fraction() else left
		if decimal_side.decimals == 0 and decimal_side.raw >= -9 and decimal_side.raw <= 99:
			var as_fraction := NumberValue.fraction(decimal_side.raw, 0, 1)
			left = left if left.is_fraction() else as_fraction
			right = right if right.is_fraction() else as_fraction
	if left.is_fraction() and right.is_fraction():
		return _calculate_fractions(left, right, operator)
	var result := _calculate_decimals(_as_decimal(left), _as_decimal(right), operator)
	return null if result.is_overflow() else result


## A fraction that meets a decimal that is not a small whole number becomes a decimal first: `FractionToDecimal`
## (0x42812c) = `NormalizeDecimal` (0x427fe8) of whole + numerator / denominator (so 1/3 is 0.333333333 from then on).
static func _as_decimal(v: NumberValue) -> NumberValue:
	if v.is_fraction():
		return NumberValue.normalize_decimal(0, v.to_double())
	return v


## `AddDecimals` (0x428463), `SubtractDecimals` (0x42856d), `MultiplyDecimals` (0x428677), `DivideDecimals` (0x42875a):
## the mantissas (raw) are doubles, the exponents (decimals) are aligned for + and -, added for *, subtracted for /,
## then `NumberValue.normalize_decimal`. The result has `decimals < 0` when it is too large.
static func _calculate_decimals(a: NumberValue, b: NumberValue, operator: String) -> NumberValue:
	var exponent := 0
	var value := 0.0
	var a_mantissa := float(a.raw)
	var b_mantissa := float(b.raw)
	match operator:
		"+", "-":
			exponent = maxi(a.decimals, b.decimals)
			for _i in range(exponent - a.decimals):
				a_mantissa *= 10.0
			for _i in range(exponent - b.decimals):
				b_mantissa *= 10.0
			value = a_mantissa + b_mantissa if operator == "+" else a_mantissa - b_mantissa
		"*":
			exponent = a.decimals + b.decimals
			value = a_mantissa * b_mantissa
		"/":
			exponent = a.decimals - b.decimals
			value = a_mantissa / b_mantissa if b_mantissa != 0.0 else 0.0
	return NumberValue.normalize_decimal(exponent, value)


static func _calculate_fractions(a: NumberValue, b: NumberValue, operator: String) -> NumberValue:
	var whole_part := 0
	var numerator_part := 0
	var denominator_part := a.denominator * b.denominator
	match operator:
		"+":
			whole_part = a.whole + b.whole
			numerator_part = a.numerator * b.denominator + b.numerator * a.denominator
		"-":
			whole_part = a.whole - b.whole
			numerator_part = a.numerator * b.denominator - b.numerator * a.denominator
		"*":
			whole_part = a.whole * b.whole
			numerator_part = a.whole * a.denominator * b.numerator + b.whole * b.denominator * a.numerator + a.numerator * b.numerator
		"/":                                      # both as improper fractions
			numerator_part = (a.whole * a.denominator + a.numerator) * b.denominator
			denominator_part = (b.whole * b.denominator + b.numerator) * a.denominator
	return _normalize_fraction(whole_part, numerator_part, denominator_part)


## `NormalizeFraction` (0x4281b3): carry the numerator into the whole part, give whole part and numerator the same sign,
## cancel by the greatest common divisor, then check the limits. (The original does not fix a negative denominator, which
## only a division by a negative fraction can make; here the sign moves to the numerator.)
static func _normalize_fraction(whole_part: int, numerator_part: int, denominator_part: int) -> NumberValue:
	var reduced := _reduce_fraction(whole_part, numerator_part, denominator_part)
	if reduced == null:
		return null
	if reduced.whole < -9 or reduced.whole > 99 or reduced.numerator < -99 or reduced.numerator > 99 or reduced.denominator > 999:
		return null
	return reduced


## The first part of `NormalizeFraction`, without the limits (null for a zero denominator, the original's "error").
@warning_ignore("integer_division")
static func _reduce_fraction(whole_part: int, numerator_part: int, denominator_part: int) -> NumberValue:
	if denominator_part == 0:
		return null
	if denominator_part < 0:
		numerator_part = -numerator_part
		denominator_part = -denominator_part
	whole_part += numerator_part / denominator_part                  # integer division truncates, like C
	numerator_part = numerator_part % denominator_part
	while whole_part < 0 and numerator_part > 0:
		whole_part += 1
		numerator_part -= denominator_part
	while numerator_part < 0 and whole_part > 0:
		whole_part -= 1
		numerator_part += denominator_part
	var divisor := _gcd(denominator_part, absi(numerator_part))
	numerator_part /= divisor
	denominator_part /= divisor
	return NumberValue.fraction(whole_part, numerator_part, denominator_part)


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a


func _reset_after_notice() -> void:
	_accumulator = NumberValue.decimal(0)
	_pending_operator = ""
	_typing = false
	_reset_entry()


## `Negate` (0x428845), the `N` key on a result: a decimal has its mantissa negated and goes through `NormalizeDecimal`
## again; a fraction has whole and numerator negated and goes through `NormalizeFraction` (0x4281b3) (which also cancels it).
## The original IGNORES the "too large" those return (`GetAnswer` (0x41ade0) calls it at 0x41b1a3 and shows the number
## as it is), so `N` on 999999999 (or any positive result above 99999999, the negative limit) leaves a number with
## exponent -1 and the mantissa one digit short: the display shows -100000000 (or -99999999 for 999999990) while the value
## is still -1000000000 (or -999999990); a fraction whose whole part is 99 keeps -99.
static func negated(v: NumberValue) -> NumberValue:
	if v.is_fraction():
		var reduced := _reduce_fraction(-v.whole, -v.numerator, v.denominator)
		return reduced if reduced != null else v
	return NumberValue.normalize_decimal(v.decimals, -float(v.raw))
