class_name PromptSender
extends RefCounted
## The little sender picture beside the first line of a problem's prompt: the research ship or the control room.
##
## Teaches: a pure rule class (static functions, no state) that holds one rule of the original, so the screen that
## draws it and the tests that pin it share the same numbers.
##
## Original: `ShowProblemPrompt` (0x4250c3) writes the prompt with `WriteMessageText` (0x4234c0). While the problem was
## asked by a map trigger (`PromptTriggerSlotPlus1` (0x442990) > 0, set by `DoMathProblem` (0x423629) only around
## `ShowProblemPrompt`, never in Math Practice) that goes to `WriteMessageTextWithSender` (0x4233c8):
##   * the picture of `LoadPromptSenderPicture` (0x423378) is drawn masked at (361, 48), 55 x 20 px;
##   * the text up to the first newline (the header, e.g. "Alert:" or "Surface Ship Message:") is drawn BESIDE it at
##     x = 360 + the picture's width rounded down to even = 414, y = 48 (box width 238, so it may wrap);
##   * everything after that newline is drawn from (364, 68) like ordinary message text. Without a newline the whole text
##     goes there, and the picture stands alone above it.
## Hints, "Error!", the worked solution and the success text are written with the plain `WriteMessageText` again (the slot
## is back to 0 after the prompt), so only the PROMPT carries the picture.

## The two loose pictures (`LoadBundleInto(0x578c / 0x578d)`: logical ids above 20000), as `ui_picture` names.
const PICTURE_SHIP := &"prompt_sender_ship"
const PICTURE_CONTROL_ROOM := &"prompt_sender_control_room"
## Where the picture goes (window pixels) and its size.
const PICTURE_POSITION := Vector2i(0x169, 0x30)
const PICTURE_SIZE := Vector2i(55, 20)
## Left edge of the header line: 0x168 plus the picture's width rounded down to an even number.
const HEADER_X := 0x168 + (55 & ~1)
## Where the text after the first newline starts: x like ordinary message text (the message box), y = 0x44.
const BODY_Y := 0x44


## `LoadPromptSenderPicture` (0x423378): the research ship for the trigger slots 2 to 19 and 60 up (the ones that light the
## ship's message light, `DoAction` 0x417ffc), the control room for slot 1 (the data canister), 20 to 59 (the on-board
## computer) and the lock's 0. The compare is signed in the original, so a negative slot is the control room too.
static func picture_name(slot: int) -> StringName:
	if (slot >= 2 and slot <= 19) or slot >= 60:
		return PICTURE_SHIP
	return PICTURE_CONTROL_ROOM


static func texture(slot: int) -> Texture2D:
	return Assets.ui_picture(picture_name(slot))


## True when the prompt of `instance` is written with the sender picture: asked by a map trigger (`trigger_slot` >= 0), not
## in Math Practice, and a type whose prompt `ShowProblemPrompt` writes (1 to 33: the combination lock (type 0) has its own
## screen and never calls it).
static func applies_to(instance: ProblemInstance, practice: bool) -> bool:
	return not practice and instance.trigger_slot >= 0 and instance.type.id >= 1 and instance.type.id <= 33


## `WriteMessageTextWithSender`'s split at the first newline: [header, rest]. Without a newline the header is empty.
static func split(prompt: String) -> PackedStringArray:
	var newline := prompt.find("\n")
	if newline < 0:
		return PackedStringArray(["", prompt])
	return PackedStringArray([prompt.substr(0, newline), prompt.substr(newline + 1)])
