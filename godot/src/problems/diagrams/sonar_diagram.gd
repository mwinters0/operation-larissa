class_name SonarDiagram
extends DiagramBase
## Type 3, Sonar: the radar dial with the sweeping beam and a blip that shows how far away the object is.
##
## Teaches: choosing a table row from a value (`distance / 5`, clamped) and a tween for an
## animation that ends in the static picture the tests look at.
##
## The original sweeps the beam twice round the dial (12 steps, 6 ticks each) and then leaves it
## pointing straight up with the blip drawn; `_build()` builds that final state, `animate_to()` the intro.
##
## SOUND [V, Ghidra `RadarBlip` (0x4319ad) / `RadarSweep` (0x431a0f)]: every time the original draws the blip it first plays effect
## 0x29 ("diagram_pop"). The sweep draws it when the beam reaches the blip's step (`blip.step[row]`, 0 = straight up,
## in every row of the data), once per turn, and once more after the second turn: three pops in all, at 0, 12 and 24
## sweep steps (0 s, 0.99 s, 1.97 s). The beam passing the other 11 steps of a turn is silent.

## (The beam reaching the blip emits `DiagramBase.sfx_requested` with the sound `diagram_pop`, see `blip_sfx`.)


func _build() -> void:
	add_spec_items(spec["items"])
	_add_beam(0)
	_add_blip(_blip_frames().size() - 1)


## Index of the blip's row: distance / 5, clamped to the table.
func blip_row() -> int:
	var blip: Dictionary = spec["blip"]
	@warning_ignore("integer_division")
	return clampi(record.int_at(blip["field"]) / int(blip["divisor"]), blip["clamp"][0], blip["clamp"][1])


## The sweep step (index into `sweep.pics`) at which the beam is over the blip of this problem.
func blip_step() -> int:
	return int(spec["blip"]["step"][blip_row()])


## Sound effect the original plays when the beam passes over the blip.
func blip_sfx() -> int:
	return int(spec["blip"]["sfx"])


func _blip_frames() -> Array:
	return spec["blip"]["pic_frames"]


func _add_beam(step: int) -> void:
	var sweep: Dictionary = spec["sweep"]
	add_picture(sweep["pics"][step], vector(sweep["pos"][step]), step >= int(sweep["mirror_from"]))


func _add_blip(frame: int) -> void:
	var blip: Dictionary = spec["blip"]
	add_picture(blip["pic_frames"][frame], vector(blip["pos"][blip_row()]))


## The sweep is `revolutions` turns of `steps` beam pictures, each shown `ticks_per_step` ticks: the length is DATA, so the step
## machine counts it like any other build-up.
func sweep_ticks() -> int:
	var sweep: Dictionary = spec["sweep"]
	return int(sweep["revolutions"]) * sweep["pics"].size() * int(sweep["ticks_per_step"])


func intro_length() -> int:
	return sweep_ticks()


## Same entry points as every other diagram: the sweep is this diagram's build-up.
func has_intro() -> bool:
	return true


## The position of the sweep for whoever draws on the same time (`DiagramBase.animation_tick`): the length is the sweep's.
func animation_length() -> int:
	return sweep_ticks() if _playing else 0


func begin_intro() -> void:
	_end_animation_clock()
	_playing = true
	_animation_tick = 0
	_next_step = 0                                   # here: the number of beam pictures shown so far
	animate_to(0)


func play_intro() -> void:
	if not is_inside_tree():
		return
	begin_intro()
	_own_clock = TickMeter.new()
	_own_tick = 0
	set_process(true)
	await animation_finished


## The beam picture of every tick: picture `k` (0 .. 2 * 12 - 1) from tick `k * ticks_per_step` on, then the final picture
## (the beam straight up, the blip drawn) when the second turn is over.
func animate_to(tick: int) -> void:
	if not _playing:
		return
	var sweep: Dictionary = spec["sweep"]
	var steps: int = sweep["pics"].size()
	var per_step: int = sweep["ticks_per_step"]
	var total := int(sweep["revolutions"]) * steps
	_animation_tick = mini(tick, total * per_step)
	while _next_step < total and _next_step * per_step <= tick:
		_show_beam(_next_step % steps)
		_next_step += 1
	animation_advanced.emit()
	if tick >= total * per_step:
		_show_beam(0)
		_finish()


func skip_animation() -> void:
	if _playing:
		_end_animation_clock()
		items.clear()
		_build()
		_finish()


func _show_beam(step: int) -> void:
	items.clear()
	add_spec_items(spec["items"])
	_add_beam(step)
	if step == 0:
		_add_blip(_blip_frames().size() - 1)
	if step == blip_step():
		sfx_requested.emit(Catalog.sfx_catalog().name_of(blip_sfx()))
	queue_redraw()
