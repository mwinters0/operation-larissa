class_name HelpTopics
extends RefCounted
## Which of the original's texts make up each page of the Help menu.
##
## Teaches: a lookup table kept as data next to a tiny cleaning function. The seven topics are the
## items of the Help menu (string `help_menu_items`); each is a list of `text` names. The long pages (`help_*`) come from the
## importer's "help" table, the "About" page from the UI strings. The original's paging buttons are in strings 11009-11013.

## One entry per Help menu item, in menu order. A page is a list of `text` names from the "help" table. The original's seven
## `do_help_*_message` wrappers (0x428ed9 ...) call `RunHelpTopic` (0x428d70) with strings 11116-11122 (first character
## = page count, the rest = title) and the first long text of the topic (logical resource 32000 + n = text 12000 + n, see
## `LogicalToRealResource`); the short texts 10152-10163 are never shown by this build.
const TOPICS: Array[Array] = [
	[&"help_playing_0", &"help_playing_1"],                                          # Playing the Game        (11116: 2 pages, wrapper 0x428ed9, logical 0x7d07)
	[&"help_keyboard_0"],                                                            # Using the Keyboard      (11117: 1 page,  0x428ef2, 0x7d09)
	[&"help_zones_0"],                                                               # Zones and Sectors       (11118: 1 page,  0x428f0b, 0x7d12)
	[&"help_math_0", &"help_math_1"],                                                # Solving Math Calculations (11119: 2 pages, 0x428f24, 32000)
	[&"help_calculator_0", &"help_calculator_1", &"help_calculator_2"],              # Using the Calculator    (11120: 3 pages, 0x428f3d, 0x7d0e)
	[&"help_education_0", &"help_education_1", &"help_education_2", &"help_education_3"],   # Educational Focus  (11121: 4 pages, 0x428f56, 0x7d02)
]
## `MenuAboutBox` (0x42b74c) joins strings 11144-11146 (no separator), then 11147-11149 (three "\n"), then Version
## (11002) + "\n", then Copyright (11001) + "\n"; the title is 11150 ("About Operation Neptune").
const ABOUT_TEXTS: Array[StringName] = [&"about_0", &"about_1", &"about_2", &"about_3", &"about_4", &"about_5"]
const TOPIC_COUNT := 7
## The Help menu of Math Practice (strings 11058 / 11059) has two items: "Math Practice" (these texts, 11122 says 3 pages:
## `do_help_math_practice_message` 0x428f6f, logical 0x7d0b) and "About".
const PRACTICE_TOPIC: Array[StringName] = [&"help_practice_0", &"help_practice_1", &"help_practice_2"]


## How many topics the Help menu has.
static func count() -> int:
	return TOPIC_COUNT


## The text of every page of topic `index` (0-6), cleaned for display. With `practice` the topic is one of the
## two of the practice menu: 0 = Math Practice, 1 = About.
static func pages(index: int, practice: bool = false) -> PackedStringArray:
	var result := PackedStringArray()
	if practice and index == 0:
		for page in PRACTICE_TOPIC:
			result.append(clean(Catalog.text(page)))
		return result
	if practice or index == TOPIC_COUNT - 1:
		result.append(clean(about_text()))
		return result
	for page: StringName in TOPICS[index]:
		if Catalog.has_text(page):
			result.append(clean(Catalog.text(page)))
	return result


## The About box text exactly as `MenuAboutBox` (0x42b74c) builds it (before `clean`).
static func about_text() -> String:
	var about := ""
	for text_name in ABOUT_TEXTS:
		about += Catalog.text(text_name)
	return about + Catalog.text(&"version_line") + "\n" + Catalog.text(&"copyright_line") + "\n"


## Makes an original text printable: the font markers (ÿ, bold on/off) and key glyphs go (keys become
## arrows and words, see `HintSystem.printable`), the "°" used as a blank in the data becomes a space.
static func clean(raw: String) -> String:
	var expression := RegEx.create_from_string("ÿ[\\x00-\\x1f]*ÿ")
	var text := expression.sub(raw, "", true)
	text = HintSystem.printable(text).replace("°", " ")
	return text.replace("\r", "\n").strip_edges()
