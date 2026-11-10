class_name TestNoWarningsLoad
extends GdUnitTestSuite
## Teaches: a cheap safety net. Every scene under src/ must load and be instantiable; a scene whose script
## no longer compiles (a renamed class, a stale path) fails here instead of in the middle of a game.


func _scenes_in(path: String, found: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".tscn"):
			found.append(path.path_join(file))
	for directory in DirAccess.get_directories_at(path):
		_scenes_in(path.path_join(directory), found)


func test_every_scene_loads_and_can_be_instantiated() -> void:
	var scenes := PackedStringArray()
	_scenes_in("res://src", scenes)
	scenes.append("res://main.tscn")
	assert_int(scenes.size()).is_greater(35)
	for path in scenes:
		var scene := load(path) as PackedScene
		assert_object(scene).override_failure_message("cannot load " + path).is_not_null()
		assert_bool(scene.can_instantiate()).override_failure_message("cannot instantiate " + path).is_true()


func test_every_script_compiles() -> void:
	var scripts := PackedStringArray()
	_scripts_in("res://src", scripts)
	assert_int(scripts.size()).is_greater(100)
	for path in scripts:
		var script := load(path) as GDScript
		assert_object(script).override_failure_message("cannot load " + path).is_not_null()


func _scripts_in(path: String, found: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".gd"):
			found.append(path.path_join(file))
	for directory in DirAccess.get_directories_at(path):
		_scripts_in(path.path_join(directory), found)
