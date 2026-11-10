class_name TestCreatureSounds
extends GdUnitTestSuite
## The creature scripts' SOUND opcode (DESIGN 3.5 / 7), checked through the real `Audio` hook, on the dev arena (`DevCreatures`):
##  * the arena's screen 0: the chomper plays the effect `clam_chomp` once per round of `DevCreatures.CHOMP_ROUND` ticks;
##  * touching Zoom's tank (damage < 0) is SILENT in the damage step (`ApplyCreatureDamage`): the only sound is
##    the creature's own contact script (`Play_Sound oxygen_refill`), not the hit sound.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const SFX_ZOOM_PICKUP := &"oxygen_refill"

var _world: SectorWorld
var _probe: AudioProbe


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	Audio.stop_sfx()
	_probe = AudioProbe.new()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld


func after_test() -> void:
	_probe.stop()
	Audio.stop_sfx()
	GameClock.paused = false
	GameState.reset()


func test_the_chomper_plays_its_effect_once_per_round_through_audio() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.POST_SCREEN)
	_probe.clear()
	for i in DevCreatures.CHOMP_ROUND * 2 - 1:        # two rounds: the sound is the first thing of a round
		_world.tick()
	assert_array(_probe.sfx).is_equal([&"clam_chomp", &"clam_chomp"])
	assert_int(Audio.busy_sfx_players()).is_greater(0)  # a real stream was started, not just announced


func test_the_chomper_is_silent_when_its_screen_is_not_shown() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.SLEEPER_SCREEN)
	_probe.clear()
	for i in DevCreatures.CHOMP_ROUND * 2:
		_world.tick()
	assert_array(_probe.sfx).is_empty()


func _touch_zoom() -> Foe:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.ZOOM_SCREEN)
	_world.start_flight()
	var zoom := _world.original.foes[DevCreatures.ZOOM]
	assert_int(zoom.vm.damage).is_less(0)
	zoom.vm.hidden = false
	zoom.refresh(true)
	GameState.oxygen_model.oxygen = 1
	_probe.clear()
	return zoom


func test_zoom_pickup_plays_only_its_own_sound_not_the_hit_sound() -> void:
	var zoom := _touch_zoom()
	_world.sub_touches(zoom.model)
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_array(_probe.sfx).is_empty()               # the damage step itself makes no sound
	for i in 3:                                       # the contact script runs: SLEEP_FOE self, SOUND 15, HIDE
		_world.tick()
	assert_array(_probe.sfx).is_equal([SFX_ZOOM_PICKUP])
	assert_bool(zoom.vm.hidden).is_true()


func test_a_hostile_contact_still_plays_the_hit_sound() -> void:
	_world.load_sector(DevCreatures.ARENA, 0)
	_world.start_flight()
	_probe.clear()
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_array(_probe.sfx).is_equal([&"creature_hit"])


## Every SOUND operand in every creature script of the chain (found by following all branches of every entry point) names
## an effect the pack has.
func test_every_sound_operand_in_every_script_exists() -> void:
	var found := 0
	for sector_index in Catalog.sector_ids():
		var sector := Catalog.sector(sector_index)
		for id in _sound_operands(sector):
			found += 1
			assert_object(Catalog.sfx_catalog().stream(id)).is_not_null()
	assert_int(found).is_greater(0)


## Walks the creature scripts of `sector` like the VM (both ways at every branch) and returns the SOUND operands.
func _sound_operands(sector: SectorData) -> Array[int]:
	var result: Array[int] = []
	var script := sector.foe_bytecode
	var base := sector.foe_script_base
	var seen := {}
	var work: Array[int] = []
	for foe in sector.foes:
		work.append_array([foe.pc, foe.script_hit, foe.script_ink])
	while not work.is_empty():
		var pc: int = work.pop_back()
		var i := pc - base
		if seen.has(pc) or i < 0 or i >= script.size():
			continue
		seen[pc] = true
		var op := script[i]
		if not FoeOps.is_valid(op):
			continue
		var next := pc + 1 + FoeOps.OPERAND_COUNT[op]
		var offset := 0
		if i + 2 < script.size():
			offset = script[i + 1] | (script[i + 2] << 8)
			offset = offset - 65536 if offset >= 32768 else offset
		match op:
			FoeOps.Op.SOUND:
				result.append(script[i + 1])
				work.append(next)
			FoeOps.Op.YIELD, FoeOps.Op.RET:
				if op == FoeOps.Op.YIELD:
					work.append(next)
			FoeOps.Op.JMP:
				work.append(next + offset)
			FoeOps.Op.HANDLER, FoeOps.Op.LOOP0, FoeOps.Op.LOOP1, FoeOps.Op.LOOP2:
				work.append(next + offset)
				work.append(next)
			FoeOps.Op.IF_SUBX_GT, FoeOps.Op.IF_SUBX_LT, FoeOps.Op.IF_SUBY_GT, FoeOps.Op.IF_SUBY_LT, \
					FoeOps.Op.IF_RAND_GT, FoeOps.Op.IF_SEM:
				work.append(next)
				var j := next - base
				if j >= 0 and j < script.size() and FoeOps.is_valid(script[j]):
					work.append(next + 1 + FoeOps.OPERAND_COUNT[script[j]])
			_:
				work.append(next)
	return result
