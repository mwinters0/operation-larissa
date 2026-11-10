class_name TestDisplaySettings
extends GdUnitTestSuite
## Project settings are data too: read them with ProjectSettings.


func test_viewport_and_stretch() -> void:
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_width")).is_equal(640)
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_height")).is_equal(400)
	assert_str(ProjectSettings.get_setting("display/window/stretch/mode")).is_equal("canvas_items")
	assert_str(ProjectSettings.get_setting("display/window/stretch/aspect")).is_equal("keep")
	assert_str(ProjectSettings.get_setting("display/window/stretch/scale_mode")).is_equal("integer")


func test_pixel_art_rendering() -> void:
	# 0 = Nearest
	assert_int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")).is_equal(0)
	assert_bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")).is_true()
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).is_equal("gl_compatibility")


func test_audio_buses() -> void:
	for bus_name in ["Master", "Music", "SFX", "Voice"]:
		assert_int(AudioServer.get_bus_index(bus_name)).override_failure_message("missing bus " + bus_name).is_greater_equal(0)
