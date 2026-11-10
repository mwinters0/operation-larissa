class_name SourceScan
extends RefCounted
## Test helper: reads the SOURCE of a script and says where it names something it should not. One copy of the scan for every test
## that guards a layer ("the rules never name a node", "a view times nothing with a tween", "layout code asks no texture for a size").
##
## Teaches: why a text search needs a little care. A word in a comment ("draws a Texture2D") or in a string ("Audio") is not code, so
## the scan first blanks out comments and strings (keeping the line numbers); a word is only a hit when it stands alone (`Font`
## is not `FontFile`, `Input` is not `InputSnapshot`); and a hit is reported as file:line and the word, so the failure says
## where to look.


## The lines of `source` with every comment and every string blanked out (a string becomes `""` with nothing inside, a comment is
## cut off). The count and the order of the lines stay, so line numbers still match the file. Knows `#` comments, '...', "...",
## triple quotes (which may run over several lines), escapes with a backslash, and the `&"name"` / `^"path"` literals (the quote
## is all that matters to it).
static func code_lines(source: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	var quote := ""                                  # the quote that closes the string we are in ("" outside a string)
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]
		if c == "\n":
			lines.append(line)
			line = ""
			i += 1
			continue
		if quote.is_empty():
			if c == "#":                             # a comment: the rest of the line is not code
				while i < n and source[i] != "\n":
					i += 1
				continue
			if c == "\"" or c == "'":
				quote = c.repeat(3) if source.substr(i, 3) == c.repeat(3) else c
				line += "\"\""
				i += quote.length()
				continue
			line += c
			i += 1
		else:                                        # inside a string: skip to the closing quote
			if c == "\\":                            # a backslash: the next character is part of the string (a line break ends the line)
				i += 1
				if i < n and source[i] != "\n":
					i += 1
			elif source.substr(i, quote.length()) == quote:
				i += quote.length()
				quote = ""
			else:
				i += 1
	lines.append(line)
	return lines


## The code lines (see `code_lines`) of the file at `path`.
static func code_lines_of(path: String) -> PackedStringArray:
	return code_lines(FileAccess.get_file_as_string(path))


## Every place where the code of `path` names one of `words`, as "path:line  word". A word is a regular-expression fragment
## ("Timer\\.new" is fine) matched as a whole word. Comments and strings do not count. `members_too` false skips a word that follows a
## dot (`PlayerProfile.Game` is a member of another class, not the class `Game`); true (the default) keeps it (`node.get_tree()` is
## the call that is being looked for).
static func find(path: String, words: Array, members_too: bool = true) -> Array[String]:
	var pattern := RegEx.create_from_string(("" if members_too else "(?<!\\.)") + "\\b(" + "|".join(PackedStringArray(words)) + ")\\b")
	var found: Array[String] = []
	var number := 0
	for code in code_lines_of(path):
		number += 1
		for hit in pattern.search_all(code):
			found.append("%s:%d  %s" % [path, number, hit.get_string()])
	return found


## `find` over several files, in the order given.
static func find_in(paths: Array, words: Array, members_too: bool = true) -> Array[String]:
	var found: Array[String] = []
	for path: String in paths:
		found.append_array(find(path, words, members_too))
	return found


## Every .gd file under `dir` (recursively), as res:// paths, sorted.
static func scripts_under(dir: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(scripts_under(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	found.sort()
	return found
