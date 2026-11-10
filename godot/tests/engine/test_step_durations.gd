class_name TestStepDurations
extends GdUnitTestSuite
## Teaches: a step that holds up play gets its LENGTH from the rules or from data, never from the thing that shows it.
## A tween's interval, an animation's length or a timer in a view would make the length depend on how it is drawn; so the lengths
## are ticks (1/73 s) owned by `ProblemFlow`, `CanisterLog` and the diagrams' data, and the view is TOLD "you have N
## ticks". The first test reads the source of the views to keep it that way; the others pin where the numbers come from.

## Views of the problem screens, the log screen and the playfield. None of them may time a step with a Tween or a timer (the screen's own AnimationPlayer only shakes and flashes; nothing waits for it). The playfield's door, drive, balloon and dissolve are lengths of the rules (`StationSequence`, `SimWorld.dissolve_length()`).
const VIEWS: Array[String] = [
	"res://src/problems/problem_screen.gd",
	"res://src/problems/diagrams/diagram_base.gd",
	"res://src/problems/diagrams/sonar_diagram.gd",
	"res://src/problems/diagrams/ballast_panel_diagram.gd",
	"res://src/ui/log_screen.gd",
	"res://src/gameplay/supply_station.gd",
	"res://src/gameplay/sub.gd",
	"res://src/gameplay/original_presenter.gd",
	"res://src/gameplay/sector_presenter.gd",
	"res://src/autoload/scene_router.gd",
	"res://src/story/surface_ship_screen.gd",
	"res://src/problems/combination_lock.gd",
	"res://src/story/news_cartoon.gd",
]
const CLOCKS: Array[String] = ["create_tween", "create_timer", "tween_interval", "Timer\\.new", "wait_time"]


func test_the_views_time_no_step_with_a_tween_a_timer_or_an_animation() -> void:
	var found := SourceScan.find_in(VIEWS, CLOCKS)
	assert_array(found).override_failure_message("a view times a step itself:\n" + "\n".join(found)).is_empty()


func test_the_log_scan_is_counted_by_the_rules_and_the_screen_has_no_animation_player() -> void:
	assert_int(CanisterLog.scan_ticks()).is_equal(Durations.at("log_scan.ticks_per_picture") * 8 * Durations.at("log_scan.sweeps"))     # (8 pictures a sweep)
	var screen := scene_runner("res://src/ui/log_screen.tscn").scene() as LogScreen
	for child in screen.get_children():
		assert_bool(child is AnimationPlayer).is_false()


func test_the_station_trips_and_the_dissolve_are_counted_by_the_rules() -> void:
	assert_int(StationSequence.launch().ticks).is_equal(28)                       # game ticks of 6/73 s: dev's door 2 + 24 driven (96 px at 4) + door 2
	assert_int(StationSequence.dock().ticks).is_equal(26)                         # 4 + 20 (100 px at 5) + 2
	assert_int(StationSequence.balloon().ticks).is_equal(ceili(float(Durations.at("station.balloon.from_y") - Durations.at("station.balloon.to_y")) / Durations.at("station.balloon.pixels_per_tick")))
	assert_int(SimWorld.dissolve_length()).is_equal(Durations.at("dissolve.ticks"))     # ticks of 1/73 s (the clock is held meanwhile)
	var station := (load("res://src/gameplay/supply_station.tscn") as PackedScene).instantiate()
	assert_object(station.find_child("Animations", true, false)).is_null()
	station.free()


func test_a_scene_fade_is_counted_in_ticks_not_tweened() -> void:
	assert_int(SceneRouter.fade_ticks()).is_equal(10)                                # dev's own length
	var done := [false]
	(func() -> void:
		await SceneRouter._fade_to(1.0)
		done[0] = true).call()
	SceneRouter.advance_fade(9)
	assert_bool(done[0]).is_false()
	SceneRouter.advance_fade(1)
	assert_bool(done[0]).is_true()
	SceneRouter._fade.modulate.a = 0.0


func test_the_supply_message_wait_is_the_datas_number_of_ticks_after_the_speech() -> void:
	assert_int(SurfaceShipScreen.wait_ticks()).is_equal(Durations.at("surface_ship.wait_ticks"))


func test_the_ballast_hold_is_70_ticks_in_the_panels_data() -> void:
	for type_id in [28, 29]:
		assert_int(int(Catalog.problem_type(type_id).diagram["total"]["hold_ticks"])).is_equal(70)


func test_a_message_stays_the_datas_number_of_ticks() -> void:
	assert_int(ProblemFlow.message_ticks()).is_equal(Durations.at("problem.message_ticks"))
	assert_int(ProblemFlow.message_ticks()).is_equal(Durations.at("speech.silent_ticks"))    # (the lock's own messages and the silent speech are the same length)


func test_a_calculator_key_stays_lit_for_the_rules_ticks() -> void:
	assert_int(CalculatorModel.key_flash_ticks()).is_equal(Durations.at("calculator.key_flash_ticks"))
	var calculator := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	assert_float(calculator._flash_timer.wait_time).is_equal_approx(CalculatorModel.key_flash_ticks() / 73.0, 0.00001)


func test_the_tick_meter_loses_no_time_at_any_frame_rate() -> void:
	var meter := TickMeter.new()
	var ticks := 0
	for frame in 600:                                                             # ten seconds at 60 frames per second
		ticks += meter.feed(1.0 / 60.0)
	assert_int(ticks).is_between(729, 730)                                        # 73 ticks per second (the last one may be a rounding away)
	assert_int(meter.feed(0.0)).is_less_equal(1)
	assert_int(TickMeter.new().feed(10.0)).is_equal(730)                          # one long frame gives the same
	assert_float(TickMeter.seconds(73)).is_equal(1.0)
	meter.feed(0.005)
	meter.reset()
	assert_int(meter.feed(0.005)).is_equal(0)                                     # a reset forgets the left-over fraction
