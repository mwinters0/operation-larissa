class_name TestGameState
extends GdUnitTestSuite
## Teaches: testing signals. A fresh GameState (not the autoload) is created for each
## test and its signals are recorded by lambdas, so nothing leaks between tests.

const GameStateScript := preload("res://src/autoload/game_state.gd")

var _state: Node
var _events: Array


func before_test() -> void:
	_state = auto_free(GameStateScript.new())
	_state.begin_run()                                            # (a run: the rule values of the chain)
	_events = []
	_state.oxygen_changed.connect(func(tanks: int, oxygen: int) -> void: _events.append(["oxygen", tanks, oxygen]))
	_state.ink_changed.connect(func(n: int) -> void: _events.append(["ink", n]))
	_state.tank_lost.connect(func(code: int) -> void: _events.append(["tank_lost", code]))
	_state.game_over.connect(func() -> void: _events.append(["game_over"]))
	_state.ink_empty.connect(func() -> void: _events.append(["ink_empty"]))


func test_starts_like_a_new_player() -> void:
	assert_int(_state.tanks()).is_equal(_state.tuning.refill_tanks)
	assert_int(_state.oxygen()).is_equal(_state.tuning.max_oxygen)
	assert_int(_state.ink).is_equal(_state.tuning.ink_max)


func test_damage_emits_oxygen_changed() -> void:
	_state.update_oxygen(-1)
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, _state.tuning.max_oxygen - 1]])


func test_running_out_with_a_spare_tank_emits_tank_lost() -> void:
	_state.update_oxygen(-4)
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0], ["tank_lost", -1]])


func test_running_out_with_the_last_tank_emits_tank_lost_with_code_minus_3() -> void:
	_state.oxygen_model.tanks = 1
	assert_int(_state.update_oxygen(-4)).is_equal(-3)
	assert_array(_events.back()).is_equal(["tank_lost", -3])


func test_running_out_with_no_tank_emits_game_over() -> void:
	_state.oxygen_model.tanks = 0
	_state.update_oxygen(-4)
	assert_array(_events).is_equal([["oxygen", 0, 0], ["game_over"]])


func test_respawn_and_restart_codes_refill() -> void:
	_state.update_oxygen(-4)
	_events.clear()
	_state.update_oxygen(4)                              # respawn: spends a tank
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks - 1, _state.tuning.max_oxygen]])


func test_firing_uses_one_pellet_and_an_empty_supply_says_so() -> void:
	assert_bool(_state.fire_ink()).is_true()
	assert_int(_state.ink).is_equal(_state.tuning.ink_max - 1)
	assert_array(_events).is_equal([["ink", _state.tuning.ink_max - 1]])
	_state.ink = 0
	_events.clear()
	assert_bool(_state.fire_ink()).is_false()
	assert_int(_state.ink).is_equal(0)
	assert_array(_events).is_equal([["ink_empty"]])


func test_refill_restores_the_full_supply() -> void:
	for i in 5:
		_state.fire_ink()
	_state.refill_ink()
	assert_int(_state.ink).is_equal(_state.tuning.ink_max)


# --- losses held while a problem is open ----------------------------------------------------

func test_a_held_loss_changes_the_numbers_but_is_announced_only_on_release() -> void:
	_state.hold_losses()
	_state.update_oxygen(-4)
	assert_int(_state.oxygen()).is_equal(0)                 # the console shows the air gone ...
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0]])      # ... but no tank is lost yet
	assert_bool(_state.has_held_loss()).is_true()
	_state.release_losses()
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0], ["tank_lost", -1]])
	assert_bool(_state.has_held_loss()).is_false()


func test_only_the_first_held_loss_counts_and_a_game_over_waits_too() -> void:
	_state.oxygen_model.tanks = 0
	_state.hold_losses()
	_state.update_oxygen(-4)
	_state.update_oxygen(-1)
	_state.release_losses()
	assert_array(_events.filter(func(e: Array) -> bool: return e[0] == "game_over")).has_size(1)


func test_releasing_without_a_loss_announces_nothing() -> void:
	_state.hold_losses()
	_state.update_oxygen(-1)
	_state.release_losses()
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, _state.tuning.max_oxygen - 1]])


func test_a_loss_decided_before_a_hold_begins_survives_it() -> void:
	# The sim holds the losses from a hit until the sub has dissolved; a problem screen opening in between holds them too.
	_state.hold_losses()                                    # the sim's
	_state.update_oxygen(-4)                                # the tank is lost, waiting for the dissolve
	_state.hold_losses()                                    # a problem opens
	assert_bool(_state.has_held_loss()).is_true()
	_state.release_losses()                                 # ... and closes: the sim's hold is still on, nothing is announced yet
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0]])
	_state.release_losses()                                 # the dissolve is over
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0], ["tank_lost", -1]])


func test_extra_releases_are_ignored() -> void:
	_state.release_losses()
	_state.hold_losses()
	_state.update_oxygen(-4)
	assert_array(_events).is_equal([["oxygen", _state.tuning.refill_tanks, 0]])      # one release too many before did not leave a credit


# --- the midpoint --------------------------------------------------------------------------

func test_the_midpoint_turns_on_after_the_midpoint_screen_and_the_early_pieces() -> void:
	var sector := Catalog.sector(0)
	var changes := []
	_state.midpoint_changed.connect(func(past: bool) -> void: changes.append(past))
	_state.screen_entered(Tuning.resolve().midpoint_screen, sector)               # the midpoint screen seen, but pieces before it are missing
	assert_bool(_state.past_midpoint).is_false()
	for i in sector.pieces.size():
		if sector.pieces[i].screen < Tuning.resolve().midpoint_screen:
			_state.collect_piece(i)
	assert_bool(_state.past_midpoint).is_false()                      # nobody asked yet: the engine asks after every pickup
	_state.update_midpoint(sector)
	assert_bool(_state.past_midpoint).is_true()
	assert_array(changes).is_equal([true])
	_state.update_midpoint(sector)
	assert_array(changes).is_equal([true])                            # announced once
	_state.clear_midpoint()
	assert_bool(_state.past_midpoint).is_false()
	assert_bool(_state.midpoint_reached).is_false()


func test_all_pieces_without_ever_entering_the_midpoint_screen_is_not_the_midpoint() -> void:
	var sector := Catalog.sector(0)
	for i in sector.pieces.size():
		_state.collect_piece(i)
	_state.update_midpoint(sector)
	assert_bool(_state.past_midpoint).is_false()


# --- the player ----------------------------------------------------------------------------

func test_a_profile_goes_in_and_comes_back_out() -> void:
	var p := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	p.tanks = 4
	p.oxygen = 2
	p.ink = 9
	p.pieces_mask = 0b101
	p.hints_unseen = 0xFFFF & ~(1 << HintSystem.CONTROLS)
	_state.apply_profile(p)
	assert_int(_state.tanks()).is_equal(4)
	assert_int(_state.oxygen()).is_equal(2)
	assert_int(_state.ink).is_equal(9)
	assert_int(_state.pieces_collected()).is_equal(2)
	assert_bool(_state.hints.has_been_shown(HintSystem.CONTROLS)).is_true()   # the saved hint mask is honoured
	_state.update_oxygen(-1)
	_state.fire_ink()
	_state.hints.take(HintSystem.LOW_OXYGEN)
	_state.past_midpoint = true
	_state.capture_profile()
	assert_int(p.oxygen).is_equal(1)
	assert_int(p.ink).is_equal(8)
	assert_bool(p.past_midpoint()).is_true()
	assert_int(p.hints_unseen & 0xFFFF).is_equal(0xFFFF & ~(1 << HintSystem.CONTROLS) & ~(1 << HintSystem.LOW_OXYGEN))


func test_a_game_over_restart_refills_everything_and_counts_a_try() -> void:
	var p := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	_state.apply_profile(p)
	_state.collect_piece(1)
	_state.past_midpoint = true
	_state.oxygen_model.tanks = 0
	_state.fire_ink()
	_state.restart_sector()
	assert_int(_state.tanks()).is_equal(_state.tuning.refill_tanks)
	assert_int(_state.oxygen()).is_equal(_state.tuning.max_oxygen)
	assert_int(_state.ink).is_equal(_state.tuning.ink_max)
	assert_int(_state.pieces_mask).is_equal(0)
	assert_bool(_state.past_midpoint).is_false()
	assert_int(p.tries).is_equal(2)


func test_a_respawn_spends_a_tank_and_keeps_the_pieces() -> void:
	_state.collect_piece(2)
	_state.respawn()
	assert_int(_state.tanks()).is_equal(_state.tuning.refill_tanks - 1)
	assert_int(_state.oxygen()).is_equal(_state.tuning.max_oxygen)
	assert_bool(_state.has_piece(2)).is_true()
