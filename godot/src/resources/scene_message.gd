class_name SceneMessage
extends Resource
## One page of a scene's message: a text and the voice groups read aloud while it is on screen. A `StoryScene` lists them in `messages`; the verb `messages` shows them one after the other in the message box as the surface ship's
## (`MessageQueue.post_ship`), Enter closing a page and cutting its speech off. The legacy pack's Voyager closing has three (`closing_page_0`..2, the first with the jingle "incoming transmission" before its words).
##
## Teaches: a page as ONE record of what is shown and what is heard with it, so the two cannot drift apart; how long the page stays is not here, the player closes it.

## The text of the page (a `Catalog.text` name: a text of the original or one of a pack's `texts.json`).
@export var text: StringName = &""
## The voice groups (`voice_cues`) spoken while the page is up, in order; empty: the page is silent.
@export var speech: Array[StringName] = []

## The heading line the original's closing texts begin with. The message box draws its own heading ("Surface Ship Message"), so the text is shown without it: the one place that line is dropped.
const HEADING := "Surface Ship Message:\n"


## The page as the message box shows it: the text without its own heading line, the key pictures of the text turned into words (`HintSystem.printable`), the ends trimmed.
func shown() -> String:
	var raw := Catalog.text(text)
	if raw.begins_with(HEADING):
		raw = raw.substr(HEADING.length())
	return HintSystem.printable(raw).strip_edges()


## Does a pack of the chain hold the text of the page?
func has_text() -> bool:
	return text != &"" and Catalog.has_text(text)


## The clips of the page's voice groups in order (the groups that hold none add nothing).
func clips() -> Array[StringName]:
	var found: Array[StringName] = []
	for group in speech:
		found.append_array(Catalog.voice_cues().clips(String(group)))
	return found
