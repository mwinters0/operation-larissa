class_name TestSourceScan
extends GdUnitTestSuite
## Teaches: testing a test tool. The guards that read source (`test_rules_are_plain_objects.gd` and the others) are only as good as
## `SourceScan`, so its few rules are pinned here: comments and strings are blanked, line numbers survive, a word is a hit only
## when it stands alone, and a hit says file:line and the word.

const SAMPLE := """class_name Sample
extends RefCounted
## A doc comment about a Node and a Texture2D.
var a := 1 # a Font in a comment
var s := "Input in a string, \\" still a string, Node"
var t := 'Timer'
var u := &"Audio"
var triple := \"\"\"
Node on a line inside a triple-quoted string
\"\"\"
var real: Node = null
var other: FontFile = null
var snap: InputSnapshot = null
"""


func test_comments_and_strings_are_blanked_and_the_lines_stay_where_they_were() -> void:
	var lines := SourceScan.code_lines(SAMPLE)
	assert_int(lines.size()).is_equal(SAMPLE.count("\n") + 1)
	assert_str(lines[0]).is_equal("class_name Sample")
	assert_str(lines[2]).is_empty()                                    # (a doc comment)
	assert_str(lines[3].strip_edges()).is_equal("var a := 1")
	assert_str(lines[4]).is_equal("var s := \"\"")
	assert_str(lines[5]).is_equal("var t := \"\"")
	assert_str(lines[6]).is_equal("var u := &\"\"")
	assert_str(lines[8]).is_empty()                                     # (inside the triple quotes)
	assert_str(lines[10]).is_equal("var real: Node = null")


func test_a_word_is_a_hit_only_when_it_stands_alone_and_is_reported_with_its_line() -> void:
	var path := "user://source_scan_sample.gd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(SAMPLE)
	file.close()
	var found := SourceScan.find(path, ["Node", "Font", "Input", "Timer", "Audio", "Texture2D"])
	DirAccess.remove_absolute(path)
	assert_array(found).is_equal([path + ":11  Node"])                  # not FontFile, not InputSnapshot, nothing from comments or strings
