class_name TestTextTemplate
extends GdUnitTestSuite
## Teaches: testing string substitution, including the original's odd line endings.


func test_slots_are_replaced() -> void:
	assert_str(TextTemplate.render("{0} + {1} = {2}", {0: "1", 1: "2", 2: "3"})).is_equal("1 + 2 = 3")


func test_same_slot_twice() -> void:
	assert_str(TextTemplate.render("{0}/{0}", {0: "7"})).is_equal("7/7")


func test_degree_sign_and_newline_survive() -> void:
	assert_str(TextTemplate.render("{0}°F\nnext", {0: "-10"})).is_equal("-10°F\nnext")


func test_carriage_returns_become_newlines() -> void:
	assert_str(TextTemplate.render("a\r\nb\rc", {})).is_equal("a\nb\nc")


## G35: a raw 0xFF is the underline toggle (`ConvertTextMarkup` 0x415ebf -> FF 02 FF), not an answer slot; the next byte
## is ordinary text, so nothing is dropped and no `_____` appears.
func test_a_raw_0xff_underlines_the_rest_and_keeps_the_next_character() -> void:
	assert_str(TextTemplate.render("{0} + ÿ= ", {0: "1"})).is_equal("1 + [u]= [/u]")
	assert_str(TextTemplate.render("{0} + ÿt ", {0: "1"})).is_equal("1 + [u]t [/u]")


func test_a_second_0xff_switches_the_underline_off_again() -> void:
	assert_str(TextTemplate.render("aÿbÿc", {})).is_equal("a[u]b[/u]c")
	assert_str(TextTemplate.render("aÿbÿcÿd", {})).is_equal("a[u]b[/u]c[u]d[/u]")


func test_unfilled_slot_is_detected() -> void:
	assert_bool(TextTemplate.has_unfilled_slot("a {3} b")).is_true()
	assert_bool(TextTemplate.has_unfilled_slot("no slots {here}")).is_false()
	assert_bool(TextTemplate.has_unfilled_slot(TextTemplate.render("{0} {1}", {0: "a"}))).is_true()
