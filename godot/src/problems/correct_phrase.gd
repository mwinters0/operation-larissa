class_name CorrectPhrase
extends RefCounted
## The four short phrases of Math Practice for a right answer: "Correct.", "That's right.", "Good answer.", "Very good."
##
## Teaches: a tiny pure helper with an injectable random source. `ShowCorrectPhrase` (0x4235e5) loads the string
## `11110 + rand() % 4` (here `correct_phrase_<n>`) and shows it for 146 ticks (`WaitKeyOrTicks(0x92)`) or until Enter. The game itself shows the
## problem's own success text instead; the phrases belong to practice mode only (`InMathPractice`).

const COUNT := 4                      # `correct_phrase_0` .. `correct_phrase_3`


## One of the four phrases, chosen with `rng` (a test seeds it).
static func pick(rng: RandomNumberGenerator) -> String:
	return Catalog.text(StringName("correct_phrase_%d" % (rng.randi() % COUNT)))
