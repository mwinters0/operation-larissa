class_name TestCutsceneTimeline
extends GdUnitTestSuite
## Teaches: testing a small translation layer with a made-up scene. `CutsceneTimeline` (data) -> `Cutscene.animation()` ->
## `Animation` -> an `AnimationPlayer` moving real nodes. A stage of two sprites and a player stand in for a cutscene, so each rule of
## the translation (ticks become seconds, a picture NAME becomes a texture, a window position becomes a position inside the
## parent, a sub POSE becomes a frame and a facing, cues become method calls) is one short test.

var _root: Node2D
var _field: Node2D            # a parent that starts at window position (16, 32), like the playfield
var _sprite: Sprite2D
var _sub: AnimatedSprite2D
var _player: AnimationPlayer
var _cast: CutsceneCast


func before_test() -> void:
	_root = auto_free(Node2D.new())
	_field = Node2D.new()
	_field.position = Vector2(16, 32)
	_root.add_child(_field)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_field.add_child(_sprite)
	_sub = AnimatedSprite2D.new()
	_sub.name = "Sub"
	_sub.sprite_frames = Catalog.sub_frames()
	_sub.animation = &"all"
	_field.add_child(_sub)
	_player = AnimationPlayer.new()
	_root.add_child(_player)
	add_child(_root)
	_cast = CutsceneCast.new(_root)
	_cast.sub_tuning = Tuning.resolve().sub
	_cast.bind(&"thing", _sprite)
	_cast.bind(&"sub", _sub)


func _play(timeline: CutsceneTimeline) -> Animation:
	Cutscene.install_timeline(_player, &"test", timeline, _cast)
	_player.play(&"test")
	_player.pause()
	return _player.get_animation(&"test")


func test_ticks_become_seconds() -> void:
	var timeline := CutsceneTimeline.made_in_code(146.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, false], [73.0, true]])
	var animation := _play(timeline)
	assert_float(animation.length).is_equal_approx(2.0, 0.0001)
	assert_float(animation.track_get_key_time(0, 1)).is_equal_approx(1.0, 0.0001)
	_player.seek(0.5, true)
	assert_bool(_sprite.visible).is_false()
	_player.seek(1.0, true)
	assert_bool(_sprite.visible).is_true()


func test_a_picture_name_becomes_a_texture_and_a_window_position_a_position_inside_the_parent() -> void:
	var timeline := CutsceneTimeline.made_in_code(10.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_PICTURE, [[0.0, &"title_sky"], [5.0, &"title_sea"]])
	timeline.track(&"thing", CutsceneTrack.PROP_POSITION, [[0.0, Vector2(100, 200)]])
	timeline.track(&"thing", CutsceneTrack.PROP_MIRROR, [[0.0, true]])
	_play(timeline)
	_player.seek(0.0, true)
	assert_object(_sprite.texture).is_equal(Assets.ui_picture(&"title_sky"))
	assert_vector(_sprite.position).is_equal(Vector2(84, 168))             # the parent starts at (16, 32)
	assert_bool(_sprite.flip_h).is_true()
	_player.seek(6.0 / 73.0, true)
	assert_object(_sprite.texture).is_equal(Assets.ui_picture(&"title_sea"))


func test_a_skin_can_change_how_names_become_textures_without_touching_the_timeline() -> void:
	var seen: Array[StringName] = []
	_cast.pictures = func(picture_name: StringName) -> Texture2D:
		seen.append(picture_name)
		return Assets.ui_picture(&"title_sea")
	var timeline := CutsceneTimeline.made_in_code(10.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_PICTURE, [[0.0, &"title_sky"]])
	_play(timeline)
	_player.seek(0.0, true)
	assert_array(seen).is_equal([&"title_sky"])
	assert_object(_sprite.texture).is_equal(Assets.ui_picture(&"title_sea"))


func test_a_smooth_track_moves_between_keys_and_a_discrete_one_jumps() -> void:
	var timeline := CutsceneTimeline.made_in_code(73.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_FADE, [[0.0, 0.0], [73.0, 1.0]], true)
	_play(timeline)
	_player.seek(0.5, true)
	assert_float(_sprite.modulate.a).is_equal_approx(0.5, 0.001)
	var jump := CutsceneTimeline.made_in_code(73.0, "test")
	jump.track(&"thing", CutsceneTrack.PROP_FADE, [[0.0, 0.0], [73.0, 1.0]])
	_play(jump)
	_player.seek(0.5, true)
	assert_float(_sprite.modulate.a).is_equal(0.0)


func test_a_pose_is_a_drawing_and_a_facing_and_the_facing_gets_a_key_only_when_it_changes() -> void:
	var tuning := Tuning.resolve().sub
	var timeline := CutsceneTimeline.made_in_code(40.0, "test")
	timeline.track(&"sub", CutsceneTrack.PROP_POSE, [[0.0, Vector2i(1, 0)], [10.0, Vector2i(2, 1)], [20.0, Vector2i(5, 0)], [30.0, Vector2i(6, 1)]])
	var animation := _play(timeline)
	assert_int(animation.get_track_count()).is_equal(2)                          # the frame and flip_h
	assert_int(animation.track_get_key_count(0)).is_equal(4)
	assert_int(animation.track_get_key_count(1)).is_equal(2)                     # cells 1, 2 face left, 5 and 6 face right
	_player.seek(15.0 / 73.0, true)
	assert_int(_sub.frame).is_equal(tuning.picture_for(2, 1))
	assert_bool(_sub.flip_h).is_true()
	_player.seek(35.0 / 73.0, true)
	assert_int(_sub.frame).is_equal(tuning.picture_for(6, 1))
	assert_bool(_sub.flip_h).is_false()


func test_a_sound_and_an_event_at_the_same_moment_are_both_called() -> void:
	var timeline := CutsceneTimeline.made_in_code(10.0, "test")
	timeline.cue(5.0, CutsceneCue.SOUND, &"begin")
	timeline.cue(5.0, CutsceneCue.EVENT, &"prompt")
	var animation := _play(timeline)
	var calls := []
	for track in animation.get_track_count():
		assert_int(animation.track_get_type(track)).is_equal(Animation.TYPE_METHOD)
		for key in animation.track_get_key_count(track):
			calls.append([animation.method_track_get_name(track, key), animation.method_track_get_params(track, key)[0]])
	assert_array(calls).contains_exactly_in_any_order([[&"play_sfx", &"begin"], [&"cue", &"prompt"]])


func test_marks_become_animation_markers() -> void:
	var timeline := CutsceneTimeline.made_in_code(146.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
	timeline.marks = {&"middle": 73.0}
	var animation := _play(timeline)
	assert_float(animation.get_marker_time(&"middle")).is_equal_approx(1.0, 0.0001)


func test_frame_names_are_looked_up_in_the_zone_of_the_cast() -> void:
	_cast.frame_zone = 6
	_sub.sprite_frames = Catalog.foes_frames(6)
	var timeline := CutsceneTimeline.made_in_code(40.0, "test")
	timeline.track(&"sub", CutsceneTrack.PROP_FRAME, [[0.0, &"alien_artifact_0"], [10.0, &"alien_artifact_1"], [20.0, 3]])
	_play(timeline)
	_player.seek(0.0, true)
	assert_int(_sub.frame).is_equal(35)
	_player.seek(10.0 / 73.0, true)
	assert_int(_sub.frame).is_equal(36)
	_player.seek(20.0 / 73.0, true)
	assert_int(_sub.frame).is_equal(3)                                            # a number passes through


func test_an_actor_can_name_a_property_its_own_way() -> void:
	var chain := Control.new()
	chain.name = "Chain"
	_root.add_child(chain)
	_cast.bind(&"chain", chain, {CutsceneTrack.PROP_VISIBLE: "mouse_filter"})
	var timeline := CutsceneTimeline.made_in_code(10.0, "test")
	timeline.track(&"chain", CutsceneTrack.PROP_VISIBLE, [[0.0, 2]])
	_play(timeline)
	_player.seek(0.0, true)
	assert_int(chain.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


# --- the resources themselves ------------------------------------------------------------------------------

func test_problems_are_found() -> void:
	var timeline := CutsceneTimeline.made_in_code(10.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, true], [20.0, false]])        # a key after the end
	assert_int(timeline.problems().size()).is_equal(1)
	var bad := CutsceneTrack.from_keys(&"thing", &"colour", [[0.0, 1]])
	assert_str(bad.problem()).contains("unknown property")
	var unsorted := CutsceneTrack.from_keys(&"thing", CutsceneTrack.PROP_VISIBLE, [[5.0, true], [1.0, false]])
	assert_str(unsorted.problem()).contains("before")
	var uneven := CutsceneTrack.from_keys(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
	uneven.values.append(false)
	assert_str(uneven.problem()).contains("moments")
	assert_int(CutsceneTimeline.new().problems().size()).is_equal(1)                       # no length


func test_key_times_are_every_moment_once() -> void:
	var timeline := CutsceneTimeline.made_in_code(100.0, "test")
	timeline.track(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, true], [30.0, false]])
	timeline.track(&"sub", CutsceneTrack.PROP_POSE, [[30.0, Vector2i(0, 0)], [60.0, Vector2i(0, 1)]])
	timeline.cue(100.0, CutsceneCue.EVENT, &"end")
	assert_array(Array(timeline.key_times())).is_equal([0.0, 30.0, 60.0, 100.0])


func test_merging_keeps_both_halves() -> void:
	var first := CutsceneTimeline.made_in_code(64.0, "from the file", true)
	first.track(&"thing", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
	var second := CutsceneTimeline.made_in_code(64.0, "made here", true)
	second.track(&"sub", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
	second.cue(10.0, CutsceneCue.SOUND, &"begin")
	var merged := first.merged_with(second)
	assert_int(merged.tracks.size()).is_equal(2)
	assert_int(merged.cues.size()).is_equal(1)
	assert_bool(merged.loop).is_true()
	assert_str(merged.provenance).contains("from the file")
	assert_str(merged.provenance).contains("made here")
