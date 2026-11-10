@tool
class_name LineDiff
extends RefCounted
## The lines that differ between two texts, as a list of hunks. Used by the what-changed report (`SectorChanges`) to show what a
## designer changed in a creature script.
##
## Teaches: the longest common subsequence, the idea under every `diff`: the lines both texts keep, in order, are the ones that did
## not change; what lies between them was removed (old only), added (new only) or both (changed). The common beginning and end are
## cut off first, which makes the table small for the usual case of a few edited lines in a long script.

## Above this many table cells (old lines x new lines of the part between the common ends) the middle is reported as one hunk
## instead of being compared line by line.
const MAX_CELLS := 4_000_000


## One place where the texts differ. `old_start` / `new_start` are 1-based line numbers of the first line of the hunk in the old /
## new text; with no lines on one side they are the line the other side's lines come before.
class Hunk extends RefCounted:
	var old_start := 0
	var old_lines: Array[String] = []
	var new_start := 0
	var new_lines: Array[String] = []

	func kind() -> String:
		if old_lines.is_empty():
			return "added"
		if new_lines.is_empty():
			return "removed"
		return "changed"

	## "line 40", "lines 40-42", or "after line 39" for lines that were only removed.
	func new_range_text() -> String:
		if new_lines.is_empty():
			return "after line %d" % maxi(new_start - 1, 0)
		if new_lines.size() == 1:
			return "line %d" % new_start
		return "lines %d-%d" % [new_start, new_start + new_lines.size() - 1]


## The hunks that turn `old_text` into `new_text`, in order; empty when the texts are the same line by line.
static func diff(old_text: String, new_text: String) -> Array[Hunk]:
	return diff_lines(_lines(old_text), _lines(new_text))


static func _lines(text: String) -> Array[String]:
	var out: Array[String] = []
	for line in text.replace("\r\n", "\n").split("\n"):
		out.append(line)
	if not out.is_empty() and out[out.size() - 1] == "":
		out.pop_back()                       # the newline that ends the last line
	return out


static func diff_lines(old_lines: Array[String], new_lines: Array[String]) -> Array[Hunk]:
	var hunks: Array[Hunk] = []
	var head := 0
	while head < old_lines.size() and head < new_lines.size() and old_lines[head] == new_lines[head]:
		head += 1
	var tail := 0
	while tail < old_lines.size() - head and tail < new_lines.size() - head \
			and old_lines[old_lines.size() - 1 - tail] == new_lines[new_lines.size() - 1 - tail]:
		tail += 1
	var n := old_lines.size() - head - tail
	var m := new_lines.size() - head - tail
	if n == 0 and m == 0:
		return hunks
	if (n + 1) * (m + 1) > MAX_CELLS or n == 0 or m == 0:
		hunks.append(_hunk(head, old_lines.slice(head, head + n), new_lines.slice(head, head + m)))
		return hunks
	# table[i * (m + 1) + j] = length of the longest common subsequence of old[i..] and new[j..]
	var width := m + 1
	var table := PackedInt32Array()
	table.resize((n + 1) * width)
	for i in range(n - 1, -1, -1):
		for j in range(m - 1, -1, -1):
			if old_lines[head + i] == new_lines[head + j]:
				table[i * width + j] = table[(i + 1) * width + j + 1] + 1
			else:
				table[i * width + j] = maxi(table[(i + 1) * width + j], table[i * width + j + 1])
	var i := 0
	var j := 0
	var removed: Array[String] = []
	var added: Array[String] = []
	var removed_at := 0
	var added_at := 0
	while i < n or j < m:
		if i < n and j < m and old_lines[head + i] == new_lines[head + j]:
			if not removed.is_empty() or not added.is_empty():
				hunks.append(_hunk2(removed_at, removed, added_at, added))
				removed = []
				added = []
			i += 1
			j += 1
			continue
		if removed.is_empty() and added.is_empty():
			removed_at = head + i
			added_at = head + j
		if j >= m or (i < n and table[(i + 1) * width + j] >= table[i * width + j + 1]):
			removed.append(old_lines[head + i])
			i += 1
		else:
			added.append(new_lines[head + j])
			j += 1
	if not removed.is_empty() or not added.is_empty():
		hunks.append(_hunk2(removed_at, removed, added_at, added))
	return hunks


static func _hunk(at: int, removed: Array[String], added: Array[String]) -> Hunk:
	return _hunk2(at, removed, at, added)


## `old_at` / `new_at` are 0-based indexes of the first line of each side.
static func _hunk2(old_at: int, removed: Array[String], new_at: int, added: Array[String]) -> Hunk:
	var hunk := Hunk.new()
	hunk.old_start = old_at + 1
	hunk.old_lines = removed
	hunk.new_start = new_at + 1
	hunk.new_lines = added
	return hunk
