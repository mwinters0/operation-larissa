class_name TestSupplyStationLegacy
extends GdUnitTestSuite
## Teaches: the original's supply station trips in ticks of 6/73 s: the launch took 30 (2.47 s), the dock 31 (2.55 s), the balloon 44 (3.62 s). (The rules that
## count them: tests/engine/test_supply_station.gd.)

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_numbers_of_the_original() -> void:
	# (the numbers are data now, `data/rules/durations.json`; `test_durations.gd` changes them and watches the rules follow)
	var launch := StationSequence.launch()
	var dock := StationSequence.dock()
	assert_array([launch.pixels_per_tick, dock.pixels_per_tick, StationSequence.balloon().pixels_per_tick]).is_equal([4, 4, 4])
	assert_int(launch.to_x - launch.from_x).is_equal(96)
	assert_int(dock.to_x - dock.from_x).is_equal(100)
	assert_array([launch.opening_ticks, launch.closing_ticks, dock.opening_ticks, dock.closing_ticks]).is_equal([3, 3, 3, 3])
	assert_array([StationSequence.balloon().balloon_x, StationSequence.balloon().balloon_from_y, StationSequence.balloon().balloon_to_y]).is_equal([560, 144, -32])


func test_a_launch_is_30_ticks_a_dock_31_and_the_balloon_44() -> void:
	assert_int(StationSequence.launch().drive_ticks()).is_equal(24)
	assert_int(StationSequence.launch().ticks).is_equal(30)
	assert_int(StationSequence.dock().drive_ticks()).is_equal(25)
	assert_int(StationSequence.dock().ticks).is_equal(31)
	assert_int(StationSequence.balloon().ticks).is_equal(44)               # 176 px at 4 px per tick, from the surface ship's window to above the playfield




func test_the_finale_sectors_have_stations_too() -> void:
	var world := scene_runner("res://src/gameplay/sector_world.tscn").scene() as SectorWorld
	world.load_sector(30, 0)                                            # (DrawScreen 0x433f1c)
	assert_bool(world.original.station.visible).is_true()
	assert_int(world.original.station.side).is_equal(SupplyStation.Side.LEFT)
