class_name TextTemplate
extends RefCounted
## Fills the `{0}`, `{1}` ... slots of one of the original's text templates.
##
## Teaches: string processing with a Dictionary of replacements. In the original the
## slot marker is the byte pair 0x08 0xD0+k; the importer already wrote it as `{k}`.
## Two more details of the original text format are handled here:
##   * a raw 0xFF (stored as "ÿ", `UNDERLINE_TOGGLE`) is the underline toggle of the original's text drawer:
##     `ConvertTextMarkup` (0x415ebf) turns it into FF 02 FF, `WrapTextLayout` (0x4160f6, case 2) flips the
##     underline flag and `DrawWrapChar` (0x4165d7) underlines every character drawn while it is on. The NEXT
##     byte is ordinary text (there is no width byte, and no "answer slot"). `render` writes the underlined
##     stretch as BBCode `[u]...[/u]` (an unclosed one ends with the text), which the problem screen's
##     RichTextLabel draws underlined. Only five stored texts hold a 0xFF: the lock solution of form 3 (10184)
##     and the data canister hints 10198-10201 (`N + ` then the underlined `= `, `t `, `c `, `s `).
##     No stored problem text contains a `[`, so the BBCode cannot clash with the text.
##   * lines may end in "\r\n" or a lone "\r"; both become one "\n" (the extractor turned
##     the "\r" of a "\r\n" pair into a second newline, so empty lines are collapsed).

const UNDERLINE_TOGGLE := "ÿ"
const UNDERLINE_ON := "[u]"
const UNDERLINE_OFF := "[/u]"


## `slots` maps the slot number to the text that replaces `{k}`.
static func render(template: String, slots: Dictionary) -> String:
	var text := template.replace("\r", "\n")
	while "\n\n" in text:
		text = text.replace("\n\n", "\n")
	for k in slots:
		text = text.replace("{%s}" % k, str(slots[k]))
	# Each raw 0xFF flips the underline; the byte after it is ordinary text.
	var parts := text.split(UNDERLINE_TOGGLE)
	text = parts[0]
	for i in range(1, parts.size()):
		text += (UNDERLINE_ON if i % 2 == 1 else UNDERLINE_OFF) + parts[i]
	if parts.size() % 2 == 0:
		text += UNDERLINE_OFF
	return text.strip_edges()


## True if a `{k}` slot is still in the text (a test helper: nothing may be left unfilled).
static func has_unfilled_slot(text: String) -> bool:
	var open := text.find("{")
	while open >= 0:
		var close := text.find("}", open)
		if close > open and text.substr(open + 1, close - open - 1).is_valid_int():
			return true
		open = text.find("{", open + 1)
	return false
