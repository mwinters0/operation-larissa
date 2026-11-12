class_name TestInitChainsToTheBase
extends GdUnitTestSuite
## Teaches: a GDScript trap kept out by a test that reads the source. A script that defines `_init()` does NOT get its base script's `_init()` run for it: the base's constructor is only called when
## the subclass says `super()`. The same holds for `_ready`, `_enter_tree` and `_exit_tree` (and `_process` and the other callbacks): the engine calls the most derived one only, the base's runs when the subclass says `super()`.
## (`_notification` is the exception: the engine calls it once for every script of the chain, so it must NOT say `super`.) `ModDiagram` once defined its own `_init` over `DiagramBase`'s (which gives the diagram the size
## of the window) and so was 0 x 0 pixels, and its `clip_contents` cut every problem's picture away. This suite reads every script of `src/`, `addons/` and `skins/` and fails on a script that has one of the four set-up and
## tear-down methods over the same method of the script class it extends without calling `super` in it; it also feeds the scan scripts that are wrong, so that a scan that went blind would fail too.
## A script whose base is native (a `Node`, a `Control`) has nothing to chain to and is not looked at. A per-frame or per-event callback (`_process`, `_draw`, `_input`) is not guarded: replacing it is often the point.

const SKIPPED := ["res://addons/gdUnit4/", "res://addons/godot_ai/", "res://addons/midi/", "res://addons/godot_sandbox/"]
## The methods the engine calls once, to set an object up or to take it down, which a subclass has to chain by hand.
const CHAINED := ["_init", "_ready", "_enter_tree", "_exit_tree"]

var _class_line := RegEx.create_from_string("^class_name\\s+(\\w+)")
var _extends_line := RegEx.create_from_string("^extends\\s+(\\w+)")
var _func_line := RegEx.create_from_string("^func\\s+(\\w+)\\s*\\(")


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for folder in ["res://src", "res://addons", "res://skins"]:
		for path in SourceScan.scripts_under(folder):
			if not SKIPPED.any(func(skipped: String) -> bool: return path.begins_with(skipped)):
				found.append(path)
	return found


## What the code lines of a script say of it: its class name, the class it extends, and for each of `CHAINED` that it defines, whether the body calls `super` (`super(` or `super.<method>(`).
func _facts(lines: PackedStringArray) -> Dictionary:
	var facts := {"name": "", "base": "", "methods": {}}
	var current := ""
	for code in lines:
		var named := _class_line.search(code)
		if named != null:
			facts["name"] = named.get_string(1)
		var based := _extends_line.search(code)
		if based != null:
			facts["base"] = based.get_string(1)
		var defined := _func_line.search(code)
		if defined != null:
			current = defined.get_string(1) if defined.get_string(1) in CHAINED else ""
			if not current.is_empty():
				facts["methods"][current] = false
			continue
		if not current.is_empty():
			if not code.is_empty() and code[0] != " " and code[0] != "\t":     # (the next top-level line ends the body)
				current = ""
			elif RegEx.create_from_string("\\bsuper\\s*\\(|\\bsuper\\.%s\\s*\\(" % current).search(code) != null:
				facts["methods"][current] = true
	return facts


## Every method of `CHAINED` that a script defines over the same method of the script class it extends, without `super`: "label: ...". `sources` maps a label (a path) to the source of a script.
func _skipped(sources: Dictionary) -> Array[String]:
	var all := {}
	var by_name := {}
	for label: String in sources:
		var facts := _facts(SourceScan.code_lines(sources[label]))
		all[label] = facts
		if not String(facts["name"]).is_empty():
			by_name[facts["name"]] = label
	var broken: Array[String] = []
	for label: String in all:
		var facts: Dictionary = all[label]
		for method: String in facts["methods"]:
			if facts["methods"][method]:
				continue
			var base := String(facts["base"])
			while by_name.has(base):                                 # (up the chain of script classes: the first one with the method is the one that is skipped)
				var above: Dictionary = all[by_name[base]]
				if above["methods"].has(method):
					broken.append("%s: `%s` over the `%s` of %s (%s) without `super`" % [label, method, method, base, by_name[base]])
					break
				base = String(above["base"])
	return broken


func test_a_script_with_its_own_setup_method_chains_to_the_one_of_the_script_class_it_extends() -> void:
	var sources := {}
	for path in _scripts():
		sources[path] = FileAccess.get_file_as_string(path)
	var broken := _skipped(sources)
	assert_array(broken).override_failure_message("a set-up or tear-down method that skips its base's:\n" + "\n".join(broken)).is_empty()


## The scan itself: a base with all four, a subclass that skips each, one that chains each (both spellings), a grandchild whose parent defines none, a native base and a method that is not one of the four.
func test_the_scan_finds_a_method_that_skips_its_base() -> void:
	var base := "class_name Base\nextends Control\nfunc _init() -> void:\n\tsize = Vector2(1, 1)\nfunc _ready() -> void:\n\tpass\nfunc _enter_tree() -> void:\n\tpass\nfunc _exit_tree() -> void:\n\tpass\nfunc _process(_d: float) -> void:\n\tpass\n"
	var skipping := "class_name Skipping\nextends Base\nfunc _init() -> void:\n\tclip_contents = true\nfunc _ready() -> void:\n\tpass\nfunc _enter_tree() -> void:\n\tpass\nfunc _exit_tree() -> void:\n\tpass\nfunc _process(_d: float) -> void:\n\tpass\n"
	var chaining := "class_name Chaining\nextends Base\nfunc _init() -> void:\n\tsuper()\n\tclip_contents = true\nfunc _ready() -> void:\n\tsuper._ready()\nfunc _enter_tree() -> void:\n\tsuper()\nfunc _exit_tree() -> void:\n\tsuper._exit_tree()\n"
	var grandchild := "class_name Grandchild\nextends Skipping\nfunc _ready() -> void:\n\tpass\n"
	var native := "class_name Native\nextends Control\nfunc _init() -> void:\n\tpass\nfunc _ready() -> void:\n\tpass\n"
	var in_comment := "class_name Quiet\nextends Base\nfunc _init() -> void:\n\tvar note := \"super()\"     # super()\n\tpass\n"
	var found := _skipped({"base": base, "skipping": skipping, "chaining": chaining, "grandchild": grandchild, "native": native, "quiet": in_comment})
	var expected: Array[String] = []
	for method in CHAINED:
		expected.append("skipping: `%s` over the `%s` of Base (base) without `super`" % [method, method])
	expected.append("grandchild: `_ready` over the `_ready` of Skipping (skipping) without `super`")    # (the first script up the chain that has `_ready`)
	expected.append("quiet: `_init` over the `_init` of Base (base) without `super`")                    # (`super(` in a string or a comment does not count)
	found.sort()
	expected.sort()
	assert_array(found).is_equal(expected)
